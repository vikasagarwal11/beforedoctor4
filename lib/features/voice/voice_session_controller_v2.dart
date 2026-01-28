import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/audio/audio_engine_service.dart';
import '../../services/audio/audio_queue_manager.dart';
import '../../services/audio/playback_buffer_manager.dart';
import '../../services/audio/vad_processor.dart';
import '../../services/gateway/gateway_client.dart';
import '../../services/gateway/gateway_protocol.dart' as gw;
import '../../services/logging/app_logger.dart';

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

class VoiceSessionControllerV2 extends ChangeNotifier {
  // Dependencies
  final IGatewayClient gateway;
  final IAudioEngine audio;
  final AppLogger logger = AppLogger.instance;

  // Configuration
  final bool preferBinaryAudio;
  final VadSensitivity vadSensitivity;

  // Session state
  VoiceUiState _uiState = VoiceUiState.idle;
  bool _sessionActive = false;
  bool _serverReady = false;

  // Reconnection state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
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
  Timer? _sendLoopTimer; // Send audio every 20ms
  Timer? _playbackDrainTimer; // Drain playback buffer every 20ms
  Timer? _serverReadyTimer;

  // Event subscriptions
  StreamSubscription<gw.GatewayEvent>? _gatewayEventSub;

  // State info
  String userTranscriptPartial = '';
  String userTranscriptFinal = '';
  String assistantTextPartial = '';
  String assistantTextFinal = '';
  String? lastError;
  bool showReconnectPrompt = false;

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

