import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/conversation.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../services/audio/audio_engine_service.dart';
import '../../services/audio/audio_queue_manager.dart';
import '../../services/audio/playback_buffer_manager.dart';
import '../../services/audio/vad_processor.dart';
import '../../services/gateway/gateway_client.dart';
import '../../services/gateway/gateway_protocol.dart' as gw;
import '../../services/logging/app_logger.dart';

/// ============================================================================
/// AUDIO PLAYBACK LIFECYCLE ARCHITECTURE
/// ============================================================================
///
/// CRITICAL PRINCIPLE: Audio playback is driven ONLY by incoming audio chunks.
///
/// RULES:
/// 1. Each audioOut event resets a 2000ms silence timer via _resetSilenceTimer()
/// 2. If no chunk arrives for 2000ms, _finalizePlayback() is called automatically
/// 3. transcriptFinal events do NOT stop, clear, or affect audio playback
/// 4. Text completion != Audio completion (TTS may still be streaming)
/// 5. Playback state machine: IDLE → PLAYING → FINISHING → IDLE
///
/// EDGE CASES HANDLED:
/// - Network jitter: Timer resets on each chunk, no matter the delay
/// - Long responses: Timer keeps resetting while audio streams
/// - Rapid responses: New chunks cancel previous timer, continue playing
/// - Slow streaming: Full response plays regardless of gaps between chunks
///
/// RESULT: Full AI responses ALWAYS play completely, never truncated.
/// ============================================================================

enum VoiceUiState {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  error,
  reconnecting,
  stopped,
}

/// Audio playback state machine - driven ONLY by incoming audio chunks.
/// Never affected by text events (transcriptFinal).
enum AudioPlaybackState {
  idle, // No audio playing
  playing, // Actively receiving and playing chunks
  finishing, // Last chunk received, draining buffer
}

class VoiceSessionControllerV2 extends ChangeNotifier {
  // Dependencies
  final IGatewayClient gateway;
  final IAudioEngine audio;
  final AppLogger logger = AppLogger.instance;
  final ConversationRepository _conversationRepo = ConversationRepository();
  final Uuid _localUuid = const Uuid();

  // Configuration
  final bool preferBinaryAudio;
  final VadSensitivity vadSensitivity;

  // Mode management
  bool _isAudioModeEnabled = true; // Audio mode active by default

  // Session state
  VoiceUiState _uiState = VoiceUiState.idle;
  bool _sessionActive = false;
  bool _serverReady = false;

  // Reconnection state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts =
      20; // Increased from 5 for long sessions
  static const Duration _baseReconnectDelay =
      Duration(seconds: 1); // Reduced from 2s for faster recovery
  Timer? _reconnectTimer;

  // Stored for reconnect
  Uri? _lastGatewayUrl;
  String? _lastFirebaseToken;
  Map<String, dynamic>? _lastSessionConfig;

  // Components
  late VadProcessor _vad;
  late AudioQueueManager _audioQueue;
  late PlaybackBufferManager _playbackBuffer;

  // Timers
  Timer? _sendLoopTimer; // Send audio every 10ms
  Timer? _playbackDrainTimer; // Drain playback buffer every 20ms
  Timer? _serverReadyTimer;
  Timer? _silenceDetectionTimer; // Detect silence and send turnComplete
  Timer? _assistantDoneTimer; // Return UI to idle after assistant finishes
  Timer? _audioStopTimer; // Auto-stop playback after audio finishes

  // Silence detection for auto-turnComplete
  DateTime _lastAudioFrameTime = DateTime.now();
  DateTime? _lastAiAudioReceivedTime;
  bool _turnCompleteAlreadySent = false;
  static const Duration _silenceThreshold =
      Duration(seconds: 2); // 2 seconds of silence - allow natural pauses
  StreamSubscription<gw.GatewayEvent>? _gatewayEventSub;
  StreamSubscription<List<ChatMessage>>? _messageStreamSub;

  // State info
  String userTranscriptPartial = '';
  String userTranscriptFinal = '';
  String userDraftText = '';
  bool isUserDraftEditing = false;
  bool _textTurnInFlight = false;
  String _lastSentUserText = '';
  DateTime? _lastSentUserAt;
  String assistantTextPartial = '';
  String assistantTextFinal = '';
  String? lastError;
  bool showReconnectPrompt = false;

  // Conversation management
  Conversation? _activeConversation;
  final List<ChatMessage> _messages = [];

  // Assistant message de-duplication for streaming/final updates
  String? _lastAssistantMessageId;
  String _lastAssistantMessageText = '';
  DateTime? _lastAssistantMessageAt;

  bool _transcribingPending = false;
  bool get isTranscribingPending => _transcribingPending;

  bool _aiMuted = false;
  bool get isAiMuted => _aiMuted;

  // Audio playback state machine - driven ONLY by incoming audio chunks
  AudioPlaybackState _audioPlaybackState = AudioPlaybackState.idle;
  static const Duration _audioSilenceTimeout = Duration(milliseconds: 10000);

  // Enforce monotonic created_at for message ordering
  DateTime? _lastMessageTimestamp;

  // Live transcript tracking (for draft merge while editing)
  String _liveUserTranscript = '';
  String _lastCommittedTranscript =
      ''; // Track what's been added to userDraftText

  // VAD turn-complete detection
  bool _inUserUtterance = false;
  int _silenceFramesAfterSpeech = 0;
  static const int _silenceFramesToEnd = 15; // ~300ms at 20ms frames

  // Metrics
  int capturedChunks = 0;
  int sentChunks = 0;
  int receivedAudioChunks = 0;

