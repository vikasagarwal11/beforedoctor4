// lib/services/audio/native_audio_engine.dart
//
// Production-grade native audio engine with:
// - PCM buffering (20-40ms chunks) for smooth audio quality
// - Audio resampling (device sample rate → 16kHz) for compatibility
// - iOS audio session configuration (playAndRecord with Bluetooth)
// - Chunk size validation and timing control
//
// Requirements:
// - Input (mic → gateway):  16kHz, 16-bit PCM, mono (s16le)
// - Output (gateway → spk): 24kHz, 16-bit PCM, mono (s16le)

import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../../services/logging/app_logger.dart';
import 'audio_engine_service.dart';

class NativeAudioEngine implements IAudioEngine {
  @override
  final IAudioCapture capture = _NativeCapture();

  @override
  final IAudioPlayback playback = _NativePlayback();

  @override
  Future<void> dispose() async {
    await capture.stop();
    await playback.dispose();
  }
}

class _NativeCapture implements IAudioCapture {
  static const int _targetSampleRate = 16000;
  static const int _targetChannels = 1;

  // Fixed 20ms chunks (640 bytes at 16kHz) for deterministic latency
  // At 16kHz, 16-bit mono: 16,000 samples/sec * 2 bytes/sample = 32,000 bytes/sec
  // 20ms = 0.02 sec * 32,000 bytes/sec = 640 bytes
  static const int _fixedChunkBytes = 640; // 20ms at 16kHz: (16000 * 0.02 * 2)
  static const int _maxChunkBytes = 640; // Maximum (20ms)

  bool _isCapturing = false;
  FlutterSoundRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  StreamController<Uint8List>? _streamController;

  // Buffering state
  final List<int> _audioBuffer = [];
  void Function(Uint8List pcm16k)?
      _onPcm16kCallback; // Store callback for final flush

  // No sample rate detection on Android - use 16kHz always
  // iOS can be added later if needed with explicit negotiation
  int _chunkCounter = 0; // For logging

  final AppLogger _logger = AppLogger.instance;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start(
      {required void Function(Uint8List pcm16k) onPcm16k}) async {
    if (_isCapturing) {
      _logger.warn('audio.capture_already_active');
      return;
    }

    try {
      // Configure iOS audio session before starting
      await _configureAudioSession();

      _isCapturing = true;
      _audioBuffer.clear();
      _onPcm16kCallback = onPcm16k; // Store callback for final flush

      // Reuse existing recorder if available, otherwise create new one
      _recorder ??= FlutterSoundRecorder();

      // Only open if not already open
      if (!(_recorder!.isRecording || _recorder!.isPaused)) {
        await _recorder!.openRecorder();
      }

      // Create stream controller for audio data
      _streamController = StreamController<Uint8List>.broadcast();

      // Listen to the stream and process directly (no buffering/resampling)
      _sub = _streamController!.stream.listen((data) {
        if (!_isCapturing) return;
        // Process each incoming chunk directly as 20ms frames
        _processAudioChunk(data, onPcm16k);
      });

      // Start recording at native 16kHz, mono, PCM16
      await _recorder!.startRecorder(
        toStream: _streamController!.sink,
        codec: Codec.pcm16,
        sampleRate: _targetSampleRate,
        numChannels: _targetChannels,
      );

      _logger.info('audio.capture_started', data: {
        'sample_rate': _targetSampleRate,
        'channels': _targetChannels,
        'fixed_chunk_ms': 20,
      });
    } catch (e) {
      _isCapturing = false;
      _logger.error('audio.capture_start_failed', error: e);
      rethrow;
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
        // Prefer speech processing / echo control where the OS supports it.
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        // Prefer exclusive transient focus to reduce interruptions while capturing speech.
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: true,
      ));

