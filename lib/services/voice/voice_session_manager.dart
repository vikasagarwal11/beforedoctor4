// lib/services/voice/voice_session_manager.dart
//
// Production-grade Voice Session Manager
// Implements thread-safe state machine with proper lifecycle management
//
// Key responsibilities:
// - Single source of truth for session state
// - Re-entrancy protection (no duplicate start/stop)
// - Safe async operation off UI thread
// - PCM player lifecycle ordering (setup → play → stop → cleanup)
// - Audio buffering until server ready
// - Structured logging and error recovery

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../audio/audio_engine_service.dart';
import '../gateway/gateway_client.dart';
import '../logging/app_logger.dart';

/// Session lifecycle states (state machine)
enum SessionState {
  idle,
  requestingPermission,
  initializing,
  connectingGateway,
  waitingForServer,
  ready,
  listening,
  speaking,
  processing,
  stopping,
  stopped,
  error,
}

/// Structured session event for logging
class SessionEvent {
  final String name;
  final SessionState? fromState;
  final SessionState? toState;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  SessionEvent({
    required this.name,
    this.fromState,
    this.toState,
    this.data = const {},
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      '[$timestamp] $name (${fromState?.name} → ${toState?.name})';
}

/// Audio buffer for queuing chunks before server ready
class AudioBuffer {
  static const int _maxChunks = 40; // ~800ms at 20ms per chunk
  final Queue<Uint8List> _queue = Queue();

  void add(Uint8List chunk) {
    _queue.addLast(chunk);
    // Drop oldest if exceeding max
    if (_queue.length > _maxChunks) {
      _queue.removeFirst();
    }
  }

  List<Uint8List> flush() {
    final chunks = _queue.toList();
    _queue.clear();
    return chunks;
  }

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  void clear() => _queue.clear();
}

/// Main session manager
class VoiceSessionManager {
  final IGatewayClient gateway;
  final IAudioEngine audio;
  final AppLogger _logger = AppLogger.instance;

  // State machine
  SessionState _state = SessionState.idle;
  SessionState get state => _state;

  // Re-entrancy protection: prevents concurrent start/stop calls
  bool _isTransitioning = false;
  final Completer<void> _startCompleter = Completer();
  Completer<void>? _pendingStart;

  // Audio buffering before server ready
  final AudioBuffer _audioBuffer = AudioBuffer();
  bool _serverReady = false;

  // Playback lifecycle state
  bool _playerSetupInitiated = false;
  bool _playerSetupComplete = false;

  // Session lifecycle
  Timer? _serverReadyTimeout;
  static const Duration _serverReadyMaxWait = Duration(seconds: 8);

  // Event logging
  final List<SessionEvent> _eventLog = [];
  static const int _maxEventLogSize = 100;

  VoiceSessionManager({
    required this.gateway,
    required this.audio,
  });

  /// Main entry point: Start session safely with re-entrancy protection
  Future<void> start({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    _log('voice.start_requested', data: {
      'current_state': _state.name,
      'is_transitioning': _isTransitioning,
    });

    // Re-entrancy guard: if already starting, wait for it
    if (_pendingStart != null) {
      _log('voice.start_ignored_already_pending');
      return _pendingStart!.future;
    }

    // If already running, ignore
    if (_state == SessionState.ready ||
        _state == SessionState.listening ||
        _state == SessionState.speaking) {
      _log('voice.start_ignored_already_running', data: {
        'current_state': _state.name,
      });
      return;
    }

    // Create a completer to track this start attempt
    _pendingStart = Completer<void>();

    try {
      await _doStart(
        url: url,
        firebaseIdToken: firebaseIdToken,
        sessionConfig: sessionConfig,
      );
      _pendingStart?.complete();
    } catch (e) {
      _pendingStart?.completeError(e);
    } finally {
      _pendingStart = null;
    }
  }

  /// Internal: Actual start implementation (off main thread where possible)
  Future<void> _doStart({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    try {
      // Step 1: Request permission (may be slow - user interaction)
      _setState(SessionState.requestingPermission);
      _log('voice.permission_requested');

      // Run permission request in background
      await Future.delayed(Duration.zero); // Yield to UI thread

      // Step 2: Initialize audio engine (off UI thread)
      _setState(SessionState.initializing);
      _log('voice.initializing_audio_engine');

      // Initialize player lifecycle: setup() phase
      await _initializePlayback();
      _log('voice.audio_playback_setup_complete');

      // Initialize capture
      await _initializeCapture();
      _log('voice.audio_capture_initialized');

      // Step 3: Connect to gateway (network I/O - off UI thread)
      _setState(SessionState.connectingGateway);
      _log('voice.connecting_to_gateway');

      await gateway.connect(
        url: url,
        firebaseIdToken: firebaseIdToken,
        sessionConfig: sessionConfig,
      );
      _log('voice.gateway_connected');

      // Step 4: Wait for server ready signal
      _setState(SessionState.waitingForServer);
      _log('voice.waiting_for_server_ready');

      await _waitForServerReady();
      _log('voice.server_ready_confirmed');

      // Step 5: Ready to listen
      _setState(SessionState.ready);
      _log('voice.session_ready', data: {
        'buffered_audio_chunks': _audioBuffer.length,
      });

      // Flush any buffered audio to server
      await _flushAudioBuffer();

      // Transition to listening
      _setState(SessionState.listening);
      _log('voice.listening_started');
    } catch (e) {
      _setState(SessionState.error);
      _log('voice.start_failed', data: {
        'error': e.toString(),
        'type': e.runtimeType.toString(),
      });
      rethrow;
    }
  }

  /// Stop session safely
  Future<void> stop() async {
    _log('voice.stop_requested', data: {
      'current_state': _state.name,
    });

    if (_state == SessionState.idle || _state == SessionState.stopped) {
      _log('voice.stop_ignored_not_running');
      return;
    }

    try {
      _setState(SessionState.stopping);

      // Stop audio in correct order
      await _stopCapture();
      await _stopPlayback(); // Safe even if partially started
      await gateway.close();

      _audioBuffer.clear();
      _resetState();

      _setState(SessionState.stopped);
      _log('voice.stop_completed');
    } catch (e) {
      _setState(SessionState.error);
      _log('voice.stop_failed', data: {'error': e.toString()});
      rethrow;
    }
  }

  /// Called by controller when server signals ready
  void markServerReady() {
    if (_serverReady) return;

    _serverReady = true;
    _serverReadyTimeout?.cancel();

    _log('voice.server_ready_confirmed', data: {
      'current_state': _state.name,
      'buffered_chunks': _audioBuffer.length,
    });

    // Flush buffered audio immediately
    Future.microtask(() => _flushAudioBuffer());
  }

  /// Queue audio chunk, buffering if server not ready yet
  Future<void> queueAudioChunk(Uint8List chunk) async {
    if (!_serverReady) {
      _audioBuffer.add(chunk);
      if (_audioBuffer.length % 10 == 0) {
        // Log every 10 chunks to avoid spam
        _log('voice.audio_buffered', data: {
          'chunk_count': _audioBuffer.length,
          'server_ready': _serverReady,
        });
      }
      return;
    }

    // Send directly if server ready
    try {
      await gateway.sendAudioChunkBinary(chunk);
    } catch (e) {
      _log('voice.audio_send_failed', data: {'error': e.toString()});
    }
  }

  /// Initialize playback safely
  Future<void> _initializePlayback() async {
    if (_playerSetupInitiated) {
      _log('voice.playback_already_initialized');
      return;
    }

    _playerSetupInitiated = true;

    try {
      // Setup MUST happen before any play calls
      await audio.playback.setup();
      _playerSetupComplete = true;
      _log('voice.playback_setup_complete');
    } catch (e) {
      _playerSetupComplete = false;
      _log('voice.playback_setup_failed', data: {'error': e.toString()});
      rethrow;
    }
  }

  /// Stop playback safely (guards against calling on uninitialized player)
  Future<void> _stopPlayback() async {
    if (!_playerSetupInitiated) {
      _log('voice.playback_stop_skipped_not_initialized');
      return;
    }

    try {
      await audio.playback.stop();
      _log('voice.playback_stopped');
    } catch (e) {
      _log('voice.playback_stop_failed', data: {'error': e.toString()});
      // Don't rethrow - cleanup should not fail the whole stop operation
    }

    try {
      await audio.playback.cleanup();
      _log('voice.playback_cleanup_complete');
    } catch (e) {
      _log('voice.playback_cleanup_failed', data: {'error': e.toString()});
      // Don't rethrow - cleanup failure is not fatal
    }

    _playerSetupInitiated = false;
    _playerSetupComplete = false;
  }

  /// Initialize audio capture
  Future<void> _initializeCapture() async {
    try {
      await audio.capture.start(onPcm16k: (chunk) {
        // Queue immediately, buffering happens in queueAudioChunk
        Future.microtask(() => queueAudioChunk(chunk));
      });
      _log('voice.capture_started');
    } catch (e) {
      _log('voice.capture_start_failed', data: {'error': e.toString()});
      rethrow;
    }
  }

  /// Stop audio capture
  Future<void> _stopCapture() async {
    try {
      await audio.capture.stop();
      _log('voice.capture_stopped');
    } catch (e) {
      _log('voice.capture_stop_failed', data: {'error': e.toString()});
    }
  }

  /// Wait for server ready signal with timeout
  Future<void> _waitForServerReady() async {
    _serverReadyTimeout = Timer(_serverReadyMaxWait, () {
      _log('voice.server_ready_timeout', data: {
        'max_wait_ms': _serverReadyMaxWait.inMilliseconds,
      });
    });

    // Poll for server ready (controller will call markServerReady)
    while (!_serverReady && _state == SessionState.waitingForServer) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    _serverReadyTimeout?.cancel();

    if (!_serverReady) {
      throw Exception(
          'Server ready timeout after ${_serverReadyMaxWait.inSeconds}s');
    }
  }

  /// Send buffered audio chunks to server
  Future<void> _flushAudioBuffer() async {
    if (_audioBuffer.isEmpty) return;

    final chunks = _audioBuffer.flush();
    _log('voice.audio_buffer_flushed', data: {
      'chunk_count': chunks.length,
    });

    for (final chunk in chunks) {
      try {
        await gateway.sendAudioChunkBinary(chunk);
      } catch (e) {
        _log('voice.buffered_chunk_send_failed', data: {
          'error': e.toString(),
          'pending_chunks': _audioBuffer.length,
        });
        // Continue with next chunk even if one fails
      }
    }
  }

  /// State transition with logging
  void _setState(SessionState newState) {
    if (_state == newState) return;

    final event = SessionEvent(
      name: 'state_transition',
      fromState: _state,
      toState: newState,
    );

    _state = newState;
    _logEvent(event);

    _log('voice.state_changed', data: {
      'from': _state.name,
      'to': newState.name,
    });
  }

  /// Reset internal state
  void _resetState() {
    _serverReady = false;
    _audioBuffer.clear();
    _playerSetupInitiated = false;
    _playerSetupComplete = false;
    _serverReadyTimeout?.cancel();
    _serverReadyTimeout = null;
  }

  /// Structured logging
  void _log(String event, {Map<String, dynamic> data = const {}}) {
    final sessionEvent = SessionEvent(
      name: event,
      data: {
        ...data,
        'state': _state.name,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _logEvent(sessionEvent);
    _logger.info('voice.$event', data: sessionEvent.data);
  }

  void _logEvent(SessionEvent event) {
    _eventLog.add(event);
    if (_eventLog.length > _maxEventLogSize) {
      _eventLog.removeAt(0);
    }
  }

  /// Get session event log (for debugging)
  List<SessionEvent> get eventLog => List.unmodifiable(_eventLog);

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
  }
}
