// lib/features/voice/voice_session_controller.dart
//
// Controller for the Voice Live experience.
// Responsibilities:
// - session state machine
// - receiving gateway events (ordered by seq, with gap detection logging)
// - applying incremental report patches
// - transcript + narrative preview
// - barge-in (audioStop) => flush playback immediately
// - playback jitter buffer (prebuffer + timed drain + drop-oldest)
// - uplink backpressure (bounded ring buffer + timed drain + drop-oldest)
// - emergency escalation => UI state + banner
// - affective state hook (emotion/urgency signal)
//
// NOTE: Best practice is to request Permission.microphone in the UI BEFORE calling start().
// This controller also requests it at the start() entry as a safety net.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/adverse_event_report.dart';
import '../../services/audio/audio_engine_service.dart';
import '../../services/gateway/gateway_client.dart';
import '../../services/gateway/gateway_protocol.dart';
import '../../services/logging/app_logger.dart';
import 'vad/audio_vad.dart';

enum VoiceUiState { 
  ready, 
  connecting, 
  listening, 
  speaking, 
  processing, 
  emergency, 
  stopped, 
  error,
  reconnecting,  // NEW: Attempting to reconnect
}

class VoiceSessionController extends ChangeNotifier {
  final IGatewayClient gateway;
  final IAudioEngine audio;
  final AppLogger _logger = AppLogger.instance;

  VoiceUiState uiState = VoiceUiState.ready;
  
  // Reconnection state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  Uri? _lastGatewayUrl;
  String? _lastFirebaseToken;
  Map<String, dynamic>? _lastSessionConfig;

  AdverseEventReport draft = AdverseEventReport.empty();
  // Assistant captions (from modelTurn.text - what the assistant is saying)
  String assistantCaptionPartial = '';
  String assistantCaptionFinal = '';
  // User ASR transcripts (from user speech recognition - what the user said)
  // NOTE: We attempt to extract user ASR from Vertex Live API messages via:
  // - message.serverContent.inputTranscription
  // - message.serverContent.userTranscript
  // - message.serverContent.userTranscription
  // However, Vertex Live API may not provide these fields in all cases.
  // If these fields are unavailable, these will remain empty and only assistant captions will be shown.
  // For guaranteed user ASR, you may need a separate ASR pipeline (e.g., Google Speech-to-Text API).
  String userTranscriptPartial = '';
  String userTranscriptFinal = '';
  String narrativePreview = '';
  
  // Legacy fields for backward compatibility (deprecated - use assistantCaption* instead)
  @Deprecated('Use assistantCaptionPartial instead')
  String get transcriptPartial => assistantCaptionPartial;
  @Deprecated('Use assistantCaptionFinal instead')
  String get transcriptFinal => assistantCaptionFinal;
  String? emergencyBanner;
  String? lastError;
  bool showReconnectPrompt = false; // Expose to UI for "Tap to reconnect" banner

  // Affective state hook (optional future UI polish / safety)
  String? userEmotion; // e.g. 'stress', 'urgency', 'calm'
  double? userEmotionConfidence; // 0..1 (if provided)

  int _lastSeqApplied = 0;
  StreamSubscription<GatewayEvent>? _sub;
  bool _sessionStarted = false;
  bool _serverReady = false; // Track when server session is ready (listening state)
  bool _micCaptureActive = false; // Track if mic is actively capturing
  bool _micMuted = false; // Track if mic is muted (for push-to-talk)
  bool _turnCompleteSent = false; // Per-turn guard against duplicate turnComplete

  // Automatic silence detection for turn completion
  Timer? _silenceTimer;
  DateTime? _lastTranscriptTime;
  static const Duration _silenceThreshold = Duration(milliseconds: 1800); // 1.8 seconds of silence
  Timer? _serverReadyTimer;
  static const Duration _serverReadyTimeout = Duration(seconds: 15);

  // Audio-energy VAD (Voice Activity Detection) for more natural turn completion
  late AudioVad _vad;
  Timer? _vadCommitTicker;           // Periodic check for VAD commit
  
  // VAD sensitivity (can be changed by UI)
  VadSensitivity vadSensitivity = VadSensitivity.medium;
  
  // Latency instrumentation (Gemini Live quality metrics)
  int? _userSpeechStartMs;           // When user started speaking
  int? _userSpeechEndMs;             // When user stopped speaking (VAD endpoint)
  int? _turnCompleteSentMs;          // When turnComplete sent to server
  int? _firstAiAudioReceivedMs;      // When first AI audio chunk received
  int? _firstAiTextReceivedMs;       // When first AI transcript received
  int? _bargeInMs;                   // When user interrupted AI (barge-in detected)
  int? _playbackFlushedMs;           // When playback buffer flushed
  Map<String, int> latencyMetrics = {}; // Expose for observability
  
  // Helper for timestamp
  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // --- Audio backpressure: bounded queue + timed drain (drop-oldest) ---
  static const int _chunkMs = 20; // 20ms chunks from audio engine

  // Keep at most ~0.8s buffered to favor real-time latency.
  static const int _maxQueuedMs = 800;
  static const int _maxQueuedChunks = _maxQueuedMs ~/ _chunkMs;
  static const int _maxConsecutiveDrainErrors = 5;

  final Queue<_QueuedAudio> _audioQueue = Queue<_QueuedAudio>();
  Timer? _audioDrainTimer;
  bool _drainInProgress = false; // Single-flight guard to prevent overlapping async sends
  int _droppedAudioChunks = 0;
  int _consecutiveDrainErrors = 0;
  int _lastDrainErrorAtMs = 0;
  int _audioEnqueueCounter = 0;
  int _audioSendCounter = 0;

  // --- Playback jitter buffer: bounded queue + timed drain (drop-oldest) ---
  final Queue<Uint8List> _playbackQueue = Queue<Uint8List>();
  Timer? _playbackTimer;
  bool _playbackStarted = false; // True once initial buffer is filled
  bool _playbackDrainInProgress = false; // Single-flight guard to prevent overlapping async feeds