      await session.setActive(true);
      _logger.info('audio.session_configured', data: {
        'category': 'playAndRecord',
        'bluetooth_enabled': true,
      });
    } catch (e) {
      // Log but don't fail - some platforms may not support all options
      _logger
          .warn('audio.session_config_failed', data: {'error': e.toString()});
    }
  }

  void _processAudioChunk(
      Uint8List rawData, void Function(Uint8List pcm16k) onPcm16k) {
    if (!_isCapturing) return;

    // Target: 640 bytes for 20ms @ 16kHz mono 16-bit
    const targetChunkBytes = 640;

    // If chunk is larger than expected, split it into proper-sized chunks
    if (rawData.length > targetChunkBytes * 1.5) {
      // Split large chunk into multiple 640-byte chunks
      int offset = 0;
      while (offset + targetChunkBytes <= rawData.length) {
        final chunk =
            Uint8List.sublistView(rawData, offset, offset + targetChunkBytes);
        onPcm16k(chunk);
        offset += targetChunkBytes;
      }
      // Send remaining bytes if any (keep in buffer for next chunk)
      if (offset < rawData.length) {
        final remainder = Uint8List.sublistView(rawData, offset);
        _audioBuffer.addAll(remainder);
      }
      return;
    }

    // If we have buffered data, combine with new chunk
    if (_audioBuffer.isNotEmpty) {
      _audioBuffer.addAll(rawData);

      // Extract complete chunks from buffer
      while (_audioBuffer.length >= targetChunkBytes) {
        final chunk =
            Uint8List.fromList(_audioBuffer.sublist(0, targetChunkBytes));
        _audioBuffer.removeRange(0, targetChunkBytes);

        _chunkCounter++;
        if (_chunkCounter % 50 == 0) {
          _logger.info('audio.capture_chunk_processed', data: {
            'chunk_size_bytes': chunk.length,
            'chunk_number': _chunkCounter,
            'buffer_remaining': _audioBuffer.length,
          });
        }

        onPcm16k(chunk);
      }
      return;
    }

    // Normal case: chunk is approximately correct size
    _chunkCounter++;
    if (_chunkCounter % 50 == 0) {
      _logger.info('audio.capture_chunk_received', data: {
        'chunk_size_bytes': rawData.length,
        'chunk_number': _chunkCounter,
      });
    }

    onPcm16k(rawData);
  }

  void _flushBuffer(void Function(Uint8List pcm16k) onPcm16k) {
    if (!_isCapturing || _audioBuffer.isEmpty) return;

    // Fixed 20ms chunking: always send exactly 640 bytes (or wait if not enough)
    // This ensures deterministic latency matching Gemini Live's expectations
    if (_audioBuffer.length < _fixedChunkBytes) {
      // Not enough data yet - wait for next timer tick
      return;
    }

    // Extract exactly 640 bytes (20ms at 16kHz)
    final chunk = _audioBuffer.sublist(0, _fixedChunkBytes);
    _audioBuffer.removeRange(0, _fixedChunkBytes);

    // Validate chunk size (should always be exactly 640 bytes now)
    if (chunk.length != _fixedChunkBytes) {
      _logger.warn('audio.unexpected_chunk_size', data: {
        'size': chunk.length,
        'expected': _fixedChunkBytes,
      });
    }

    // Convert to Uint8List and send
    final pcm16k = Uint8List.fromList(chunk);

    // Log when audio chunk is sent to controller (every 10th chunk to avoid spam)
    _chunkCounter++;
    if (_chunkCounter % 10 == 0) {
      _logger.info('audio.chunk_sent_to_controller', data: {
        'chunk_size_bytes': pcm16k.length,
        'chunk_number': _chunkCounter,
        'buffer_remaining_bytes': _audioBuffer.length,
      });
    }

    onPcm16k(pcm16k);
  }

  @override
  Future<void> stop() async {
    if (!_isCapturing) {
      _logger.debug('audio.capture_already_stopped');
      return;
    }

    _isCapturing = false;

    // Flush any remaining buffer - ALWAYS forward it to callback, even if small
    // This prevents dropping the final 10-20ms of speech
    if (_audioBuffer.isNotEmpty && _onPcm16kCallback != null) {
      final pcm16k = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      _logger
          .debug('audio.flushing_final_buffer', data: {'bytes': pcm16k.length});

      // Forward final buffer to callback (even if smaller than minChunkBytes)
      _onPcm16kCallback!(pcm16k);
    } else if (_audioBuffer.isNotEmpty) {
      // No callback available, just clear
      _logger.debug('audio.discarding_final_buffer_no_callback',
          data: {'bytes': _audioBuffer.length});
      _audioBuffer.clear();
    }

    // Clear callback reference
    _onPcm16kCallback = null;

    _chunkCounter = 0;

    try {
      await _sub?.cancel();
      _sub = null;

      if (_recorder != null) {
        if (_recorder!.isRecording) {
          await _recorder!.stopRecorder();
        }
        await _recorder!.closeRecorder();
        // Keep recorder instance for reuse (don't null it out)
        // This prevents creating multiple instances
      }

      await _streamController?.close();
      _streamController = null;
    } catch (e) {
      _logger.warn('audio.capture_stop_error', data: {'error': e.toString()});
      // Reset recorder on error to allow recovery
      _recorder = null;
    }

    _logger.info('audio.capture_stopped');
  }

  /// Dispose of the recorder completely (for cleanup)
  Future<void> dispose() async {
    await stop();
    try {
      await _recorder?.closeRecorder();
    } catch (e) {
      _logger
          .debug('audio.capture_dispose_error', data: {'error': e.toString()});
    }
    _recorder = null;
  }
}

