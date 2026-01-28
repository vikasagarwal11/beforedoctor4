// lib/services/audio/audio_engine_service.dart
//
// Audio abstraction for BeforeDoctor Voice Live.
//
// The Gemini Live "native-audio" path expects:
// - Input (mic → gateway):  16kHz, 16-bit PCM, mono (s16le)
// - Output (gateway → spk): 24kHz, 16-bit PCM, mono (s16le)
//
// This file defines interfaces and a NoOp implementation.
// Add your platform implementation in a separate file (native_audio_engine.dart).

import 'dart:typed_data';

import '../logging/app_logger.dart';

abstract class IAudioEngine {
  IAudioCapture get capture;
  IAudioPlayback get playback;
  Future<void> dispose();
}

abstract class IAudioCapture {
  bool get isCapturing;

  /// Starts microphone capture and calls [onPcm16k] with raw PCM s16le, mono, 16kHz.
  Future<void> start({required void Function(Uint8List pcm16k) onPcm16k});

  Future<void> stop();
}

abstract class IAudioPlayback {
  bool get isPlaying;

  /// Setup audio session (called once at start)
  /// Initializes platform-specific audio session configuration
  Future<void> setup();

  /// Prepares speaker playback for PCM s16le, mono, 24kHz.
  /// Deprecated: Use setup() instead for one-time initialization
  @Deprecated('Use setup() instead')
  Future<void> prepare();

  /// Feeds a PCM 24kHz chunk to the speaker.
  Future<void> feed(Uint8List pcm24k);

  /// Stop playback and flush buffers (safe to call even if not playing)
  Future<void> stop();

  /// Cleanup and release audio resources (called at session end)
  Future<void> cleanup();

  /// Stop playback immediately (for barge-in / emergency)
  /// Alias for stop() with emphasis on immediate effect
  Future<void> stopNow() => stop();

  Future<void> dispose();
}

/// Safe default for desktop/tests.
class NoOpAudioEngine implements IAudioEngine {
  @override
  final IAudioCapture capture = _NoOpCapture();

  @override
  final IAudioPlayback playback = _NoOpPlayback();

  @override
  Future<void> dispose() async {
    await capture.stop();
    await playback.dispose();
  }
}

class _NoOpCapture implements IAudioCapture {
  bool _capturing = false;
  static final _logger = AppLogger.instance;

  @override
  bool get isCapturing => _capturing;

  @override
  Future<void> start(
      {required void Function(Uint8List pcm16k) onPcm16k}) async {
    _capturing = true;
    _logger.info('audio.noop_capture_started', data: {
      'note':
          'Mock mode - no actual audio capture. Audio chunks will not be generated.',
      'is_capturing': _capturing,
      'warning':
          'To test real audio capture, set useMockGateway: false and use NativeAudioEngine',
    });
    // no-op - this is intentional for mock mode
    // In mock mode, we don't generate audio chunks because there's no real microphone
    // The mock gateway will still send simulated transcript events
  }

  @override
  Future<void> stop() async {
    _capturing = false;
  }
}

class _NoOpPlayback implements IAudioPlayback {
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> setup() async {
    _playing = true;
  }

  @Deprecated('Use setup() instead')
  @override
  Future<void> prepare() async {
    _playing = true;
  }

  @override
  Future<void> feed(Uint8List pcm24k) async {
    // no-op
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> cleanup() async {
    _playing = false;
  }

  @override
  Future<void> stopNow() async {
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    _playing = false;
  }
}