  static const int _playbackStartBufferMs = 120; // Lower prebuffer for faster first audio
  static const int _playbackDrainEveryMs = 20; // Match 20ms chunks
  static const int _maxPlaybackBufferedMs = 800; // Cap to ~0.8s (prefer real-time over lag)

  VoiceSessionController({
    required this.gateway,
    required this.audio,
    VadSensitivity? vadSensitivity,
  }) {
    // Initialize VAD with preset or default
    this.vadSensitivity = vadSensitivity ?? VadSensitivity.medium;
    _vad = AudioVad.preset(this.vadSensitivity);
  }
  
  /// Update VAD sensitivity (for UI settings)
  void updateVadSensitivity(VadSensitivity newSensitivity) {
    if (vadSensitivity == newSensitivity) return;
    
    vadSensitivity = newSensitivity;
    _vad = AudioVad.preset(newSensitivity);
    
    // If session is active, restart VAD with new settings
    if (_sessionStarted && _serverReady) {
      _stopVad();
      _startVad();
    }
    
    _logger.info('voice.vad_sensitivity_updated', data: {
      'sensitivity': newSensitivity.toString(),
    });
    
    notifyListeners();
  }

  /// Get count of dropped audio chunks (for observability/debugging)
  int get droppedAudioChunks => _droppedAudioChunks;

  /// Get current queue depth (for observability/debugging)
  int get queuedAudioChunks => _audioQueue.length;

  /// Get timestamp of last drain error (for observability/debugging)
  int get lastDrainErrorAtMs => _lastDrainErrorAtMs;

  Future<void> start({
    required Uri gatewayUrl,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
    bool isReconnect = false,
  }) async {
    // Store for reconnection
    _lastGatewayUrl = gatewayUrl;
    _lastFirebaseToken = firebaseIdToken;
    _lastSessionConfig = sessionConfig;
    _shouldReconnect = true; // Enable auto-reconnect
    showReconnectPrompt = false; // Clear any previous reconnect prompt
    
    try {
      _setState(isReconnect ? VoiceUiState.reconnecting : VoiceUiState.connecting);
      
      // RECONNECT RESYNC: Full state reset before starting
      if (isReconnect) {
        _logger.info('voice.reconnect_resync_start', data: {
          'attempt': _reconnectAttempts + 1,
          'max_attempts': _maxReconnectAttempts,
        });
        
        // Reset all state flags
        _sessionStarted = false;
        _serverReady = false;
        _micCaptureActive = false;
        _turnCompleteSent = false;
        _micMuted = false;
        
        // Clear all audio queues
        _audioQueue.clear();
        _playbackQueue.clear();
        _droppedAudioChunks = 0;
        _consecutiveDrainErrors = 0;
        
        // Reset VAD state
        final now = _nowMs();
        _vad.reset(nowMs: now);
        
        // Clear transcripts
        userTranscriptPartial = '';
        userTranscriptFinal = '';
        assistantCaptionPartial = '';
        assistantCaptionFinal = '';
        
        _logger.info('voice.reconnect_resync_complete', data: {
          'queues_cleared': true,
          'state_reset': true,
        });
      } else {
        _sessionStarted = false;
      }

      // ---- Permission check (UI should request permission before calling start()) ----
      // Controller only checks status to avoid duplicate prompts
      // Skip permission check if using NoOpAudioEngine (mock mode)
      final isNoOpAudio = audio is NoOpAudioEngine;
      if (!isNoOpAudio) {
        final status = await Permission.microphone.status;
        if (!status.isGranted) {
          lastError = 'Microphone permission not granted.';
          _logger.warn('voice.permission.denied', data: {'permission': 'microphone'});
          _setState(VoiceUiState.error);
          return;
        }
      }

      // Prepare audio playback first
      try {
        await audio.playback.prepare();
      } catch (e) {
        lastError = 'Failed to prepare audio playback: $e';
        _setState(VoiceUiState.error);
        return;
      }

      // Set up event listener BEFORE connecting (to catch sessionState events)
      _sub?.cancel();
      _sub = gateway.events.listen(_onGatewayEvent, onError: (e) {
        lastError = e.toString();
        _logger.error('voice.gateway_event_stream_error', error: e);
        _setState(VoiceUiState.error);
      });

      // Validate Firebase token before connecting
      if (firebaseIdToken.isEmpty) {
        lastError = 'Firebase ID token is required but was empty. Please ensure authentication is complete.';
        _logger.error('voice.firebase_token_empty', data: {
          'url': gatewayUrl.toString(),
        });
        _setState(VoiceUiState.error);
        await audio.playback.dispose();
        return;
      }

      // Connect to gateway
      try {
        _logger.info('voice.connecting_to_gateway', data: {
          'url': gatewayUrl.toString(),
          'has_token': firebaseIdToken.isNotEmpty,
          'token_length': firebaseIdToken.length,
        });
        await gateway.connect(
          url: gatewayUrl,
          firebaseIdToken: firebaseIdToken,
          sessionConfig: sessionConfig,
        );
        _logger.info('voice.gateway_connected', data: {
          'is_connected': gateway.isConnected,
          'url': gatewayUrl.toString(),
        });
      } catch (e) {
        lastError = 'Failed to connect to gateway: $e';
        _logger.error('voice.gateway_connection_failed', error: e);
        _setState(VoiceUiState.error);
        // Cleanup audio on connection failure
        await audio.playback.dispose();
        return;
      }

      _sessionStarted = true;
      _serverReady = false; // Will be set to true when we receive 'listening' state
      _micCaptureActive = false;
      _micMuted = false; // Start with mic unmuted (continuous mode)
      _turnCompleteSent = false;

      // Wait for server to be ready (sessionState: 'listening') before starting mic
      // This prevents sending audio before Vertex session is fully set up
      _logger.info('voice.waiting_for_server_ready', data: {
        'gateway_url': gatewayUrl.toString(),
      });
      
      _serverReadyTimer?.cancel();
      _serverReadyTimer = Timer(_serverReadyTimeout, () {
        if (!_serverReady && _sessionStarted) {
          _logger.warn('voice.server_ready_timeout', data: {
            'timeout_ms': _serverReadyTimeout.inMilliseconds,
          });
          unawaited(stop());
        }
      });

      // Note: Mic capture will start automatically when we receive sessionState: 'listening'
      // See _onGatewayEvent handler for sessionState case
    } catch (e) {
      // Catch-all for any unexpected errors
      lastError = 'Unexpected error during start: $e';
      _setState(VoiceUiState.error);
      _sessionStarted = false;
      // Ensure cleanup
      await stop();
    }
  }