/// Simple linear interpolation resampler
/// Converts audio from sourceSampleRate to targetSampleRate (16kHz)
class _AudioResampler {
  final int sourceSampleRate;
  final int targetSampleRate;
  final double ratio;
  double _position = 0.0;

  _AudioResampler(this.sourceSampleRate, this.targetSampleRate)
      : ratio = sourceSampleRate / targetSampleRate;

  /// Resample PCM16 mono audio
  Uint8List resample(Uint8List input) {
    if (sourceSampleRate == targetSampleRate) {
      return input; // No resampling needed
    }

    final inputSamples = _bytesToSamples(input);
    final outputSampleCount = (inputSamples.length / ratio).ceil();
    final outputSamples = <int>[];

    for (int i = 0; i < outputSampleCount; i++) {
      final srcPos = _position;
      final srcIndex = srcPos.floor();
      final fraction = srcPos - srcIndex;

      if (srcIndex + 1 < inputSamples.length) {
        // Linear interpolation
        final sample1 = inputSamples[srcIndex].toDouble();
        final sample2 = inputSamples[srcIndex + 1].toDouble();
        final interpolated = sample1 + (sample2 - sample1) * fraction;
        outputSamples.add(interpolated.round().clamp(-32768, 32767));
      } else if (srcIndex < inputSamples.length) {
        outputSamples.add(inputSamples[srcIndex]);
      }

      _position += ratio;
    }

    // Handle position wrap-around
    if (_position >= inputSamples.length) {
      _position -= inputSamples.length;
    }

    return _samplesToBytes(outputSamples);
  }

  List<int> _bytesToSamples(Uint8List bytes) {
    final samples = <int>[];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final low = bytes[i];
      final high = bytes[i + 1];
      // Little-endian 16-bit signed integer
      final sample = (high << 8) | low;
      // Convert to signed
      final signedSample = sample > 32767 ? sample - 65536 : sample;
      samples.add(signedSample);
    }
    return samples;
  }

  Uint8List _samplesToBytes(List<int> samples) {
    final bytes = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(-32768, 32767);
      // Convert to unsigned and write as little-endian
      final unsigned = sample < 0 ? sample + 65536 : sample;
      bytes[i * 2] = unsigned & 0xFF;
      bytes[i * 2 + 1] = (unsigned >> 8) & 0xFF;
    }
    return bytes;
  }
}

