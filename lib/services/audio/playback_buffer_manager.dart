import 'dart:collection';
import 'dart:typed_data';

class PlaybackFrame {
  final Uint8List data; // PCM16 bytes
  final int sequenceNumber;

  PlaybackFrame({required this.data, required this.sequenceNumber});
}

class PlaybackBufferManager {
  // Configuration
  static const int _prebufferMs =
      30; // Reduced from 40ms for even lower latency
  static const int _chunkMs = 20; // Standard chunk duration
  static const int _maxBufferMs = 800; // Max buffer before we drop

  // Derived
  static const int _prebufferFrames =
      _prebufferMs ~/ _chunkMs; // 1.5 = 1 frame (30ms)
  static const int _maxBufferFrames = _maxBufferMs ~/ _chunkMs;

  // State
  final Queue<PlaybackFrame> _buffer = Queue<PlaybackFrame>();
  bool _playbackStarted = false;
  int _sequenceCounter = 0;
  int _totalUnderrunEvents = 0;

  // Callbacks
  late Function(List<PlaybackFrame>) onFeedToEngine;
  late Function() onUnderrun;

  /// Add AI audio frame to playback buffer.
  void enqueueAiAudio(Uint8List audioData) {
    // Handle large audio chunks by splitting them into smaller frames
    // Each frame is expected to be ~10ms of audio (480 bytes at 24kHz 16-bit mono)
    // Smaller frames = lower latency = less choppy audio
    // 24kHz * 0.01 seconds * 2 bytes/sample = 480 bytes per 10ms

    const int targetFrameBytes =
        480; // 10ms at 24kHz, 16-bit, mono (24000 * 0.01 * 2)

    if (audioData.length <= targetFrameBytes * 2) {
      // Small chunk - add as single frame
      final frame = PlaybackFrame(
        data: audioData,
        sequenceNumber: _sequenceCounter++,
      );

      // Check for overflow
      if (_buffer.length >= _maxBufferFrames) {
        // Drop oldest frame
        _buffer.removeFirst();
      }

      _buffer.add(frame);
    } else {
      // Large chunk - split into multiple 10ms frames for lower latency
      int offset = 0;
      while (offset < audioData.length) {
        final end = (offset + targetFrameBytes).clamp(0, audioData.length);
        final frameData = Uint8List.sublistView(audioData, offset, end);

        final frame = PlaybackFrame(
          data: frameData,
          sequenceNumber: _sequenceCounter++,
        );

        // Check for overflow
        if (_buffer.length >= _maxBufferFrames) {
          // Drop oldest frame
          _buffer.removeFirst();
        }

        _buffer.add(frame);
        offset = end;
      }
    }
  }

  /// Drain buffered frames for playback.
  /// If prebuffer not met, returns empty list.
  List<PlaybackFrame> drainFrames() {
    final result = <PlaybackFrame>[];

    // If not started yet, check if prebuffer is full
    if (!_playbackStarted) {
      if (_buffer.length >= _prebufferFrames) {
        _playbackStarted = true;
      } else {
        return result; // Still prebuffering
      }
    }

    // Playback started or prebuffer full: drain all available
    while (_buffer.isNotEmpty) {
      result.add(_buffer.removeFirst());
    }

    // Detect underrun
    if (_playbackStarted && result.isEmpty) {
      _totalUnderrunEvents++;
      return result;
    }

    return result;
  }

  /// Get prebuffer status.
  bool get isPrebuffering => !_playbackStarted;

  /// Get current buffer depth in frames.
  int get bufferDepthFrames => _buffer.length;

  /// Get current buffer depth in milliseconds.
  int get bufferDepthMs => bufferDepthFrames * _chunkMs;

  /// Get buffer fill percentage.
  double get bufferFillPercent => (bufferDepthFrames / _maxBufferFrames) * 100;

  /// Total underrun events since start.
  int get totalUnderrunEvents => _totalUnderrunEvents;

  /// Clear buffer (e.g., on stop or barge-in).
  void clear() {
    _buffer.clear();
    _playbackStarted = false;
    _totalUnderrunEvents = 0;
  }

  /// Reset playback start flag (for e.g., turn completion).
  void resetPlaybackStart() {
    _playbackStarted = false;
  }

  /// Get metrics snapshot.
  PlaybackBufferMetrics getMetrics() {
    return PlaybackBufferMetrics(
      bufferDepthFrames: bufferDepthFrames,
      bufferDepthMs: bufferDepthMs,
      bufferFillPercent: bufferFillPercent,
      isPrebuffering: isPrebuffering,
      totalUnderrunEvents: _totalUnderrunEvents,
      maxBufferFrames: _maxBufferFrames,
    );
  }
}

class PlaybackBufferMetrics {
  final int bufferDepthFrames;
  final int bufferDepthMs;
  final double bufferFillPercent;
  final bool isPrebuffering;
  final int totalUnderrunEvents;
  final int maxBufferFrames;

  PlaybackBufferMetrics({
    required this.bufferDepthFrames,
    required this.bufferDepthMs,
    required this.bufferFillPercent,
    required this.isPrebuffering,
    required this.totalUnderrunEvents,
    required this.maxBufferFrames,
  });

  @override
  String toString() =>
      'PlaybackBufferMetrics(depth=${bufferDepthFrames}fr/${bufferDepthMs}ms, '
      'fill=${bufferFillPercent.toStringAsFixed(1)}%, '
      'prebuffering=$isPrebuffering, underruns=$totalUnderrunEvents)';
}