  /// Toggle mic mute/unmute (for push-to-talk or explicit end-of-utterance)
  Future<void> toggleMic() async {
    if (_micMuted) {
      // Unmute: resume sending audio
      _micMuted = false;
      _turnCompleteSent = false;
      _logger.info('voice.mic_unmuted');
    } else {
      // Mute: stop sending audio and signal turnComplete
      _micMuted = true;
      _cancelSilenceTimer(); // Cancel auto-completion since user manually muted
      _logger.info('voice.mic_muted');
      await _sendTurnComplete(reason: 'manual_mic_mute');
    }
    notifyListeners();
  }

  /// Centralized turn completion sender (atomic guard, prevents duplicates)
  Future<void> _sendTurnComplete({required String reason}) async {
    if (_turnCompleteSent) {
      _logger.debug('voice.turn_complete_already_sent', data: {'reason': reason});
      return;
    }
    
    // Set guard BEFORE await (atomic)
    _turnCompleteSent = true;
    
    // LATENCY: Record when turnComplete sent
    _turnCompleteSentMs = _nowMs();
    
    _logger.info('voice.turn_complete_sending', data: {'reason': reason});
    
    try {
      await gateway.sendTurnComplete();
      _logger.info('voice.turn_complete_sent', data: {'reason': reason});
    } catch (e) {
      // Revert on failure to allow retry
      _turnCompleteSent = false;
      _turnCompleteSentMs = null;
      _logger.warn('voice.turn_complete_failed', data: {
        'reason': reason,
        'error': e.toString(),
      });
      rethrow;
    }
  }

  /// Start silence detection timer - auto-sends turnComplete after silence threshold
  /// NOTE: Currently DISABLED - VAD is primary. Kept as potential fallback mechanism.
  // ignore: unused_element
  void _startSilenceDetection() {
    _lastTranscriptTime = DateTime.now();
    _silenceTimer?.cancel(); // Cancel any existing timer
    
    _silenceTimer = Timer(_silenceThreshold, () async {
      // Check if we're still in a listening state and not already muted
      if (_sessionStarted && _serverReady && !_micMuted && _micCaptureActive && !_turnCompleteSent) {
        _logger.info('voice.silence_detected_auto_completing_turn', data: {
          'silence_duration_ms': DateTime.now().difference(_lastTranscriptTime!).inMilliseconds,
        });
        
        // Use centralized send method
        await _sendTurnComplete(reason: 'transcript_silence_fallback');
      }
    });
  }

