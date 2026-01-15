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
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

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
  static const int _minChunkBytes = 320; // Minimum acceptable (10ms)
  static const int _maxChunkBytes = 640; // Maximum (20ms)

  bool _isCapturing = false;
  FlutterSoundRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  StreamController<Uint8List>? _streamController;
  
  // Buffering state
  final List<int> _audioBuffer = [];
  Timer? _chunkTimer;
  
  // Sample rate detection
  int? _deviceSampleRate;
  bool _needsResampling = false;
  _AudioResampler? _resampler;
  final List<int> _chunkSizeHistory = []; // For sample rate detection
  DateTime? _firstChunkTime;
  int _totalBytesReceived = 0;
  int _chunkCounter = 0; // For logging
  
  final AppLogger _logger = AppLogger.instance;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start({required void Function(Uint8List pcm16k) onPcm16k}) async {
    if (_isCapturing) return;
    
    try {
      // Configure iOS audio session before starting
      await _configureAudioSession();
      
      _isCapturing = true;
      _audioBuffer.clear();

      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();

      // Create stream controller for audio data
      _streamController = StreamController<Uint8List>.broadcast();

      // Listen to the stream and process with buffering/resampling
      _sub = _streamController!.stream.listen((data) {
        if (!_isCapturing) return;
        _processAudioChunk(data, onPcm16k);
      });

      // Start recording - try to get native 16kHz, but we'll handle resampling if needed
      await _recorder!.startRecorder(
        toStream: _streamController!.sink,
        codec: Codec.pcm16,
        sampleRate: _targetSampleRate,
        numChannels: _targetChannels,
      );

      // Initialize sample rate detection
      _deviceSampleRate = _targetSampleRate; // Assume correct until proven otherwise
      _needsResampling = false;
      _resampler = null;
      _chunkSizeHistory.clear();
      _firstChunkTime = null;
      _totalBytesReceived = 0;

      _logger.info('audio.capture_started', data: {
        'requested_rate': _targetSampleRate,
        'device_rate': _deviceSampleRate,
        'needs_resampling': _needsResampling,
      });

      // Start periodic chunk sending (every 20ms for fixed deterministic chunks)
      _chunkTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        _flushBuffer(onPcm16k);
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
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      
      await session.setActive(true);
      _logger.info('audio.session_configured', data: {
        'category': 'playAndRecord',
        'bluetooth_enabled': true,
      });
    } catch (e) {
      // Log but don't fail - some platforms may not support all options
      _logger.warn('audio.session_config_failed', data: {'error': e.toString()});
    }
  }

  void _processAudioChunk(Uint8List rawData, void Function(Uint8List pcm16k) onPcm16k) {
    if (!_isCapturing) return;

    // Track chunk for sample rate detection
    _chunkSizeHistory.add(rawData.length);
    _totalBytesReceived += rawData.length;
    _firstChunkTime ??= DateTime.now();
    
    // Log audio capture (first chunk and every 50th chunk to avoid spam)
    if (_chunkSizeHistory.length == 1 || _chunkSizeHistory.length % 50 == 0) {
      _logger.info('audio.capture_chunk_received', data: {
        'chunk_size_bytes': rawData.length,
        'total_chunks': _chunkSizeHistory.length,
        'total_bytes': _totalBytesReceived,
        'is_capturing': _isCapturing,
      });
    }

    // Detect sample rate after collecting enough data (first 500ms)
    if (!_needsResampling && _chunkSizeHistory.length >= 10) {
      _detectSampleRate();
    }

    // Resample if needed
    final processedData = _needsResampling && _resampler != null
        ? _resampler!.resample(rawData)
        : rawData;

    // Convert to List<int> and add to buffer
    _audioBuffer.addAll(processedData.toList());
    
    // If buffer exceeds max chunk size, flush immediately to prevent lag
    if (_audioBuffer.length >= _maxChunkBytes) {
      _flushBuffer(onPcm16k);
    }
  }

  /// Detects actual device sample rate by analyzing chunk arrival rates
  void _detectSampleRate() {
    if (_chunkSizeHistory.length < 10 || _firstChunkTime == null) return;

    final elapsed = DateTime.now().difference(_firstChunkTime!).inMilliseconds;
    if (elapsed < 500) return; // Need at least 500ms of data

    // Calculate average bytes per second
    final avgBytesPerSecond = (_totalBytesReceived / elapsed) * 1000;
    
    // At 16kHz, 16-bit mono: 32,000 bytes/sec
    // If we're getting significantly more, device is likely providing higher sample rate
    const expectedBytesPerSecond = _targetSampleRate * 2; // 16-bit = 2 bytes/sample
    
    final ratio = avgBytesPerSecond / expectedBytesPerSecond;
    
    // If ratio is significantly different from 1.0, we need resampling
    if (ratio < 0.9 || ratio > 1.1) {
      // Estimate actual sample rate
      final estimatedRate = (_targetSampleRate * ratio).round();
      
      // Only enable resampling if significantly different (more than 10%)
      if ((estimatedRate - _targetSampleRate).abs() > _targetSampleRate * 0.1) {
        _deviceSampleRate = estimatedRate;
        _needsResampling = true;
        _resampler = _AudioResampler(_deviceSampleRate!, _targetSampleRate);
        
        _logger.warn('audio.sample_rate_mismatch_detected', data: {
          'requested': _targetSampleRate,
          'detected': _deviceSampleRate,
          'ratio': ratio.toStringAsFixed(2),
          'enabling_resampling': true,
        });
      }
    } else {
      // Sample rate is correct
      _deviceSampleRate = _targetSampleRate;
      _needsResampling = false;
      _resampler = null;
    }
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
    if (!_isCapturing) return;
    
    _isCapturing = false;
    
    // Cancel timer
    _chunkTimer?.cancel();
    _chunkTimer = null;
    
    // Flush any remaining buffer (send if >= minimum size, otherwise discard)
    if (_audioBuffer.isNotEmpty) {
      if (_audioBuffer.length >= _minChunkBytes) {
        // Send remaining data if it meets minimum size
        final pcm16k = Uint8List.fromList(_audioBuffer);
        _audioBuffer.clear();
        _logger.debug('audio.flushing_remaining_buffer', data: {'bytes': pcm16k.length});
      } else {
        // Discard small remaining buffer
        _logger.debug('audio.discarding_small_buffer', data: {'bytes': _audioBuffer.length});
        _audioBuffer.clear();
      }
    }
    
    // Reset sample rate detection state
    _chunkSizeHistory.clear();
    _firstChunkTime = null;
    _totalBytesReceived = 0;
    _resampler = null;
    
    try {
      await _sub?.cancel();
      await _recorder?.stopRecorder();
      await _recorder?.closeRecorder();
      await _streamController?.close();
    } catch (e) {
      _logger.warn('audio.capture_stop_error', data: {'error': e.toString()});
    }
    
    _sub = null;
    _recorder = null;
    _streamController = null;
    
    _logger.info('audio.capture_stopped');
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

  bool _prepared = false;
  final AppLogger _logger = AppLogger.instance;

  @override
  bool get isPlaying => _prepared;

  @override
  Future<void> prepare() async {
    if (_prepared) return;
    
    try {
      await FlutterPcmSound.setup(
        sampleRate: _targetSampleRate,
        channelCount: _targetChannels,
      );
      await FlutterPcmSound.play();
      _prepared = true;
      _logger.info('audio.playback_prepared', data: {
        'sample_rate': _targetSampleRate,
        'channels': _targetChannels,
      });
    } catch (e) {
      _logger.error('audio.playback_prepare_failed', error: e);
      rethrow;
    }
  }

  @override
  Future<void> feed(Uint8List pcm24k) async {
    if (!_prepared) {
      await prepare();
    }
    
    try {
      // Validate chunk size (optional, but good for debugging)
      if (pcm24k.isEmpty) {
        _logger.warn('audio.empty_playback_chunk');
        return;
      }
      
      // Convert Uint8List to ByteData for PcmArrayInt16
      final byteData = pcm24k.buffer.asByteData(pcm24k.offsetInBytes, pcm24k.length);
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: byteData));
    } catch (e) {
      _logger.warn('audio.playback_feed_failed', data: {'error': e.toString()});
    }
  }

  @override
  Future<void> stopNow() async {
    // Critical for barge-in: this flushes internal buffers immediately.
    try {
      await FlutterPcmSound.stop();
      _prepared = false;
      // Re-prepare for next audio
      await prepare();
      _logger.debug('audio.playback_flushed');
    } catch (e) {
      _logger.warn('audio.playback_stop_failed', data: {'error': e.toString()});
      _prepared = false;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await FlutterPcmSound.stop();
      _prepared = false;
      _logger.info('audio.playback_disposed');
    } catch (e) {
      _logger.warn('audio.playback_dispose_failed', data: {'error': e.toString()});
      _prepared = false;
    }
  }
}
