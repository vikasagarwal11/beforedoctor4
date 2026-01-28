import 'dart:collection';
import 'dart:typed_data';

class AudioFrame {
  final Uint8List data; // PCM16 bytes
  final int timestampMs; // Monotonic timestamp
  final int sequenceNumber;

  AudioFrame({
    required this.data,
    required this.timestampMs,
    required this.sequenceNumber,
  });

  int get sizeBytes => data.length;
}

class AudioQueueManager {
  // Configuration
  static const int _maxBufferMs = 800; // 0.8 seconds
  static const int _chunkMs = 20; // 20ms per frame
  static const int _maxQueuedFrames = _maxBufferMs ~/ _chunkMs; // 40 frames

  // State
  final Queue<AudioFrame> _queue = Queue<AudioFrame>();
  int _totalDroppedFrames = 0;
  int _sequenceCounter = 0;

  // Metrics
  DateTime _lastMetricsResetAt = DateTime.now();
  int _framesEnqueuedSinceReset = 0;
  int _framesDroppedSinceReset = 0;

  /// Enqueue a captured audio frame.
  /// Returns false if frame was dropped due to overflow.
  bool enqueue(Uint8List audioData, int timestampMs) {
    final frame = AudioFrame(
      data: audioData,
      timestampMs: timestampMs,
      sequenceNumber: _sequenceCounter++,
    );

    _framesEnqueuedSinceReset++;

    // Check backpressure: if queue is full, drop oldest
    if (_queue.length >= _maxQueuedFrames) {
      _queue.removeFirst(); // Drop oldest
      _totalDroppedFrames++;
      _framesDroppedSinceReset++;
      return false;
    }

    _queue.add(frame);
    return true;
  }

  /// Dequeue frames for sending (batch all available).
  List<AudioFrame> dequeueBatch() {
    final batch = _queue.toList();
    _queue.clear();
    return batch;
  }

  /// Dequeue up to N frames.
  List<AudioFrame> dequeueUpTo(int count) {
    final batch = <AudioFrame>[];
    for (int i = 0; i < count && _queue.isNotEmpty; i++) {
      batch.add(_queue.removeFirst());
    }
    return batch;
  }

  /// Clear all queued frames (e.g., on error or stop).
  void clear() {
    _queue.clear();
  }

  /// Get current queue depth in frames.
  int get queueDepthFrames => _queue.length;

  /// Get current queue depth in milliseconds.
  int get queueDepthMs => queueDepthFrames * _chunkMs;

  /// Get total dropped frames since instantiation.
  int get totalDroppedFrames => _totalDroppedFrames;

  /// Get dropped frames since last reset.
  int get droppedFramesSinceReset => _framesDroppedSinceReset;

  /// Get frames enqueued since last reset.
  int get framesEnqueuedSinceReset => _framesEnqueuedSinceReset;

  /// Reset metrics.
  void resetMetrics() {
    _lastMetricsResetAt = DateTime.now();
    _framesEnqueuedSinceReset = 0;
    _framesDroppedSinceReset = 0;
  }

  /// Get metrics snapshot.
  AudioQueueMetrics getMetrics() {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastMetricsResetAt).inMilliseconds;
    final frameRate =
        elapsedMs > 0 ? (_framesEnqueuedSinceReset * 1000 / elapsedMs) : 0.0;
    final dropRate = _framesEnqueuedSinceReset > 0
        ? (_framesDroppedSinceReset / _framesEnqueuedSinceReset * 100)
        : 0.0;

    return AudioQueueMetrics(
      queueDepthFrames: queueDepthFrames,
      queueDepthMs: queueDepthMs,
      totalDroppedFrames: _totalDroppedFrames,
      droppedSinceReset: _framesDroppedSinceReset,
      frameRateHz: frameRate,
      dropRatePercent: dropRate,
    );
  }
}

class AudioQueueMetrics {
  final int queueDepthFrames;
  final int queueDepthMs;
  final int totalDroppedFrames;
  final int droppedSinceReset;
  final double frameRateHz;
  final double dropRatePercent;

  AudioQueueMetrics({
    required this.queueDepthFrames,
    required this.queueDepthMs,
    required this.totalDroppedFrames,
    required this.droppedSinceReset,
    required this.frameRateHz,
    required this.dropRatePercent,
  });

  @override
  String toString() =>
      'AudioQueueMetrics(depth=${queueDepthFrames}fr/${queueDepthMs}ms, '
      'dropped=$droppedSinceReset, rate=${frameRateHz.toStringAsFixed(1)}Hz, '
      'dropRate=${dropRatePercent.toStringAsFixed(2)}%)';
}