  /// Cancel silence timer (when stopping session or muting)
  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _lastTranscriptTime = null;
  }

  /// Start audio-energy VAD for natural turn completion
  void _startVad() {
    final now = _nowMs();
    _vad.reset(nowMs: now);
    
    // Reset latency tracking for new turn
    _userSpeechStartMs = null;
    _userSpeechEndMs = null;
    _turnCompleteSentMs = null;
    _firstAiAudioReceivedMs = null;
    _firstAiTextReceivedMs = null;
    _bargeInMs = null;
    _playbackFlushedMs = null;
    
    _vadCommitTicker?.cancel();
    _vadCommitTicker = Timer.periodic(const Duration(milliseconds: 60), (_) async {
      final t = _nowMs();
      
      // Only commit if session is active and user turn is in progress
      if (!_sessionStarted || !_serverReady) return;
      if (_micMuted) return;
      if (_turnCompleteSent) return;
      
      // BARGE-IN: If user starts speaking while AI is speaking, interrupt playback
      if (uiState == VoiceUiState.speaking && _vad.inSpeech) {
        // LATENCY: Record barge-in timing
        _bargeInMs = t;
        
        _logger.info('voice.barge_in_detected', data: {
          'noise_floor_db': _vad.noiseFloorDb,
          'timestamp_ms': _bargeInMs,
        });
        
        // 1. Send barge-in signal to gateway (cancels server-side audio generation)
        try {
          await gateway.sendBargeIn();
          _logger.info('voice.barge_in_signal_sent');
        } catch (e) {
          _logger.warn('voice.barge_in_signal_failed', data: {'error': e.toString()});
        }
        
        // 2. Flush local playback immediately
        await _flushPlaybackBuffer();
        
        // LATENCY: Record playback flush timing
        _playbackFlushedMs = _nowMs();
        
        // Calculate and log barge-in recovery time
        if (_bargeInMs != null && _playbackFlushedMs != null) {
          final recoveryTime = _playbackFlushedMs! - _bargeInMs!;
          latencyMetrics['barge_in_recovery_ms'] = recoveryTime;
          
          _logger.info('voice.latency_barge_in', data: {
            'barge_in_recovery_ms': recoveryTime,
          });
        }
        
        _setState(VoiceUiState.listening);
        _turnCompleteSent = false; // Allow new turn to start
        return;
      }
      
      // Don't auto-commit while AI is speaking (unless barge-in above)
      if (uiState == VoiceUiState.speaking) return;
      
      if (_vad.shouldCommitTurnComplete(t)) {
        // LATENCY: Record speech end time
        _userSpeechEndMs = t;
        
        _logger.info('voice.vad_silence_commit', data: {
          'in_speech': _vad.inSpeech,
          'endpoint_armed': _vad.endpointArmed,
          'noise_floor_db': _vad.noiseFloorDb,
        });
        
        // Use centralized send method
        await _sendTurnComplete(reason: 'vad_silence');
        _vad.markTurnCompleted(nowMs: t);
      }
    });
    
    _logger.info('voice.vad_started', data: {
      'speech_db_threshold': _vad.speechDbAboveNoise,
      'commit_silence_ms': _vad.commitSilenceMs,
    });
  }

  /// Stop VAD monitoring
  void _stopVad() {
    _vadCommitTicker?.cancel();
    _vadCommitTicker = null;
    _logger.debug('voice.vad_stopped');
  }

  /// Get current mic mute state
  bool get isMicMuted => _micMuted;

  /// Enqueue audio chunk for backpressure-controlled sending
  void _enqueueAudioChunk(Uint8List pcm16k) {
    if (!_sessionStarted || !_serverReady || _micMuted) {
      // Only log rejection if it's unexpected (not just mic muted)
      if (!_micMuted) {
        _logger.warn('voice.audio_chunk_rejected', data: {
          'reason': !_sessionStarted 
              ? 'session_not_started' 
              : 'server_not_ready',
          'session_started': _sessionStarted,
          'server_ready': _serverReady,
          'mic_capture_active': _micCaptureActive,
        });
      }
      return;
    }

    // Drop-oldest to keep latency low
    while (_audioQueue.length >= _maxQueuedChunks) {
      _audioQueue.removeFirst();
      _droppedAudioChunks++;
    }

    // Store RAW bytes; encode later in drain (saves CPU if chunks are dropped)
    _audioQueue.add(_QueuedAudio(pcm16k));
    
    // Log audio enqueue only if there are issues (queue backing up or chunks dropped)
    _audioEnqueueCounter++;
    if (_audioEnqueueCounter % 200 == 0 && (_audioQueue.length > _maxQueuedChunks * 0.8 || _droppedAudioChunks > 0)) {
      _logger.warn('voice.audio_queue_status', data: {
        'queue_depth': _audioQueue.length,
        'max_allowed': _maxQueuedChunks,
        'total_enqueued': _audioEnqueueCounter,
        'total_dropped': _droppedAudioChunks,
      });
    }
    
    _ensureAudioDrain();
  }

  /// Ensure audio drain timer is running
  void _ensureAudioDrain() {
    if (_audioDrainTimer != null) return;

    _audioDrainTimer = Timer.periodic(
      const Duration(milliseconds: _chunkMs),
      (_) {
        if (!_sessionStarted) return;
        if (_drainInProgress) return; // Prevent overlapping async sends

        _drainInProgress = true;
        _drainOneAudioChunk().whenComplete(() {
          _drainInProgress = false;
        });
      },
    );
  }

  /// Stop audio drain and clear queue
  void _stopAudioDrain() {
    _audioDrainTimer?.cancel();
    _audioDrainTimer = null;
    _audioQueue.clear();
    _consecutiveDrainErrors = 0;
    _drainInProgress = false;
  }

  // --- Playback jitter buffer helpers ---

  /// Calculate bytes per 20ms at 24kHz, 16-bit mono
  int _bytesPer20ms24kMono16bit() {
    // 24,000 samples/sec * 2 bytes/sample * 0.02 sec = 960 bytes
    return (24000 * 2 * 20) ~/ 1000; // 960 bytes
  }

  /// Estimate buffered audio duration in milliseconds
  int _bufferedMs() {
    final perChunk = _bytesPer20ms24kMono16bit();
    if (perChunk == 0) return 0;
    final totalBytes = _playbackQueue.fold<int>(0, (sum, b) => sum + b.length);
    // Each chunk is ~20ms if you send fixed sizes; approximate:
    return (totalBytes / perChunk * 20).round();
  }

  /// Enqueue playback audio for jitter buffer
  void _enqueuePlayback(Uint8List pcm24k) {
    // Drop-oldest if we exceed max buffer (keep real-time, prefer current audio)
    while (_bufferedMs() > _maxPlaybackBufferedMs && _playbackQueue.isNotEmpty) {
      _playbackQueue.removeFirst();
    }
    _playbackQueue.add(pcm24k);
    _ensurePlaybackDrain();
  }

  /// Ensure playback drain timer is running
  void _ensurePlaybackDrain() {
    if (_playbackTimer != null) return;

    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: _playbackDrainEveryMs),
      (_) {
        if (_playbackQueue.isEmpty) {
          _playbackStarted = false;
          return;
        }

        // Wait until we have enough buffered audio to start (prebuffer)
        if (!_playbackStarted && _bufferedMs() < _playbackStartBufferMs) {
          return;
        }
        _playbackStarted = true;

        // Single-flight guard: prevent overlapping async feeds
        if (_playbackDrainInProgress) return;

        _playbackDrainInProgress = true;
        final chunk = _playbackQueue.removeFirst();
        audio.playback.feed(chunk).then((_) {
          _playbackDrainInProgress = false;
        }).catchError((e) {
          _playbackDrainInProgress = false;
          _logger.warn('voice.playback_feed_failed', data: {'error': e.toString()});
        });
      },
    );
  }

  /// Flush playback buffer (used for barge-in)
  Future<void> _flushPlaybackBuffer() async {
    _playbackQueue.clear();
    _playbackStarted = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    // Also flush device buffers (critical for barge-in)
    await audio.playback.stopNow();
  }

  /// Stop playback drain and clear queue
  void _stopPlaybackDrain() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackQueue.clear();
    _playbackStarted = false;
    _playbackDrainInProgress = false;
  }

  /// Drain one audio chunk from queue (called every 20ms by timer)
  Future<void> _drainOneAudioChunk() async {
    if (!_sessionStarted) {
      _stopAudioDrain();
      return;
    }

    if (_audioQueue.isEmpty) {
      // Auto-stop timer when queue is empty to keep controller quieter
      _stopAudioDrain();
      return;
    }

    final item = _audioQueue.removeFirst();

    try {
      // Send as binary WebSocket frame (33% faster than base64, lower latency)
      await gateway.sendAudioChunkBinary(item.pcm16k);
      
      // Log audio being sent to gateway (every 100th chunk - reduced frequency)
      _audioSendCounter++;
      if (_audioSendCounter % 100 == 0) {
        _logger.debug('voice.audio_chunk_sent_binary', data: {
          'total_sent': _audioSendCounter,
          'queue_depth': _audioQueue.length,
          'chunk_bytes': item.pcm16k.length,
        });
      }

      _consecutiveDrainErrors = 0;
    } catch (e) {
      _consecutiveDrainErrors++;
      _lastDrainErrorAtMs = DateTime.now().millisecondsSinceEpoch;

      // Drop this chunk (live-first: prefer current audio over perfect audio)
      _droppedAudioChunks++;

      _logger.warn('voice.audio_drain_failed', data: {
        'error': e.toString(),
        'queueDepth': _audioQueue.length,
        'dropped': _droppedAudioChunks,
        'consecutiveDrainErrors': _consecutiveDrainErrors,
      });

      // If the network/socket is consistently failing, flush the queue
      if (_consecutiveDrainErrors >= _maxConsecutiveDrainErrors) {
        _logger.warn('voice.audio_drain_flushing_queue', data: {
          'queueDepthBeforeFlush': _audioQueue.length,
        });
        _audioQueue.clear();
        _consecutiveDrainErrors = 0;
        
        // Show persistent failure prompt to user
        showReconnectPrompt = true;
        lastError = 'Connection unstable. Tap to reconnect.';
        notifyListeners();
      }
    }
  }

  /// Manual reconnect (called by UI)
  Future<void> reconnect() async {
    if (_lastGatewayUrl == null || _lastFirebaseToken == null || _lastSessionConfig == null) {
      _logger.warn('voice.reconnect_no_session_info');
      return;
    }
    
    _reconnectAttempts = 0; // Reset attempts for manual reconnect
    showReconnectPrompt = false;
    notifyListeners();
    
    await start(
      gatewayUrl: _lastGatewayUrl!,
      firebaseIdToken: _lastFirebaseToken!,
      sessionConfig: _lastSessionConfig!,
      isReconnect: true,
    );
  }

  /// Attempt automatic reconnect with exponential backoff
  Future<void> _attemptReconnect() async {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.error('voice.reconnect_max_attempts_reached', data: {
        'attempts': _reconnectAttempts,
      });
      _shouldReconnect = false;
      showReconnectPrompt = true; // Show UI prompt for manual reconnect
      _setState(VoiceUiState.error);
      notifyListeners();
      return;
    }
    
    _reconnectAttempts++;
    
    // Exponential backoff: 2s, 4s, 8s, 16s, 32s
    final delay = _baseReconnectDelay * (1 << (_reconnectAttempts - 1));
    
    _logger.info('voice.reconnect_scheduled', data: {
      'attempt': _reconnectAttempts,
      'delay_ms': delay.inMilliseconds,
    });
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!_shouldReconnect) return;
      
      await start(
        gatewayUrl: _lastGatewayUrl!,
        firebaseIdToken: _lastFirebaseToken!,
        sessionConfig: _lastSessionConfig!,
        isReconnect: true,
      );
    });
  }

  /// Check if error message indicates a connection error
  bool _isConnectionError(String errorMessage) {
    final connectionErrors = [
      'websocket',
      'connection',
      'network',
      'timeout',
      'unreachable',
      'no route to host',
      'connection refused',
      'connection failed',
    ];
    
    final lowerError = errorMessage.toLowerCase();
    return connectionErrors.any((pattern) => lowerError.contains(pattern));
  }

  Future<void> stop() async {
    _shouldReconnect = false; // Disable auto-reconnect on manual stop
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _logger.info('voice.stop_called', data: {
      'current_state': uiState.toString(),
      'session_started': _sessionStarted,
      'queue_depth': _audioQueue.length,
      'caller': StackTrace.current.toString().split('\n').take(4).join('\n'),
    });
    
    try {
      // Stop audio drain and clear queue immediately to prevent stale sends
      _stopAudioDrain();
      _audioQueue.clear(); // Clear any remaining queued audio
      _droppedAudioChunks = 0;
      _sessionStarted = false;
      _turnCompleteSent = false;

      // Cancel silence detection timer
      _cancelSilenceTimer();
      _serverReadyTimer?.cancel();
      _serverReadyTimer = null;
      
      // Stop VAD monitoring
      _stopVad();

      // Stop playback drain
      _stopPlaybackDrain();

      // Stop mic capture first
      _micCaptureActive = false;
      _serverReady = false;
      _micMuted = false;
      try {
        await _stopMicCapture();
      } catch (e) {
        _logger.warn('voice.capture_stop_failed', data: {'error': e.toString()});
      }

      // Send stop to gateway
      try {
        await gateway.sendStop();
      } catch (e) {
        _logger.warn('voice.gateway_stop_failed', data: {'error': e.toString()});
      }

      // Close gateway connection
      try {
        await gateway.close();
      } catch (e) {
        _logger.warn('voice.gateway_close_failed', data: {'error': e.toString()});
      }

      // Stop and flush playback
      try {
        await audio.playback.stopNow();
      } catch (e) {
        _logger.warn('voice.playback_stop_failed', data: {'error': e.toString()});
      }

      _setState(VoiceUiState.stopped);
    } catch (e) {
      // Ensure state is updated even if cleanup fails
      _setState(VoiceUiState.stopped);
      lastError = 'Error during stop: $e';
      _logger.error('voice.stop_failed', error: e);
      notifyListeners();
    }
  }

  void _onGatewayEvent(GatewayEvent ev) async {
    // Diagnostic: Log ALL events to debug server_ready issue
    _logger.info('voice.gateway_event_received_DEBUG', data: {
      'event_type': ev.type.toString(),
      'sequence': ev.seq,
      'payload_keys': ev.payload.keys.toList(),
      'server_ready_before': _serverReady,
      'session_started': _sessionStarted,
    });
    
    // Sequence gap detection and ordering guard
    if (ev.seq != 0) {
      // Drop out-of-order events
      if (ev.seq <= _lastSeqApplied) return;

      // Detect gaps (important for medical auditability)
      final expected = _lastSeqApplied + 1;
      if (_lastSeqApplied != 0 && ev.seq > expected) {
        _logger.warn('voice.sequence_gap_detected', data: {
          'expected': expected,
          'received': ev.seq,
          'gap': ev.seq - expected,
          'event_type': ev.type.toString(),
        });
        // Note: Large gaps might indicate lost aeDraftUpdate events
        // Consider requesting full draft snapshot if gap is very large (>10)
      }

      _lastSeqApplied = ev.seq;
    }

    // Affective hook: tolerate different payload shapes without requiring protocol churn
    _maybeUpdateAffective(ev.payload);

    switch (ev.type) {
      case GatewayEventType.sessionState: {
        final state = ev.payload['state'] as String? ?? '';
        final wasReconnecting = uiState == VoiceUiState.reconnecting;
        
        _logger.info('voice.sessionState_event_DEBUG', data: {
          'state': state,
          'session_started': _sessionStarted,
          'server_ready_before': _serverReady,
          'was_reconnecting': wasReconnecting,
        });
        
        if (state == 'listening') {
          _logger.info('voice.server_listening_state_received', data: {
            'current_session_started': _sessionStarted,
            'current_server_ready': _serverReady,
          });
          _setState(VoiceUiState.listening);
          _serverReady = true;
          _turnCompleteSent = false;
          _serverReadyTimer?.cancel();
          _serverReadyTimer = null;
          
          // RECONNECT RESYNC: Clear attempts on successful reconnect
          if (wasReconnecting) {
            _reconnectAttempts = 0;
            _logger.info('voice.reconnect_success', data: {
              'state': 'listening',
            });
          }
          
          _logger.info('voice.server_ready_SET_TO_TRUE_DEBUG');
          notifyListeners(); // ← ADDED: Ensure UI updates
          
          // Start VAD for energy-based turn completion
          _startVad();
          
          // Start mic capture now that server is ready
          _startMicCaptureIfNeeded();
          _logger.info('voice.after_startMicCaptureIfNeeded', data: {
            'mic_capture_active': _micCaptureActive,
            'server_ready': _serverReady,
            'session_started': _sessionStarted,
          });
        }
        if (state == 'speaking') {
          _cancelSilenceTimer(); // AI is responding
          _setState(VoiceUiState.speaking);
        }
        if (state == 'processing') _setState(VoiceUiState.processing);
        if (state == 'stopped') {
          _setState(VoiceUiState.stopped);
          _serverReady = false;
          _turnCompleteSent = false;
        }
        break;
      }

      case GatewayEventType.userTranscriptPartial: {
        final text = ev.payload['text'] as String? ?? '';
        userTranscriptPartial = text;
        _turnCompleteSent = false;
        // Transcript timer only used as FALLBACK when VAD is not active
        // VAD handles turn completion via energy detection (more reliable)
        // Only log final transcripts, not every partial update
        notifyListeners();
        break;
      }

      case GatewayEventType.userTranscriptFinal: {
        final text = ev.payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
          userTranscriptFinal = (userTranscriptFinal.isEmpty) ? text : '$userTranscriptFinal\n$text';
          userTranscriptPartial = '';
          _turnCompleteSent = false;
          _logger.info('voice.user_transcript_final_received', data: {
            'text_length': text.length,
            'sequence': ev.seq,
            'total_final_segments': userTranscriptFinal.split('\n').length,
          });
          // VAD is primary endpointer - transcript timer disabled when VAD active
          // Kept here only as documentation / potential fallback
          notifyListeners();
        }
        break;
      }

      case GatewayEventType.transcriptPartial: {
        // This is assistant caption (modelTurn.text), not user ASR
        final text = ev.payload['text'] as String? ?? '';
        assistantCaptionPartial = text;
        // Cancel silence timer - AI is responding
        _cancelSilenceTimer();
        // Only log final transcripts, not every partial update
        notifyListeners();
        break;
      }

      case GatewayEventType.transcriptFinal: {
        // This is assistant caption (modelTurn.text), not user ASR
        final text = ev.payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
          // LATENCY: Record first AI text received
          if (_firstAiTextReceivedMs == null) {
            _firstAiTextReceivedMs = _nowMs();
            
            if (_userSpeechEndMs != null) {
              final endToFirstText = _firstAiTextReceivedMs! - _userSpeechEndMs!;
              latencyMetrics['speech_end_to_first_text_ms'] = endToFirstText;
              
              _logger.info('voice.latency_first_text', data: {
                'speech_end_to_first_text_ms': endToFirstText,
              });
            }
          }
          
          assistantCaptionFinal = (assistantCaptionFinal.isEmpty) ? text : '$assistantCaptionFinal\n$text';
          assistantCaptionPartial = '';
          _logger.info('voice.assistant_caption_final_received', data: {
            'text': text,
            'text_length': text.length,
            'sequence': ev.seq,
            'total_final_segments': assistantCaptionFinal.split('\n').length,
          });
          notifyListeners();
        }
        break;
      }

      case GatewayEventType.narrativeUpdate: {
        // Accept either {"text": "..."} or {"patch": {"narrative": "..."}}
        if (ev.payload['text'] is String) {
          narrativePreview = ev.payload['text'] as String;
          draft = draft.applyJsonPatch({'narrative': narrativePreview});
        } else if (ev.payload['patch'] is Map) {
          final patch = (ev.payload['patch'] as Map).cast<String, dynamic>();
          draft = draft.applyJsonPatch(patch);
          narrativePreview = draft.narrative;
        }
        notifyListeners();
        break;
      }

      case GatewayEventType.aeDraftUpdate: {
        final patch = (ev.payload['patch'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        draft = draft.applyJsonPatch(patch);
        notifyListeners();
        break;
      }

      case GatewayEventType.audioOut: {
        // Payload: {"data": "<base64 pcm24k>"}
        final data = ev.payload['data'] as String?;
        if (data != null && data.isNotEmpty) {
          final bytes = base64Decode(data);
          
          // LATENCY: Record first AI audio received
          if (_firstAiAudioReceivedMs == null) {
            _firstAiAudioReceivedMs = _nowMs();
            
            // Calculate and log latency metrics
            if (_userSpeechEndMs != null) {
              final endToFirstAudio = _firstAiAudioReceivedMs! - _userSpeechEndMs!;
              latencyMetrics['speech_end_to_first_audio_ms'] = endToFirstAudio;
              
              if (_turnCompleteSentMs != null) {
                final turnCompleteToAudio = _firstAiAudioReceivedMs! - _turnCompleteSentMs!;
                latencyMetrics['turn_complete_to_first_audio_ms'] = turnCompleteToAudio;
              }
              
              _logger.info('voice.latency_first_audio', data: {
                'speech_end_to_first_audio_ms': endToFirstAudio,
                'turn_complete_to_first_audio_ms': latencyMetrics['turn_complete_to_first_audio_ms'],
              });
            }
          }
          
          // Cancel silence timer - AI is responding with audio
          _cancelSilenceTimer();
          // Only log empty audio responses (errors), not every chunk
          // Enqueue for jitter buffer (don't feed directly)
          _enqueuePlayback(Uint8List.fromList(bytes));
        } else {
          _logger.warn('voice.audio_response_empty', data: {'sequence': ev.seq});
        }
        break;
      }

      case GatewayEventType.audioStop: {
        // BARGE-IN: flush audio immediately (both queue and device buffers)
        // LATENCY: Record server-initiated barge-in
        if (_bargeInMs == null) {
          _bargeInMs = _nowMs();
        }
        
        // Use unawaited to avoid blocking the gateway event loop
        unawaited(_flushPlaybackBuffer().then((_) {
          _playbackFlushedMs = _nowMs();
          
          if (_bargeInMs != null && _playbackFlushedMs != null) {
            final recoveryTime = _playbackFlushedMs! - _bargeInMs!;
            latencyMetrics['barge_in_recovery_ms'] = recoveryTime;
            
            _logger.info('voice.latency_barge_in_server', data: {
              'barge_in_recovery_ms': recoveryTime,
            });
          }
        }));
        
        _setState(VoiceUiState.listening);
        break;
      }

      case GatewayEventType.emergency: {
        emergencyBanner = ev.payload['banner'] as String? ??
            'If you are experiencing severe symptoms, please seek urgent medical care.';
        _setState(VoiceUiState.emergency);
        break;
      }

      case GatewayEventType.error: {
        // Parse error from multiple possible formats
        final errorMessage = ev.payload['message'] as String? ?? 
                            ev.payload['error'] as String? ??
                            ev.payload['type'] as String? ??
                            'Unknown gateway error';
        final errorCode = ev.payload['code'] as String?;
        final errorType = ev.payload['type'] as String?;
        final originalType = ev.payload['_original_type'] as String?;
        lastError = errorMessage;
        
        _logger.error('voice.gateway_error_received', data: {
          'message': errorMessage,
          'code': errorCode,
          'type': errorType,
          'original_type': originalType,
          'sequence': ev.seq,
          'payload_keys': ev.payload.keys.where((k) => k != '_original_type').toList(),
          'session_started': _sessionStarted,
          'server_ready': _serverReady,
          'mic_capture_active': _micCaptureActive,
        });
        
        // Check if this is a transient error that we can recover from
        final isTransientError = errorType == 'TRANSIENT' || 
                                errorCode == 'TRANSIENT' ||
                                errorMessage.toLowerCase().contains('transient') ||
                                errorMessage.toLowerCase().contains('temporary');
        
        if (isTransientError) {
          // For transient errors, just log and continue - server should recover
          _logger.warn('voice.transient_error_continuing', data: {
            'error': errorMessage,
            'type': errorType,
          });
          // Don't change _serverReady or stop capture - let it continue
        } else {
          // For persistent errors, stop and potentially reconnect
          // Clear audio queue on error to prevent stale sends
          _audioQueue.clear();
          // Stop mic capture on error to prevent spam and resource waste
          _micCaptureActive = false;
          _serverReady = false;
          _micMuted = false;
          // Note: We do NOT set _sessionStarted = false here because the session
          // might still be partially active (WebSocket might reconnect, etc.)
          // Only stop() or dispose() should fully reset _sessionStarted.
          unawaited(_stopMicCapture());
          
          // Check if this is a connection error that should trigger reconnect
          if (_isConnectionError(errorMessage) && _shouldReconnect) {
            _logger.warn('voice.connection_error_triggering_reconnect', data: {
              'error': errorMessage,
            });
            unawaited(_attemptReconnect());
          } else {
            _setState(VoiceUiState.error);
          }
        }
        break;
      }

      case GatewayEventType.unknown: {
        // Log unknown event types for debugging but don't break the session
        _logger.debug('voice.unknown_event_type_ignored', data: {
          'original_type': ev.payload['_original_type'],
          'sequence': ev.seq,
          'payload_keys': ev.payload.keys.where((k) => k != '_original_type').toList(),
          'payload_sample': ev.payload.keys
              .where((k) => k != '_original_type')
              .take(5)
              .map((k) => '$k=${ev.payload[k]}')
              .join(', '),
        });
        // Do nothing - just ignore unknown events
        break;
      }
    }
  }

  void clearEmergency() {
    emergencyBanner = null;
    if (uiState == VoiceUiState.emergency) {
      _setState(VoiceUiState.listening);
    }
  }

  void _maybeUpdateAffective(Map<String, dynamic> payload) {
    // Accept multiple possible shapes without hard dependency on a new event type:
    // 1) { emotion: "stress", emotion_confidence: 0.8 }
    // 2) { affect: { label: "...", confidence: 0.7 } }
    // 3) { userEmotion: "...", confidence: ... }
    final direct = payload['emotion'] ?? payload['userEmotion'];
    if (direct is String && direct.trim().isNotEmpty) {
      userEmotion = direct.trim();
      final c = payload['emotion_confidence'] ?? payload['confidence'];
      if (c is num) userEmotionConfidence = c.toDouble();
      return;
    }

    final affect = payload['affect'];
    if (affect is Map) {
      final label = affect['label'] ?? affect['emotion'];
      if (label is String && label.trim().isNotEmpty) {
        userEmotion = label.trim();
      }
      final conf = affect['confidence'];
      if (conf is num) {
        userEmotionConfidence = conf.toDouble();
      }
    }
  }

  bool get hasAttestation {
    final name = draft.reporterAttestationName?.trim() ?? '';
    final signature = draft.reporterDigitalSignature?.trim() ?? '';
    final timestamp = draft.finalAttestationTimestampIso?.trim() ?? '';
    return name.isNotEmpty && signature.isNotEmpty && timestamp.isNotEmpty;
  }

  bool get canSubmit => draft.criteria.isValid && hasAttestation;

  void setAttestation({required String name}) {
    final trimmed = name.trim();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final signature = '$trimmed|$timestamp';

    draft = draft.copyWith(
      reporterAttestationName: trimmed,
      reporterDigitalSignature: signature,
      finalAttestationTimestampIso: timestamp,
    );

    _logger.info('voice.attestation_set', data: {'has_name': trimmed.isNotEmpty});
    notifyListeners();
  }

  void clearAttestation() {
    draft = draft.copyWith(
      reporterAttestationName: null,
      reporterDigitalSignature: null,
      finalAttestationTimestampIso: null,
    );
    _logger.info('voice.attestation_cleared');
    notifyListeners();
  }

  /// Start mic capture if server is ready and not already capturing
  Future<void> _startMicCaptureIfNeeded() async {
    _logger.debug('voice._startMicCaptureIfNeeded_called', data: {
      'mic_capture_active': _micCaptureActive,
      'session_started': _sessionStarted,
      'server_ready': _serverReady,
    });
    
    if (_micCaptureActive || !_sessionStarted || !_serverReady) {
      _logger.warn('voice._startMicCaptureIfNeeded_early_return', data: {
        'reason': _micCaptureActive ? 'already_active' : 
                  !_sessionStarted ? 'session_not_started' : 'server_not_ready',
        'mic_capture_active': _micCaptureActive,
        'session_started': _sessionStarted,
        'server_ready': _serverReady,
      });
      return;
    }
    
    try {
      _micCaptureActive = true;
      _logger.info('voice.starting_audio_capture');
      await audio.capture.start(onPcm16k: (pcm16k) {
        // Feed PCM to VAD for energy-based turn completion
        final now = _nowMs();
        _vad.processPcm16(pcm16k, nowMs: now);
        
        // LATENCY: Track when user starts speaking (first speech detected)
        if (_userSpeechStartMs == null && _vad.inSpeech) {
          _userSpeechStartMs = now;
          _logger.info('voice.latency_speech_start', data: {
            'timestamp_ms': _userSpeechStartMs,
          });
        }
        
        // Enqueue audio chunk (will be drained at fixed 20ms cadence)
        _enqueueAudioChunk(pcm16k);
      });
      _logger.info('voice.audio_capture_started', data: {
        'mic_capture_active': _micCaptureActive,
      });
    } catch (e) {
      _micCaptureActive = false;
      lastError = 'Failed to start audio capture: $e';
      _logger.error('voice.audio_capture_start_failed', error: e);
      _setState(VoiceUiState.error);
    }
  }

  /// Stop mic capture
  Future<void> _stopMicCapture() async {
    if (!_micCaptureActive) return;
    
    try {
      _micCaptureActive = false;
      await audio.capture.stop();
      _logger.info('voice.audio_capture_stopped');
    } catch (e) {
      _logger.warn('voice.audio_capture_stop_failed', data: {'error': e.toString()});
    }
  }

  void _setState(VoiceUiState next) {
    if (uiState == next) return;
    uiState = next;
    
    // Clear audio queue on error state to prevent stale sends
    if (next == VoiceUiState.error) {
      _audioQueue.clear();
    }
    
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    // Stop audio drain
    _stopAudioDrain();
    // Stop playback drain
    _stopPlaybackDrain();
    // Cancel silence detection timer
    _cancelSilenceTimer();
    _serverReadyTimer?.cancel();
    _serverReadyTimer = null;
    // Stop VAD monitoring
    _stopVad();
    _sessionStarted = false;

    try {
      await _sub?.cancel();
      _sub = null;
    } catch (e) {
      _logger.warn('voice.subscription_cancel_failed', data: {'error': e.toString()});
    }

    try {
      await audio.dispose();
    } catch (e) {
      _logger.warn('voice.audio_dispose_failed', data: {'error': e.toString()});
    }

    try {
      await gateway.close();
    } catch (e) {
      _logger.warn('voice.gateway_close_failed', data: {'error': e.toString()});
    }
    
    // Clean up reconnection timers
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _shouldReconnect = false;

    super.dispose();
  }
}

/// Helper class for queued audio chunks
class _QueuedAudio {
  final Uint8List pcm16k; // raw bytes (NOT base64 - encoded on drain)
  final int enqueuedAtMs; // for optional metrics

  _QueuedAudio(this.pcm16k) : enqueuedAtMs = DateTime.now().millisecondsSinceEpoch;
}