class _NativePlayback implements IAudioPlayback {
  static const int _targetSampleRate = 24000;
  static const int _targetChannels = 1;

  bool _setupInitiated = false;
  bool _setupComplete = false;
  final AppLogger _logger = AppLogger.instance;

  @override
  bool get isPlaying => _setupComplete;

  /// Setup: One-time initialization of audio session
  /// Must be called before any play/feed operations
  @override
  Future<void> setup() async {
    if (_setupInitiated) {
      _logger.debug('audio.playback_setup_already_initiated');
      return;
    }

    _setupInitiated = true;

    try {
      // Guard: Safely stop any previous session
      try {
        await FlutterPcmSound.stop();
        _logger.debug('audio.playback_pre_setup_stop');
      } catch (e) {
        // Ignore errors from stopping non-existent session
        _logger.debug('audio.playback_pre_setup_stop_ignored',
            data: {'error': e.toString()});
      }

      // Small delay to let audio session settle
      await Future.delayed(const Duration(milliseconds: 100));

      // Initialize audio session
      await FlutterPcmSound.setup(
        sampleRate: _targetSampleRate,
        channelCount: _targetChannels,
      );
      await FlutterPcmSound.play();
      _setupComplete = true;
      _logger.info('audio.playback_setup_complete', data: {
        'sample_rate': _targetSampleRate,
        'channels': _targetChannels,
      });
    } catch (e) {
      _setupInitiated = false;
      _setupComplete = false;
      _logger.error('audio.playback_setup_failed', error: e);
      rethrow;
    }
  }

  /// Deprecated: Use setup() instead
  @Deprecated('Use setup() instead')
  @override
  Future<void> prepare() async => setup();

  @override
  Future<void> feed(Uint8List pcm24k) async {
    // Guard: ensure setup happened first
    if (!_setupComplete) {
      _logger.warn('audio.feed_before_setup', data: {
        'setup_initiated': _setupInitiated,
        'setup_complete': _setupComplete,
      });
      await setup();
    }

    try {
      if (pcm24k.isEmpty) {
        _logger.warn('audio.empty_playback_chunk');
        return;
      }

      // Convert Uint8List to ByteData for PcmArrayInt16
      final byteData =
          pcm24k.buffer.asByteData(pcm24k.offsetInBytes, pcm24k.length);
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: byteData));
    } catch (e) {
      _logger.warn('audio.playback_feed_failed', data: {'error': e.toString()});
    }
  }

  /// Stop playback and flush buffers
  /// Safe to call even if not playing
  @override
  Future<void> stop() async {
    if (!_setupInitiated) {
      _logger.debug('audio.playback_stop_not_initialized');
      return;
    }

    try {
      await FlutterPcmSound.stop();
      _setupComplete = false;
      _logger.debug('audio.playback_stopped');
    } catch (e) {
      _setupComplete = false;
      _logger.warn('audio.playback_stop_failed', data: {'error': e.toString()});
    }
  }

  /// Immediate stop alias to satisfy IAudioPlayback
  /// Uses the same guarded stop implementation
  @override
  Future<void> stopNow() async {
    await stop();
  }

  /// Cleanup: Release audio resources completely
  /// Called at session end, safe even if partially initialized
  @override
  Future<void> cleanup() async {
    if (!_setupInitiated) {
      _logger.debug('audio.playback_cleanup_not_needed');
      return;
    }

    try {
      await FlutterPcmSound.stop();
      _setupInitiated = false;
      _setupComplete = false;
      _logger.info('audio.playback_cleanup_complete');
    } catch (e) {
      _setupInitiated = false;
      _setupComplete = false;
      _logger
          .warn('audio.playback_cleanup_failed', data: {'error': e.toString()});
    }
  }

  @override
  Future<void> dispose() async {
    await cleanup();
  }
}
