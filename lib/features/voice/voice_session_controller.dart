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

enum VoiceUiState { ready, connecting, listening, speaking, processing, emergency, stopped, error }

class VoiceSessionController extends ChangeNotifier {
  final IGatewayClient gateway;
  final IAudioEngine audio;
  final AppLogger _logger = AppLogger.instance;

  VoiceUiState uiState = VoiceUiState.ready;

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

  // Affective state hook (optional future UI polish / safety)
  String? userEmotion; // e.g. 'stress', 'urgency', 'calm'
  double? userEmotionConfidence; // 0..1 (if provided)

  int _lastSeqApplied = 0;
  StreamSubscription<GatewayEvent>? _sub;
  bool _sessionStarted = false;
  bool _serverReady = false; // Track when server session is ready (listening state)
  bool _micCaptureActive = false; // Track if mic is actively capturing
  bool _micMuted = false; // Track if mic is muted (for push-to-talk)

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
  });

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
  }) async {
    try {
      _setState(VoiceUiState.connecting);
      _sessionStarted = false;

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

      // Wait for server to be ready (sessionState: 'listening') before starting mic
      // This prevents sending audio before Vertex session is fully set up
      _logger.info('voice.waiting_for_server_ready', data: {
        'gateway_url': gatewayUrl.toString(),
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
      _logger.info('voice.mic_unmuted');
    } else {
      // Mute: stop sending audio and signal turnComplete
      _micMuted = true;
      _logger.info('voice.mic_muted');
      try {
        await gateway.sendTurnComplete();
        _logger.info('voice.turn_complete_sent');
      } catch (e) {
        _logger.warn('voice.turn_complete_failed', data: {'error': e.toString()});
      }
    }
    notifyListeners();
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
      // Encode on drain (not on enqueue) to save CPU if chunks are dropped
      final b64 = base64Encode(item.pcm16k);
      
      // Log audio being sent to gateway (every 100th chunk - reduced frequency)
      _audioSendCounter++;
      if (_audioSendCounter % 100 == 0) {
        _logger.debug('voice.audio_chunk_sent_to_gateway', data: {
          'total_sent': _audioSendCounter,
          'queue_depth': _audioQueue.length,
        });
      }
      
      await gateway.sendAudioChunkBase64(b64);

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
      }
    }
  }

  Future<void> stop() async {
    _logger.info('voice.stop_called', data: {
      'current_state': uiState.toString(),
      'session_started': _sessionStarted,
      'queue_depth': _audioQueue.length,
    });
    
    try {
      // Stop audio drain and clear queue immediately to prevent stale sends
      _stopAudioDrain();
      _audioQueue.clear(); // Clear any remaining queued audio
      _droppedAudioChunks = 0;
      _sessionStarted = false;

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
        _logger.info('voice.sessionState_event_DEBUG', data: {
          'state': state,
          'session_started': _sessionStarted,
          'server_ready_before': _serverReady,
        });
        if (state == 'listening') {
          _logger.info('voice.server_listening_state_received', data: {
            'current_session_started': _sessionStarted,
            'current_server_ready': _serverReady,
          });
          _setState(VoiceUiState.listening);
          _serverReady = true;
          _logger.info('voice.server_ready_SET_TO_TRUE_DEBUG');
          // Start mic capture now that server is ready
          _startMicCaptureIfNeeded();
        }
        if (state == 'speaking') _setState(VoiceUiState.speaking);
        if (state == 'processing') _setState(VoiceUiState.processing);
        if (state == 'stopped') {
          _setState(VoiceUiState.stopped);
          _serverReady = false;
        }
        break;
      }

      case GatewayEventType.userTranscriptPartial: {
        final text = ev.payload['text'] as String? ?? '';
        userTranscriptPartial = text;
        // Only log final transcripts, not every partial update
        notifyListeners();
        break;
      }

      case GatewayEventType.userTranscriptFinal: {
        final text = ev.payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
          userTranscriptFinal = (userTranscriptFinal.isEmpty) ? text : '$userTranscriptFinal\n$text';
          userTranscriptPartial = '';
          _logger.info('voice.user_transcript_final_received', data: {
            'text_length': text.length,
            'sequence': ev.seq,
            'total_final_segments': userTranscriptFinal.split('\n').length,
          });
          notifyListeners();
        }
        break;
      }

      case GatewayEventType.transcriptPartial: {
        // This is assistant caption (modelTurn.text), not user ASR
        final text = ev.payload['text'] as String? ?? '';
        assistantCaptionPartial = text;
        // Only log final transcripts, not every partial update
        notifyListeners();
        break;
      }

      case GatewayEventType.transcriptFinal: {
        // This is assistant caption (modelTurn.text), not user ASR
        final text = ev.payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
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
        // Use unawaited to avoid blocking the gateway event loop
        unawaited(_flushPlaybackBuffer());
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
        final errorMessage = ev.payload['message'] as String? ?? 'Unknown gateway error';
        final errorCode = ev.payload['code'] as String?;
        lastError = errorMessage;
        
        _logger.error('voice.gateway_error_received', data: {
          'message': errorMessage,
          'code': errorCode,
          'sequence': ev.seq,
          'payload_keys': ev.payload.keys.toList(),
          'session_started': _sessionStarted,
          'server_ready': _serverReady,
          'mic_capture_active': _micCaptureActive,
        });
        
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
        _setState(VoiceUiState.error);
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
    if (_micCaptureActive || !_sessionStarted || !_serverReady) {
      return;
    }
    
    try {
      _micCaptureActive = true;
      _logger.info('voice.starting_audio_capture');
      await audio.capture.start(onPcm16k: (pcm16k) {
        // Enqueue audio chunk (will be drained at fixed 20ms cadence)
        _enqueueAudioChunk(pcm16k);
      });
      _logger.info('voice.audio_capture_started');
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

    super.dispose();
  }
}

/// Helper class for queued audio chunks
class _QueuedAudio {
  final Uint8List pcm16k; // raw bytes (NOT base64 - encoded on drain)
  final int enqueuedAtMs; // for optional metrics

  _QueuedAudio(this.pcm16k) : enqueuedAtMs = DateTime.now().millisecondsSinceEpoch;
}
