import 'dart:typed_data';

class PlaybackBufferManager {
  // Configuration
  static const int startPrebufferMs = 700;
  static const int lowWaterMs = 250;
  static const int targetBufferMs = 500;
  static const int maxBufferMs = 1500;
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2;
  static const int frameMs = 40; // Aggregate two 20ms frames before feeding

  // Derived
  static const int _frameSamples = (sampleRate * frameMs) ~/ 1000;
  static const int _frameBytes = _frameSamples * bytesPerSample;
  static const int _maxBufferSamples = (maxBufferMs * sampleRate) ~/ 1000;

  static int get frameSamples => _frameSamples;

  // State
  late final Int16List _ring = Int16List(_maxBufferSamples);
  int _readIndex = 0;
  int _writeIndex = 0;
  int _bufferedSamples = 0;
  bool _playbackInitialized = false;
  bool _prebuffering = true;

  /// Add AI audio chunk to jitter buffer.
  int enqueueAiAudio(Uint8List audioData) {
    if (audioData.isEmpty) return 0;
    if (_isMostlySilent(audioData)) return 0;

    final evenLength = audioData.lengthInBytes - (audioData.lengthInBytes % 2);
    if (evenLength == 0) return 0;
    final samples = Int16List.view(
      audioData.buffer,
      audioData.offsetInBytes,
      evenLength ~/ 2,
    );

    return _writeSamples(samples) * bytesPerSample;
  }

  int _writeSamples(Int16List samples) {
    final total = samples.length;
    if (total == 0) return 0;

    if (total >= _maxBufferSamples) {
      final start = total - _maxBufferSamples;
      for (int i = 0; i < _maxBufferSamples; i++) {
        _ring[i] = samples[start + i];
      }
      _readIndex = 0;
      _writeIndex = 0;
      _bufferedSamples = _maxBufferSamples;
      return total - _maxBufferSamples;
    }

    int dropped = 0;
    final overflow = _bufferedSamples + total - _maxBufferSamples;
    if (overflow > 0) {
      _readIndex = (_readIndex + overflow) % _maxBufferSamples;
      _bufferedSamples -= overflow;
      dropped = overflow;
    }

    for (int i = 0; i < total; i++) {
      _ring[_writeIndex] = samples[i];
      _writeIndex = (_writeIndex + 1) % _maxBufferSamples;
      _bufferedSamples += 1;
    }

    return dropped;
  }

  /// Pull a fixed-size frame; pads with zeros if data is insufficient.
  PlaybackPull pullFrame() {
    final outSamples = Int16List(_frameSamples);
    var paddedSamples = 0;

    for (int i = 0; i < _frameSamples; i++) {
      if (_bufferedSamples > 0) {
        outSamples[i] = _ring[_readIndex];
        _readIndex = (_readIndex + 1) % _maxBufferSamples;
        _bufferedSamples -= 1;
      } else {
        outSamples[i] = 0;
        paddedSamples += 1;
      }
    }

    return PlaybackPull(
      data: Uint8List.view(outSamples.buffer),
      usedSilence: paddedSamples > 0,
      providedSamples: _frameSamples - paddedSamples,
      paddedSamples: paddedSamples,
    );
  }

  bool get canStartPlayback =>
      !_playbackInitialized && bufferedMs >= startPrebufferMs;

  void markPlaybackStarted() {
    _playbackInitialized = true;
    _prebuffering = false;
  }

  void resetForTurn() {
    _readIndex = 0;
    _writeIndex = 0;
    _bufferedSamples = 0;
    _playbackInitialized = false;
    _prebuffering = true;
  }

  bool get isPrebuffering => _prebuffering;
  bool get isPlaybackInitialized => _playbackInitialized;

  int get bufferedMs => (_bufferedSamples * 1000) ~/ sampleRate;
  int get bufferedSamples => _bufferedSamples;
  int get frameBytes => _frameBytes;

  /// Clear buffer (e.g., on stop or barge-in).
  void clear() {
    resetForTurn();
  }

  /// Get metrics snapshot.
  PlaybackBufferMetrics getMetrics() {
    return PlaybackBufferMetrics(
      bufferedMs: bufferedMs,
      isPrebuffering: isPrebuffering,
      maxBufferMs: maxBufferMs,
    );
  }

  bool _isMostlySilent(Uint8List frame) {
    const int silenceThreshold = 200; // PCM16 absolute amplitude
    const double maxSilentRatio = 0.95;

    final samples = frame.length ~/ 2;
    if (samples == 0) return true;

    int loudSamples = 0;
    for (int i = 0; i + 1 < frame.length; i += 2) {
      final low = frame[i];
      final high = frame[i + 1];
      var sample = (high << 8) | low;
      if (sample > 32767) sample -= 65536;
      if (sample.abs() > silenceThreshold) {
        loudSamples++;
        if (loudSamples > samples * (1 - maxSilentRatio)) {
          return false;
        }
      }
    }

    return true;
  }
}

class PlaybackPull {
  final Uint8List data;
  final bool usedSilence;
  final int providedSamples;
  final int paddedSamples;

  const PlaybackPull({
    required this.data,
    required this.usedSilence,
    required this.providedSamples,
    required this.paddedSamples,
  });
}

class PlaybackBufferMetrics {
  final int bufferedMs;
  final bool isPrebuffering;
  final int maxBufferMs;

  PlaybackBufferMetrics({
    required this.bufferedMs,
    required this.isPrebuffering,
    required this.maxBufferMs,
  });

  @override
  String toString() => 'PlaybackBufferMetrics(depth=${bufferedMs}ms, '
      'prebuffering=$isPrebuffering, max=${maxBufferMs}ms)';
}