      await gateway
          .connect(
        url: gatewayUrl,
        firebaseIdToken: firebaseIdToken,
        sessionConfig: sessionConfig,
      )
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Gateway connection timeout');
      });

      _sessionActive = true;
      _serverReady = false;

      _setupGatewayEventListener();

      _startMicCapture();
      _startSendLoop();
      _startPlaybackDrainLoop();
      _waitForServerReady();

      logger.info('voice.session_started');
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
      _uiState = newState;
      logger.debug('voice.state_changed', data: {
        'from': _uiState.toString(),
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

        // Apply VAD
        final vadDecision = _vad.processFrame(chunk);

        // Enqueue if speech or prebuffering
        if (vadDecision == VadDecision.speech ||
            _audioQueue.queueDepthFrames < 10) {
          final dropped = !_audioQueue.enqueue(
              chunk, DateTime.now().millisecondsSinceEpoch);
          if (dropped) {
            logger.warn('voice.audio_frame_dropped', data: {
              'queue_depth': _audioQueue.queueDepthFrames,
            });
          }
        }
      });
    } catch (e) {
      logger.error('voice.capture_start_failed', error: e);
      _setState(VoiceUiState.error);
    }
  }

  void _startSendLoop() {
    _sendLoopTimer?.cancel();
    logger.info('voice.send_loop_starting');

    _sendLoopTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_sessionActive || !_serverReady) return;

      // If the socket dropped, stop sending immediately and let reconnect logic run.
      if (!gateway.isConnected) {
        _handleGatewayDisconnected('Gateway not connected');
        return;
      }

      _sendAudioBatch();
    });
  }

  void _sendAudioBatch() {
    try {
      final batch = _audioQueue.dequeueBatch();
      if (batch.isEmpty) return;

      if (!gateway.isConnected) {
        _handleGatewayDisconnected('Gateway not connected');
        return;
      }

      for (final frame in batch) {
        // Send as binary PCM frame for lowest latency.
        // Ignore backpressure here; gateway/client will surface disconnects via events.
        unawaited(
          gateway.sendAudioChunkBinary(frame.data).catchError((e) {
            // Prevent unhandled Future errors from crashing the Timer callback.
            logger.error('voice.send_audio_failed', error: e);
            _handleGatewayDisconnected(e.toString());
          }),
        );
        sentChunks++;
      }

      logger.debug('voice.audio_batch_sent', data: {
        'frame_count': batch.length,
        'queue_depth': _audioQueue.queueDepthFrames,
      });
    } catch (e) {
      logger.error('voice.send_audio_failed', error: e);
    }
  }

  void _startPlaybackDrainLoop() {
    _playbackDrainTimer?.cancel();
    logger.info('voice.playback_drain_starting');

    _playbackDrainTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_sessionActive) return;

      _drainPlaybackBuffer();
    });
  }

  void _drainPlaybackBuffer() {
    try {
      final frames = _playbackBuffer.drainFrames();
      if (frames.isEmpty) return;

      for (final frame in frames) {
        audio.playback.feed(frame.data);
      }

      logger.debug('voice.playback_drained', data: {
        'frame_count': frames.length,
        'buffer_depth': _playbackBuffer.bufferDepthMs,
      });
    } catch (e) {
      logger.error('voice.playback_drain_failed', error: e);
    }
  }

  void _waitForServerReady() {
    _serverReadyTimer?.cancel();
    logger.info('voice.waiting_for_server_ready');

    // Log current connection state
    logger.debug('voice.connection_check', data: {
      'gateway_connected': gateway.isConnected,
      'session_active': _sessionActive,
    });

    _serverReadyTimer = Timer(const Duration(seconds: 5), () {
      if (!_serverReady && _sessionActive) {
        // Only force ready if the gateway is still connected.
        // If disconnected, forcing ready will cause repeated send failures.
        if (!gateway.isConnected) {
          logger.warn('voice.server_ready_timeout_gateway_disconnected', data: {
            'gateway_connected': gateway.isConnected,
            'session_active': _sessionActive,
          });
          _handleGatewayDisconnected(
              'Gateway disconnected while waiting for ready');
          return;
        }

        logger.warn('voice.server_ready_timeout_forcing_ready', data: {
          'gateway_connected': gateway.isConnected,
          'session_active': _sessionActive,
        });

        // FAILSAFE: Gateway should have sent listening state by now.
        _serverReady = true;
        _setState(VoiceUiState.listening);
        _startSendLoop();
        logger.info('voice.forced_server_ready_to_unblock_audio');
      }
    });
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
        if (ev.payload['state'] == 'listening') {
          _serverReady = true;
          _serverReadyTimer?.cancel();
          _setState(VoiceUiState.listening);
          logger.info('voice.server_ready');
        }
        break;

      case gw.GatewayEventType.audioOut:
        receivedAudioChunks++;
        final b64 = ev.payload['data'] as String?;
        if (b64 == null || b64.isEmpty) return;
        try {
          final audioBytes = base64Decode(b64);
          _playbackBuffer.enqueueAiAudio(Uint8List.fromList(audioBytes));
          logger.debug('voice.ai_audio_received', data: {
            'size_bytes': audioBytes.length,
          });
        } catch (e) {
          logger.warn('voice.ai_audio_decode_failed', data: {
            'error': e.toString(),
          });
        }
        break;

      case gw.GatewayEventType.userTranscriptPartial:
        userTranscriptPartial = ev.payload['text'] as String? ?? '';
        notifyListeners();
        break;

      case gw.GatewayEventType.userTranscriptFinal:
        userTranscriptFinal = ev.payload['text'] as String? ?? '';
        userTranscriptPartial = '';
        notifyListeners();
        break;

      case gw.GatewayEventType.transcriptPartial:
        assistantTextPartial = ev.payload['text'] as String? ?? '';
        notifyListeners();
        break;

      case gw.GatewayEventType.transcriptFinal:
        assistantTextFinal = ev.payload['text'] as String? ?? '';
        assistantTextPartial = '';
        _setState(VoiceUiState.speaking);
        notifyListeners();
        break;

      case gw.GatewayEventType.error:
        final errorMsg = ev.payload['message'] as String? ?? 'Unknown error';
        lastError = errorMsg;
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

    // Cancel subscriptions
    await _gatewayEventSub?.cancel();

    // Clear state
    _sessionActive = false;
    _serverReady = false;
    _audioQueue.clear();
    _playbackBuffer.clear();
    _vad.reset();

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

  @override
  Future<void> dispose() async {
    await _cleanup();
    super.dispose();
  }
}