  VoiceSessionControllerV2({
    required this.gateway,
    required this.audio,
    this.preferBinaryAudio = true,
    this.vadSensitivity = VadSensitivity.medium,
  }) {
    _vad = VadProcessor(sensitivity: vadSensitivity);
    _audioQueue = AudioQueueManager();
    _playbackBuffer = PlaybackBufferManager();
  }

  VoiceUiState get uiState => _uiState;

  /// Check if audio mode is enabled (mic is active)
  bool get isAudioModeEnabled => _isAudioModeEnabled;

  /// Get conversation messages (full chat history)
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Get active conversation
  Conversation? get activeConversation => _activeConversation;

  /// Start a voice session.
  Future<void> start({
    required Uri gatewayUrl,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    if (_sessionActive) {
      logger.warn('voice.session_already_running');
      return;
    }

    try {
      _setState(VoiceUiState.connecting);

      _lastGatewayUrl = gatewayUrl;
      _lastFirebaseToken = firebaseIdToken;
      _lastSessionConfig = sessionConfig;
      _reconnectAttempts = 0;

      logger.info('voice.connecting_to_gateway', data: {
        'url': gatewayUrl.toString(),
      });

      // Initialize conversation BEFORE gateway connection
      await _initializeConversation();
      logger.info('voice.conversation_initialized', data: {
        'conversation_id': _activeConversation?.id,
      });

      await gateway
          .connect(
        url: gatewayUrl,
        firebaseIdToken: firebaseIdToken,
        sessionConfig: sessionConfig,
        conversationId: _activeConversation?.id,
      )
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Gateway connection timeout');
      });

      logger.info('voice.gateway_connected_successfully');

      _sessionActive = true;
      _serverReady = false;

      _setupGatewayEventListener();

      // Initialize audio playback for AI responses
      try {
        await audio.playback.setup();
        logger.info('voice.playback_initialized');
      } catch (e) {
        logger.error('voice.playback_setup_failed', error: e);
      }

      // Start audio loops immediately
      _startSendLoop();
      _startPlaybackDrainLoop();

      // Force server ready immediately - no waiting
      _serverReady = true;
      _setState(VoiceUiState.idle);

      logger.info('voice.session_started', data: {
        'session_active': _sessionActive,
        'server_ready': _serverReady,
        'gateway_connected': gateway.isConnected,
      });
    } catch (e) {
      lastError = 'Failed to start session: $e';
      logger.error('voice.start_failed', error: e);
      _setState(VoiceUiState.error);
      await _cleanup();
    }
  }

  /// Stop session gracefully.
  Future<void> stop() async {
    logger.info('voice.stop_called', data: {
      'state': uiState.toString(),
    });

    _sessionActive = false;
    showReconnectPrompt = false;

    try {
      await _cleanup();
      _setState(VoiceUiState.stopped);
    } catch (e) {
      logger.error('voice.stop_error', error: e);
    }
  }

  /// Start mic capture only (session already connected)
  void startMicCapture() {
    logger.info('voice.startMicCapture_called', data: {
      'session_active': _sessionActive,
      'current_state': _uiState.toString(),
    });

    if (!_sessionActive) {
      logger.error('voice.mic_start_no_session');
      lastError = 'Session not active. Try restarting the app.';
      notifyListeners();
      return;
    }

    // Reset silence detection for new utterance
    _lastAudioFrameTime = DateTime.now();
    _turnCompleteAlreadySent = false;
    _startSilenceDetection();

    _startMicCapture();
    _setState(VoiceUiState.listening);
    _transcribingPending = false;
    logger.info('voice.mic_capture_started');
  }

  /// Stop mic capture only (keep session alive)
  void stopMicCapture() {
    try {
      audio.capture.stop();
      _silenceDetectionTimer?.cancel();

      // Send turnComplete to Vertex to end the turn
      if (!_turnCompleteAlreadySent && gateway.isConnected && _serverReady) {
        unawaited(gateway.sendTurnComplete());
        _turnCompleteAlreadySent = true;
        logger.info('voice.turn_complete_sent_on_mic_stop');
      }

      // Show transcribing indicator until final transcript arrives
      _transcribingPending = true;
      notifyListeners();

      _setState(VoiceUiState.idle);
      logger.info('voice.mic_stopped');
    } catch (e) {
      logger.error('voice.mic_stop_failed', error: e);
    }
  }

  /// Save/submit the current transcript to database
  /// This is called when user confirms the transcript by pressing send
  Future<void> submitTranscript(String textToSubmit) async {
    if (textToSubmit.trim().isEmpty) {
      logger.warn('voice.submit_empty_transcript');
      lastError = 'Cannot submit empty transcript';
      notifyListeners();
      return;
    }

    try {
      logger.info('voice.submitting_transcript', data: {
        'length': textToSubmit.length,
        'conversation_id': _activeConversation?.id,
      });

      if (_activeConversation == null) {
        throw Exception('No active conversation');
      }

      await _addOptimisticMessage(
        role: MessageRole.user,
        content: textToSubmit,
      );

      // Clear the draft and reset tracking
      userDraftText = '';
      userTranscriptPartial = '';
      userTranscriptFinal = '';
      _liveUserTranscript = '';
      _lastCommittedTranscript = ''; // Reset for next utterance

      logger.info('voice.transcript_submitted_successfully');
      notifyListeners();
    } catch (e) {
      lastError = 'Failed to submit transcript: $e';
      logger.error('voice.submit_transcript_failed', error: e);
      notifyListeners();
    }
  }

  /// Manual reconnect button.
  Future<void> reconnect() async {
    if (_lastGatewayUrl == null ||
        _lastFirebaseToken == null ||
        _lastSessionConfig == null) {
      logger.warn('voice.reconnect_missing_config');
      return;
    }

    _reconnectAttempts = 0;
    showReconnectPrompt = false;
    notifyListeners();

    await start(
      gatewayUrl: _lastGatewayUrl!,
      firebaseIdToken: _lastFirebaseToken!,
      sessionConfig: _lastSessionConfig!,
    );
  }

  void _setState(VoiceUiState newState) {
    if (_uiState != newState) {
      final previous = _uiState;
      _uiState = newState;
      logger.debug('voice.state_changed', data: {
        'from': previous.toString(),
        'to': newState.toString(),
      });
      notifyListeners();
    }
  }

  void _setupGatewayEventListener() {
    _gatewayEventSub?.cancel();
    _gatewayEventSub = gateway.events.listen(_onGatewayEvent, onError: (e) {
      lastError = 'Gateway event stream error: $e';
      logger.error('voice.gateway_event_stream_error', error: e);
      _setState(VoiceUiState.error);
    });
  }

  void _startMicCapture() {
    logger.info('voice.capture_starting');

    try {
      audio.capture.start(onPcm16k: (chunk) {
        capturedChunks++;
        _lastAudioFrameTime = DateTime.now();

        // Split large chunks into 20ms frames for real-time streaming
        // 16kHz mono PCM16 = 2 bytes per sample = 640 bytes per 20ms frame
        const int frameSize = 640; // 20ms at 16kHz, 2 bytes/sample

        if (chunk.length > frameSize) {
          // Large chunk - split into 20ms frames
          for (int i = 0; i < chunk.length; i += frameSize) {
            final end = (i + frameSize).clamp(0, chunk.length);
            final frame = chunk.sublist(i, end);
            final dropped = !_audioQueue.enqueue(
                frame, DateTime.now().millisecondsSinceEpoch);
            if (dropped) {
              logger.warn('voice.audio_frame_dropped', data: {
                'queue_depth': _audioQueue.queueDepthFrames,
              });
            }
          }

          // Log when splitting large chunks
          if (chunk.length > frameSize * 2) {
            logger.debug('voice.large_chunk_split', data: {
              'original_size': chunk.length,
              'frame_count': (chunk.length / frameSize).ceil(),
            });
          }
        } else {
          // Small chunk - enqueue as-is
          final dropped = !_audioQueue.enqueue(
              chunk, DateTime.now().millisecondsSinceEpoch);
          if (dropped) {
            logger.warn('voice.audio_frame_dropped', data: {
              'queue_depth': _audioQueue.queueDepthFrames,
            });
          }
        }

        // Log every 50th chunk to show audio is flowing
        if (capturedChunks % 50 == 0) {
          logger.debug('voice.audio_chunks_captured', data: {
            'total_chunks': capturedChunks,
            'chunk_size': chunk.length,
          });
        }
      });
      logger.info('voice.capture_started_successfully');
    } catch (e) {
      logger.error('voice.capture_start_failed', error: e);
      _setState(VoiceUiState.error);
    }
  }

  void _startSilenceDetection() {
    _silenceDetectionTimer?.cancel();

    // Check every 100ms if silence threshold has been exceeded
    _silenceDetectionTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) {
      final timeSinceLastFrame = DateTime.now().difference(_lastAudioFrameTime);

      // If silence threshold exceeded and we haven't sent turnComplete yet
      if (timeSinceLastFrame > _silenceThreshold && !_turnCompleteAlreadySent) {
        logger.info('voice.silence_detected_sending_turn_complete', data: {
          'silence_duration_ms': timeSinceLastFrame.inMilliseconds,
        });

        if (gateway.isConnected && _serverReady) {
          unawaited(gateway.sendTurnComplete());
          _turnCompleteAlreadySent = true;
          _silenceDetectionTimer?.cancel();
        }
      }
    });
  }

  void _startSendLoop() {
    _sendLoopTimer?.cancel();
    logger.info('voice.send_loop_starting');

    // 20ms matches our frame size; reduces CPU/log pressure vs 10ms.
    _sendLoopTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_sessionActive) return;

      // Only process audio when mic is actively listening
      if (_uiState != VoiceUiState.listening) return;

      // Send audio batch - will buffer if disconnected
      _sendAudioBatch();
    });
  }

  void _sendAudioBatch() {
    try {
      // Only send audio when mic is actively capturing (listening state)
      if (_uiState != VoiceUiState.listening) {
        return; // Don't send any audio if not actively recording
      }

      // If queue is backing up, send everything immediately to prevent batching
      // This prevents the native audio engine's large buffers from accumulating
      final isFull = _audioQueue.isQueueFull;
      final batch =
          isFull ? _audioQueue.dequeueAll() : _audioQueue.dequeueUpTo(2);

      if (batch.isEmpty) return;

      if (isFull) {
        logger.warn('voice.queue_full_flushing', data: {
          'frames_flushed': batch.length,
          'queue_depth': _audioQueue.queueDepthFrames,
        });
      }

      // During reconnection, keep buffering audio instead of trying to send
      if (!gateway.isConnected) {
        // Re-enqueue the frames we just dequeued
        for (final frame in batch.reversed) {
          _audioQueue.enqueue(frame.data, frame.timestampMs);
        }
        logger.debug('voice.audio_buffered_during_reconnect', data: {
          'queue_depth': _audioQueue.queueDepthFrames,
        });
        return; // Don't trigger disconnect handler, just buffer
      }

      // Send frames one by one in real-time
      for (final frame in batch) {
        sentChunks++;

        // Update last audio frame time for silence detection
        _lastAudioFrameTime = DateTime.now();

        // Log every 100th chunk sent
        if (sentChunks % 100 == 0) {
          logger.debug('voice.audio_batches_sent', data: {
            'total_sent': sentChunks,
            'queue_depth': _audioQueue.queueDepthFrames,
            'gateway_connected': gateway.isConnected,
          });
        }

        // Send as binary PCM frame for lowest latency.
        // Ignore backpressure here; gateway/client will surface disconnects via events.
        unawaited(
          gateway.sendAudioChunkBinary(frame.data).catchError((e) {
            // Prevent unhandled Future errors from crashing the Timer callback.
            logger.error('voice.send_audio_failed', error: e);
            _handleGatewayDisconnected(e.toString());
          }),
        );
      }
    } catch (e) {
      logger.error('voice.send_audio_failed', error: e);
    }
  }

  void _startPlaybackDrainLoop() {
    _playbackDrainTimer?.cancel();
    logger.info('voice.playback_drain_starting');

    _playbackDrainTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_sessionActive) return;
      // Don't block on _serverReady - let audio drain smoothly

      _drainPlaybackBuffer();
    });
  }

  void _drainPlaybackBuffer() {
    if (!_sessionActive) {
      logger.debug('voice.playback_drain_skipped_not_active');
      return;
    }

    if (_aiMuted) {
      // Only log occasionally to avoid spam
      if (_playbackBuffer.bufferDepthFrames > 0) {
        logger.debug('voice.playback_drain_skipped_muted', data: {
          'buffer_frames': _playbackBuffer.bufferDepthFrames,
        });
      }
      return;
    }

    try {
      final prebuffering = _playbackBuffer.isPrebuffering;
      final bufferFrames = _playbackBuffer.bufferDepthFrames;

      // Log prebuffering status (every 5 calls to avoid spam)
      if (prebuffering && bufferFrames % 5 == 0) {
        logger.debug('voice.playback_prebuffering', data: {
          'buffer_frames': bufferFrames,
          'buffer_ms': _playbackBuffer.bufferDepthMs,
          'target_frames':
              2, // 40ms prebuffer (reduced from 120ms for lower latency)
        });
      }

      final frames = _playbackBuffer.drainFrames();

      if (frames.isEmpty) {
        if (prebuffering && bufferFrames > 0) {
          // Still prebuffering - log every 10 cycles to avoid spam
          if (bufferFrames % 10 == 0) {
            logger.debug('voice.playback_prebuffering_status', data: {
              'buffer_frames': bufferFrames,
              'buffer_ms': _playbackBuffer.bufferDepthMs,
            });
          }
        }
        return;
      }

      // Successfully drained frames!
      logger.debug('voice.playback_draining', data: {
        'frame_count': frames.length,
        'buffer_depth_ms': _playbackBuffer.bufferDepthMs,
        'total_bytes': frames.fold<int>(0, (sum, f) => sum + f.data.length),
      });

      // Feed all frames to playback engine WITHOUT awaiting to prevent blocking
      int bytesFed = 0;
      for (final frame in frames) {
        // Fire-and-forget: don't await feed() to prevent blocking the drain loop
        // This allows the next iteration to happen quickly
        audio.playback.feed(frame.data).catchError((feedError) {
          logger.error('voice.playback_feed_failed', error: feedError);
          // Continue to next frame
        });
        bytesFed += frame.data.length;
      }

      logger.debug('voice.playback_drained', data: {
        'frame_count': frames.length,
        'total_bytes_fed': bytesFed,
      });
    } catch (e) {
      logger.error('voice.playback_drain_failed', error: e);
    }
  }

  /// ========================================================================
  /// AUDIO PLAYBACK LIFECYCLE - Driven ONLY by incoming audio chunks
  /// ========================================================================

  /// Reset the silence timer - called whenever a new audio chunk arrives.
  /// This is the ONLY mechanism that drives playback lifecycle.
  /// Audio stops 2000ms after the last chunk, regardless of text events.
  void _resetSilenceTimer() {
    // Cancel any existing timer
    _audioStopTimer?.cancel();

    // Update state to PLAYING if not already
    if (_audioPlaybackState != AudioPlaybackState.playing) {
      _audioPlaybackState = AudioPlaybackState.playing;
      logger.debug('voice.playback_state_changed', data: {'state': 'playing'});
    }

    // Schedule finalization after silence timeout
    _audioStopTimer = Timer(_audioSilenceTimeout, () {
      logger.info('voice.audio_silence_detected', data: {
        'timeout_ms': _audioSilenceTimeout.inMilliseconds,
      });
      _finalizePlayback();
    });
  }

  /// Finalize playback - called after audio silence timeout expires.
  /// Stops audio output, clears buffers, and resets state to IDLE.
  void _finalizePlayback() {
    if (_audioPlaybackState == AudioPlaybackState.idle) {
      return; // Already finalized
    }

    logger.info('voice.finalizing_playback', data: {
      'previous_state': _audioPlaybackState.toString(),
    });

    // Transition to finishing state
    _audioPlaybackState = AudioPlaybackState.finishing;

    // Clear playback buffer
    _playbackBuffer.clear();

    // Reset audio chunk counter for next turn
    receivedAudioChunks = 0;

    // Stop audio output
    try {
      audio.playback.stop();
      logger.debug('voice.playback_stopped');
    } catch (e) {
      logger
          .debug('voice.playback_stop_ignored', data: {'error': e.toString()});
    }

    // Reset audio engine for next turn (allows re-initialization)
    unawaited(audio.playback.cleanup().then((_) {
      logger.debug('voice.playback_engine_reset_for_next_turn');
    }).catchError((e) {
      logger
          .debug('voice.playback_cleanup_error', data: {'error': e.toString()});
    }));

    // Return to idle state
    _audioPlaybackState = AudioPlaybackState.idle;

    // Update UI state if still speaking
    if (_uiState == VoiceUiState.speaking) {
      _setState(VoiceUiState.idle);
    }

    logger.info('voice.playback_finalized');
  }

  void _handleGatewayDisconnected(String reason) {
    if (!_sessionActive) return;

    // Stop sending immediately.
    _sendLoopTimer?.cancel();
    _serverReady = false;

    lastError = reason;
    logger.warn('voice.gateway_disconnected', data: {
      'reason': reason,
    });

    // Trigger existing reconnect logic.
    _scheduleReconnect();
  }

  void _onGatewayEvent(gw.GatewayEvent ev) {
    logger.debug('voice.gateway_event', data: {
      'type': ev.type.toString(),
      'seq': ev.seq,
      'payload_keys': ev.payload.keys.toList(),
    });

    switch (ev.type) {
      case gw.GatewayEventType.sessionState:
        final state = ev.payload['state'] as String?;

        if (state == 'thinking') {
          _setState(VoiceUiState.thinking);
          logger.info('voice.server_thinking');
        } else if (state == 'ready') {
          _serverReady = true;
          _serverReadyTimer?.cancel();
          // Don't auto-start listening - wait for user to press mic button
          logger.info('voice.server_ready');
        } else if (state == 'listening') {
          _serverReady = true;
          _serverReadyTimer?.cancel();
          // Don't auto-start listening - wait for user to press mic button
          logger.info('voice.server_listening');
        }
        break;

      case gw.GatewayEventType.audioOut:
        if (_aiMuted) {
          logger.info('voice.ai_audio_muted_skipped');
          return;
        }
        receivedAudioChunks++;
        final b64 = ev.payload['data'] as String?;
        if (b64 == null || b64.isEmpty) {
          logger.warn('voice.ai_audio_empty');
          return;
        }
        try {
          final audioBytes = base64Decode(b64);
          _playbackBuffer.enqueueAiAudio(Uint8List.fromList(audioBytes));

          // Track last audio received time for metrics
          _lastAiAudioReceivedTime = DateTime.now();

          // === CRITICAL: Re-setup audio engine on FIRST chunk after finalization ===
          // After previous turn ends, audio engine is cleaned up.
          // When first audio chunk arrives, re-initialize it for next turn.
          if (_audioPlaybackState == AudioPlaybackState.idle &&
              receivedAudioChunks == 1) {
            unawaited(audio.playback.setup().then((_) {
              logger.debug('voice.playback_reinitialized_for_new_turn');
            }).catchError((e) {
              logger.warn('voice.playback_reinit_failed', data: {
                'error': e.toString(),
              });
            }));
          }

          // === CRITICAL: Reset silence timer on EVERY audio chunk ===
          // This is the ONLY driver of playback lifecycle.
          // Audio stops after silence timeout or audioStop event.
          // transcriptFinal events do NOT affect playback.
          _resetSilenceTimer();

          // Transition to speaking state when first audio chunk arrives
          if (_uiState == VoiceUiState.thinking) {
            _setState(VoiceUiState.speaking);
            logger.info('voice.state_transition_thinking_to_speaking');
          }

          logger.info('voice.ai_audio_received', data: {
            'size_bytes': audioBytes.length,
            'buffer_depth_ms': _playbackBuffer.bufferDepthMs,
            'buffer_frames': _playbackBuffer.bufferDepthFrames,
            'is_prebuffering': _playbackBuffer.isPrebuffering,
            'session_active': _sessionActive,
            'ai_muted': _aiMuted,
            'playback_state': _audioPlaybackState.toString(),
          });
        } catch (e) {
          logger.error('voice.ai_audio_decode_failed', error: e);
        }
        break;

      case gw.GatewayEventType.audioStop:
        // Gateway signals to stop playback immediately (barge-in / flush)
        logger.info('voice.audio_stop_requested', data: {
          'playback_state': _audioPlaybackState.toString(),
        });
        _finalizePlayback();
        break;

      case gw.GatewayEventType.userTranscriptPartial:
        userTranscriptPartial = ev.payload['text'] as String? ?? '';
        logger.debug('voice.transcript_partial_received', data: {
          'text': userTranscriptPartial,
          'length': userTranscriptPartial.length,
        });
        _applyUserTranscriptUpdate(userTranscriptPartial, isFinal: false);
        notifyListeners();
        break;

      case gw.GatewayEventType.userTranscriptFinal:
        userTranscriptFinal = ev.payload['text'] as String? ?? '';
        logger.info('voice.transcript_final_received', data: {
          'text': userTranscriptFinal,
          'length': userTranscriptFinal.length,
        });
        _transcribingPending = false;
        // Keep the transcript visible - merge into draft
        if (userTranscriptFinal.isNotEmpty) {
          _applyUserTranscriptUpdate(userTranscriptFinal, isFinal: true);
        }
        // Don't clear partial - keep it visible for continuous experience
        notifyListeners();
        break;

      case gw.GatewayEventType.transcriptPartial:
        assistantTextPartial = ev.payload['text'] as String? ?? '';

        // Transition to speaking when assistant starts generating text
        if (assistantTextPartial.isNotEmpty &&
            (_uiState == VoiceUiState.thinking ||
                _uiState == VoiceUiState.idle)) {
          _setState(VoiceUiState.speaking);
        }

        logger.debug('voice.assistant_transcript_partial', data: {
          'text_length': assistantTextPartial.length,
          'text_preview': assistantTextPartial.substring(
              0, math.min(50, assistantTextPartial.length)),
        });
        notifyListeners();
        break;

      case gw.GatewayEventType.transcriptFinal:
        assistantTextFinal = ev.payload['text'] as String? ?? '';
        assistantTextPartial = '';
        logger.debug('voice.assistant_transcript_final', data: {
          'text_length': assistantTextFinal.length,
          'text_preview': assistantTextFinal.substring(
              0, math.min(50, assistantTextFinal.length)),
        });
        _textTurnInFlight = false;

        // === CRITICAL: transcriptFinal does NOT affect audio playback ===
        // Text completion != Audio completion
        // Playback is driven ONLY by incoming audio chunks via silence timer.
        // TTS audio may still be streaming after text is finalized.
        // Do NOT stop, clear, or reset anything related to audio here.

        logger.info('voice.transcript_final_text_complete', data: {
          'playback_state': _audioPlaybackState.toString(),
          'note': 'Audio playback continues independently',
        });

        // Persist assistant message to Supabase (dedupe/update if we get multiple finals)
        if (assistantTextFinal.isNotEmpty) {
          unawaited(_persistAssistantMessage(assistantTextFinal));
        }
        notifyListeners();
        break;

      case gw.GatewayEventType.error:
        final errorMsg = ev.payload['message'] as String? ?? 'Unknown error';
        lastError = errorMsg;
        _textTurnInFlight = false;
        logger.error('voice.gateway_error', data: {
          'message': errorMsg,
        });

        if (_isConnectionError(errorMsg)) {
          _handleGatewayDisconnected(errorMsg);
        } else {
          _setState(VoiceUiState.error);
        }
        break;

      default:
        // Ignore other gateway events for now.
        break;
    }
  }

  bool _isConnectionError(String message) {
    final keywords = [
      'websocket',
      'connection',
      'disconnected',
      'not connected',
      'network',
    ];
    final lower = message.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      logger.error('voice.reconnect_exhausted', data: {
        'attempts': _reconnectAttempts,
      });
      _setState(VoiceUiState.error);
      showReconnectPrompt = true;
      notifyListeners();

      // Full shutdown
      unawaited(_cleanup());
      return;
    }

    _reconnectAttempts++;
    final delay = _baseReconnectDelay * (1 << (_reconnectAttempts - 1));

    logger.info('voice.reconnect_scheduled', data: {
      'attempt': _reconnectAttempts,
      'delay_ms': delay.inMilliseconds,
    });

    _setState(VoiceUiState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_sessionActive) {
        unawaited(start(
          gatewayUrl: _lastGatewayUrl!,
          firebaseIdToken: _lastFirebaseToken!,
          sessionConfig: _lastSessionConfig!,
        ));
      }
    });
  }

  Future<void> _cleanup() async {
    logger.info('voice.cleanup_starting');

    // Stop timers
    _sendLoopTimer?.cancel();
    _playbackDrainTimer?.cancel();
    _serverReadyTimer?.cancel();
    _reconnectTimer?.cancel();
    _silenceDetectionTimer?.cancel();
    _audioStopTimer?.cancel();

    // Finalize playback state machine
    _audioPlaybackState = AudioPlaybackState.idle;

    // Cancel subscriptions
    await _gatewayEventSub?.cancel();
    await _messageStreamSub?.cancel();

    // Clear state
    _sessionActive = false;
    _serverReady = false;
    _audioQueue.clear();
    _playbackBuffer.clear();
    _vad.reset();
    _inUserUtterance = false;
    _silenceFramesAfterSpeech = 0;

    // Stop audio
    try {
      await audio.capture.stop();
    } catch (e) {
      logger.error('voice.capture_stop_failed', error: e);
    }

    try {
      await audio.playback.stop();
    } catch (e) {
      logger.error('voice.playback_stop_failed', error: e);
    }

    // Close gateway
    try {
      await gateway.close();
    } catch (e) {
      logger.error('voice.gateway_close_failed', error: e);
    }

    logger.info('voice.cleanup_complete');
  }

  /// Initialize conversation for the session
  Future<void> _initializeConversation() async {
    try {
      logger.info('voice.conversation_initializing');

      _activeConversation =
          await _conversationRepo.getOrCreateActiveConversation(
        title: 'Voice Conversation ${DateTime.now().toLocal()}',
      );

      logger.info('voice.conversation_created', data: {
        'conversation_id': _activeConversation!.id,
      });

      // Load existing messages
      final existingMessages = await _conversationRepo.getMessages(
        _activeConversation!.id,
      );
      _messages.clear();
      _messages.addAll(existingMessages);

      logger.info('voice.messages_loaded', data: {
        'count': existingMessages.length,
      });

      // Subscribe to real-time updates
      await _messageStreamSub?.cancel();
      _messageStreamSub = _conversationRepo
          .streamMessages(_activeConversation!.id)
          .listen((messages) {
        _messages
          ..clear()
          ..addAll(messages);
        notifyListeners();
      });

      logger.info('voice.conversation_initialized', data: {
        'conversation_id': _activeConversation!.id,
        'message_count': _messages.length,
      });
    } catch (e) {
      logger.error('voice.conversation_init_failed', error: e);
      // Continue without conversation persistence
      _activeConversation = null;
    }
  }

  /// Add message to conversation
  Future<void> _addMessageToConversation({
    required MessageRole role,
    required String content,
    MessageStatus status = MessageStatus.sent,
    String? id,
    DateTime? createdAt,
  }) async {
    if (_activeConversation == null) {
      logger.warn('voice.no_active_conversation', data: {
        'role': role.value,
        'attempting_reinit': true,
      });
      // Try to reinitialize conversation
      await _initializeConversation();
      if (_activeConversation == null) {
        logger.error('voice.conversation_reinit_failed');
        return;
      }
    }

    if (content.trim().isEmpty) return;

    try {
      final message = await _conversationRepo.addMessage(
        conversationId: _activeConversation!.id,
        role: role,
        content: content,
        status: status,
        id: id,
        createdAt: createdAt,
      );

      _upsertMessageInMemory(message);
      logger.info('voice.message_added', data: {
        'role': role.value,
        'content_length': content.length,
        'conversation_id': _activeConversation!.id,
      });
    } catch (e) {
      logger.error('voice.message_add_failed', error: e);
    }
  }

  Future<void> _addOptimisticMessage({
    required MessageRole role,
    required String content,
  }) async {
    if (_activeConversation == null) {
      await _initializeConversation();
      if (_activeConversation == null) return;
    }

    final now = _nextMessageTimestamp();
    final localId = _localUuid.v4();

    final optimistic = ChatMessage(
      id: localId,
      conversationId: _activeConversation!.id,
      role: role,
      content: content,
      timestamp: now,
      status: MessageStatus.sending,
    );

    _upsertMessageInMemory(optimistic);

    try {
      final persisted = await _conversationRepo.addMessage(
        conversationId: _activeConversation!.id,
        role: role,
        content: content,
        status: MessageStatus.sent,
        id: localId,
        createdAt: now,
      );

      _upsertMessageInMemory(persisted);
    } catch (e) {
      _upsertMessageInMemory(
        optimistic.copyWith(status: MessageStatus.error),
      );
      logger.error('voice.message_add_failed', error: e);
    }
  }

  Future<void> _persistAssistantMessage(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    // If we receive multiple transcriptFinal events for the same turn, prefer updating
    // the last assistant message instead of creating duplicates.
    final now = _nextMessageTimestamp();
    final recent = _lastAssistantMessageAt != null &&
        now.difference(_lastAssistantMessageAt!).inSeconds <= 20;

    final canUpdateExisting = recent &&
        _lastAssistantMessageId != null &&
        _lastAssistantMessageText.isNotEmpty &&
        (cleaned == _lastAssistantMessageText ||
            cleaned.startsWith(_lastAssistantMessageText) ||
            _lastAssistantMessageText.startsWith(cleaned));

    if (canUpdateExisting) {
      // Skip no-op duplicates
      if (cleaned == _lastAssistantMessageText) return;

      try {
        await updateMessageContent(
          messageId: _lastAssistantMessageId!,
          newContent: cleaned,
        );
        _lastAssistantMessageText = cleaned;
        _lastAssistantMessageAt = now;
        return;
      } catch (_) {
        // If update fails, fall back to insert.
      }
    }

    try {
      if (_activeConversation == null) {
        // Ensure we have a conversation before attempting to persist
        await _initializeConversation();
      }
      if (_activeConversation == null) return;

      final messageId = _localUuid.v4();
      final optimistic = ChatMessage(
        id: messageId,
        conversationId: _activeConversation!.id,
        role: MessageRole.assistant,
        content: cleaned,
        timestamp: now,
        status: MessageStatus.sending,
      );

      _upsertMessageInMemory(optimistic);

      final message = await _conversationRepo.addMessage(
        conversationId: _activeConversation!.id,
        role: MessageRole.assistant,
        content: cleaned,
        status: MessageStatus.sent,
        id: messageId,
        createdAt: now,
      );

      _upsertMessageInMemory(message);
      _lastAssistantMessageId = message.id;
      _lastAssistantMessageText = cleaned;
      _lastAssistantMessageAt = now;

      logger.info('voice.assistant_message_persisted', data: {
        'content_length': cleaned.length,
        'conversation_id': _activeConversation!.id,
      });
    } catch (e) {
      logger.error('voice.assistant_message_persist_failed', error: e);
    }
  }

  void setUserDraftEditing(bool editing) {
    if (isUserDraftEditing == editing) return;
    isUserDraftEditing = editing;
    notifyListeners();
  }

  void updateUserDraftText(String text) {
    userDraftText = text;
    notifyListeners();
  }

  /// Toggle between audio mode (voice input) and text-only mode
  void setAudioModeEnabled(bool enabled) {
    if (_isAudioModeEnabled == enabled) return;
    _isAudioModeEnabled = enabled;
    logger.info('voice.audio_mode_toggled', data: {
      'enabled': enabled,
    });
    notifyListeners();
  }

  Future<void> sendUserDraftMessage() async {
    final content = userDraftText.trim();
    if (content.isEmpty) return;

    if (_textTurnInFlight) {
      logger.warn('voice.text_turn_blocked_in_flight');
      return;
    }

    final now = DateTime.now();
    if (_lastSentUserText == content &&
        _lastSentUserAt != null &&
        now.difference(_lastSentUserAt!).inSeconds <= 5) {
      logger.warn('voice.text_turn_blocked_duplicate');
      return;
    }

    _textTurnInFlight = true;
    _lastSentUserText = content;
    _lastSentUserAt = now;

    // Ensure gateway/session is ready before sending text turn
    if (!gateway.isConnected || !_serverReady) {
      lastError = 'Session not ready yet. Please wait a moment and try again.';
      logger.warn('voice.text_turn_rejected_not_ready', data: {
        'gateway_connected': gateway.isConnected,
        'server_ready': _serverReady,
      });
      _textTurnInFlight = false;
      notifyListeners();
      return;
    }

    // Clear draft immediately so UI doesn't re-populate while sending
    userDraftText = '';
    userTranscriptPartial = '';
    userTranscriptFinal = '';
    _liveUserTranscript = '';
    _lastCommittedTranscript = '';
    isUserDraftEditing = false;
    notifyListeners();

    await _addOptimisticMessage(
      role: MessageRole.user,
      content: content,
    );

    // If the mic is still running, stop it so the next turn starts cleanly.
    if (_uiState == VoiceUiState.listening) {
      stopMicCapture();
    }

    // Log which path is being taken
    logger.info('voice.text_turn_sending', data: {
      'audio_mode': _isAudioModeEnabled,
      'content_length': content.length,
    });

    // Trigger AI response based on edited text
    try {
      await gateway.sendTextTurn(
        content,
        conversationId: _activeConversation?.id,
      );
      // Only set thinking if send was successful
      _setState(VoiceUiState.thinking);
    } catch (e) {
      _textTurnInFlight = false;
      logger.error('voice.text_turn_send_failed', error: e);
      _setState(VoiceUiState.error);
    }

    notifyListeners();
  }

  void clearUserDraft() {
    userDraftText = '';
    userTranscriptPartial = '';
    userTranscriptFinal = '';
    _liveUserTranscript = '';
    _lastCommittedTranscript = ''; // Reset committed tracker
    isUserDraftEditing = false;
    notifyListeners();
  }

  void toggleAiMute() {
    _aiMuted = !_aiMuted;
    if (_aiMuted) {
      // Muting: finalize playback immediately
      _audioStopTimer?.cancel();
      _finalizePlayback();
      logger.info('voice.ai_muted');
    } else {
      // Unmuting: reset buffer state so it can start fresh
      _playbackBuffer.resetPlaybackStart();
      logger.info('voice.ai_unmuted');
    }
    notifyListeners();
  }

  DateTime _nextMessageTimestamp() {
    var now = DateTime.now().toUtc();
    if (_lastMessageTimestamp != null && !now.isAfter(_lastMessageTimestamp!)) {
      now = _lastMessageTimestamp!.add(const Duration(milliseconds: 1));
    }
    _lastMessageTimestamp = now;
    return now;
  }

  void _applyUserTranscriptUpdate(String newText, {required bool isFinal}) {
    if (newText.isEmpty) return;

    logger.info('voice.apply_transcript_update', data: {
      'new_text_length': newText.length,
      'is_final': isFinal,
      'current_draft_length': userDraftText.length,
      'is_user_editing': isUserDraftEditing,
    });

    final previousLive = _liveUserTranscript;
    _liveUserTranscript = newText;

    if (isFinal) {
      // FINAL transcript - commit it to the accumulated draft
      // Only add text that hasn't been committed yet
      final uncommittedText = _extractDelta(_lastCommittedTranscript, newText);

      if (uncommittedText.isNotEmpty) {
        if (isUserDraftEditing) {
          // If user is editing, append carefully
          userDraftText = _mergeTranscript(userDraftText, uncommittedText);
        } else {
          // Append the new final text to accumulated draft
          userDraftText = _mergeTranscript(userDraftText, uncommittedText);
        }

        // Mark this text as committed
        _lastCommittedTranscript = newText;

        logger.info('voice.final_transcript_committed', data: {
          'new_text': uncommittedText,
          'full_draft': userDraftText,
        });
      }

      userTranscriptFinal = newText;
      userTranscriptPartial = newText; // Show final as partial for smooth UX
    } else {
      // PARTIAL transcript - just show it live, don't commit to draft yet
      // Display the partial for real-time feedback
      userTranscriptPartial = newText;

      logger.debug('voice.partial_transcript_received', data: {
        'text': newText,
      });
    }
  }

  String _extractDelta(String previous, String current) {
    if (previous.isEmpty) return current;
    if (current.startsWith(previous)) {
      return current.substring(previous.length).trimLeft();
    }
    return current;
  }

  /// Merge two transcript fragments
  String _mergeTranscript(String existing, String incoming) {
    final trimmedExisting = existing.trim();
    final trimmedIncoming = incoming.trim();
    if (trimmedExisting.isEmpty) return trimmedIncoming;
    if (trimmedIncoming.isEmpty) return trimmedExisting;

    final needsSpace = !trimmedExisting.endsWith(' ') &&
        !trimmedExisting.endsWith('\n') &&
        !trimmedExisting.endsWith('.') &&
        !trimmedExisting.endsWith('!') &&
        !trimmedExisting.endsWith('?') &&
        !trimmedExisting.endsWith(',');

    return needsSpace
        ? '$trimmedExisting $trimmedIncoming'
        : '$trimmedExisting$trimmedIncoming'; // Fixed: no space when needsSpace is false
  }

  /// Add or update message in local cache
  void _upsertMessageInMemory(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    notifyListeners();
  }

  /// Update message content (e.g., user edits transcript)
  Future<void> updateMessageContent({
    required String messageId,
    required String newContent,
  }) async {
    if (_activeConversation == null) {
      logger.warn('voice.update_no_conversation');
      return;
    }
    if (newContent.trim().isEmpty) return;

    try {
      logger.info('voice.updating_message', data: {
        'message_id': messageId,
        'conversation_id': _activeConversation!.id,
      });

      final updated = await _conversationRepo.updateMessage(
        messageId: messageId,
        content: newContent,
      );

      _upsertMessageInMemory(updated);
      logger.info('voice.message_updated', data: {
        'message_id': messageId,
        'content_length': newContent.length,
      });
    } catch (e) {
      logger.error('voice.message_update_failed', error: e);
    }
  }

  /// Generate and download conversation summary
  Future<ConversationSummary?> generateSummary() async {
    if (_activeConversation == null) return null;

    try {
      return await _conversationRepo.generateSummary(_activeConversation!.id);
    } catch (e) {
      logger.error('voice.summary_generation_failed', error: e);
      return null;
    }
  }

  /// Build context for AI with full conversation history
  String buildConversationContext() {
    if (_messages.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('Previous conversation context:');

    for (final message in _messages) {
      final speaker = message.role == MessageRole.user ? 'User' : 'Assistant';
      buffer.writeln('$speaker: ${message.content}');
    }

    return buffer.toString();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
