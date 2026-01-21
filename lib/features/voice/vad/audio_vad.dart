import 'dart:math';
import 'dart:typed_data';

/// VAD sensitivity presets for different environments
enum VadSensitivity {
  veryLow,    // Noisy environments (car, street, kids, construction)
  low,        // Moderate noise (office, cafe, open space)
  medium,     // Normal quiet environment (default)
  high,       // Quiet room, low background noise
  veryHigh,   // Studio/silent environment
}

/// Lightweight energy-based VAD with adaptive noise floor.
/// Works on 16-bit PCM mono little-endian frames (e.g., 16kHz, 20ms = 640 bytes).
///
/// Usage:
///   final vad = AudioVad();
///   vad.processPcm16(frameBytes); // call per mic frame
///   if (vad.shouldCommitTurnComplete(nowMs)) { ... }
///
/// Or with sensitivity preset:
///   final vad = AudioVad.preset(VadSensitivity.low); // For noisy environment
class AudioVad {
  // --- Tunables (start here) ---
  /// Minimum speech dB above the learned noise floor to consider as "voice".
  /// Typical: 10-16 dB. Higher => less sensitive (fewer false positives).
  final double speechDbAboveNoise;

  /// How long of continuous silence before we "arm" endpoint (ms).
  /// Typical: 450-700ms for natural end-of-sentence detection.
  final int endpointSilenceMs;

  /// How long of silence before we commit sending turnComplete (ms).
  /// Typical: 1200-1800ms.
  final int commitSilenceMs;

  /// Minimum time from start of detected speech before we allow committing (ms).
  /// Prevents "hello" micro-bursts from auto-committing instantly.
  final int minSpeechMsBeforeCommit;

  /// Noise floor adaptation speed (0..1). Lower is slower (more stable).
  final double noiseLerp;

  /// Clamp range for noise floor in dBFS (since mic environments vary).
  final double minNoiseDb;
  final double maxNoiseDb;

  // --- State ---
  double _noiseFloorDb; // learned
  bool _calibrating = true;
  int _calibrationStartMs = 0;

  int _lastFrameMs = 0;
  int _lastVoiceMs = 0;
  int _speechStartMs = 0;

  bool _inSpeech = false;
  bool _endpointArmed = false;

  /// Create VAD with preset sensitivity profile for different environments
  factory AudioVad.preset(VadSensitivity sensitivity) {
    switch (sensitivity) {
      case VadSensitivity.veryLow:
        return AudioVad(
          speechDbAboveNoise: 16.0,  // Higher threshold (less sensitive to noise)
          commitSilenceMs: 2000,     // Longer pause (prevent cutting off in noisy env)
          minSpeechMsBeforeCommit: 500,
        );
      case VadSensitivity.low:
        return AudioVad(
          speechDbAboveNoise: 14.0,
          commitSilenceMs: 1800,
          minSpeechMsBeforeCommit: 400,
        );
      case VadSensitivity.medium:
        return AudioVad(); // Default
      case VadSensitivity.high:
        return AudioVad(
          speechDbAboveNoise: 10.0,  // Lower threshold (more sensitive)
          commitSilenceMs: 1400,     // Shorter pause (faster response)
          minSpeechMsBeforeCommit: 300,
        );
      case VadSensitivity.veryHigh:
        return AudioVad(
          speechDbAboveNoise: 8.0,
          commitSilenceMs: 1200,
          minSpeechMsBeforeCommit: 250,
        );
    }
  }

  AudioVad({
    this.speechDbAboveNoise = 12.0,
    this.endpointSilenceMs = 600,
    this.commitSilenceMs = 1600,
    this.minSpeechMsBeforeCommit = 350,
    this.noiseLerp = 0.04,
    this.minNoiseDb = -70,
    this.maxNoiseDb = -25,
    double initialNoiseDb = -55,
  }) : _noiseFloorDb = initialNoiseDb;

  /// Call when a new session starts.
  void reset({required int nowMs}) {
    _calibrating = true;
    _calibrationStartMs = nowMs;

    _lastFrameMs = nowMs;
    _lastVoiceMs = 0;
    _speechStartMs = 0;

    _inSpeech = false;
    _endpointArmed = false;

    // keep noise floor; it will re-adapt quickly.
  }

  /// Call for each PCM16LE mono audio frame.
  /// [nowMs] should be monotonically increasing epoch milliseconds.
  void processPcm16(Uint8List pcm16leBytes, {required int nowMs}) {
    _lastFrameMs = nowMs;

    final db = _dbfsFromPcm16le(pcm16leBytes);

    // Calibration: first 400-600ms we assume mostly background to set a baseline.
    if (_calibrating) {
      if (nowMs - _calibrationStartMs < 600) {
        // move noise floor toward observed db slowly (conservative).
        _noiseFloorDb = _lerp(_noiseFloorDb, _clamp(db, minNoiseDb, maxNoiseDb), 0.08);
        return;
      } else {
        _calibrating = false;
      }
    }

    // Update noise floor when NOT in speech OR when signal is near noise.
    // This keeps noise floor adaptive without drifting upward during speech.
    final isNearNoise = db < (_noiseFloorDb + 3.0);
    if (!_inSpeech || isNearNoise) {
      _noiseFloorDb = _lerp(_noiseFloorDb, _clamp(db, minNoiseDb, maxNoiseDb), noiseLerp);
    }

    final speechThresholdDb = _noiseFloorDb + speechDbAboveNoise;
    final isVoice = db >= speechThresholdDb;

    if (isVoice) {
      _lastVoiceMs = nowMs;

      if (!_inSpeech) {
        _inSpeech = true;
        _speechStartMs = nowMs;
      }

      // While voice present, do not arm endpoint.
      _endpointArmed = false;
    } else {
      // No voice detected.
      if (_inSpeech) {
        final silenceMs = nowMs - _lastVoiceMs;

        // After short silence, arm endpoint (like "end of phrase").
        if (silenceMs >= endpointSilenceMs) {
          _endpointArmed = true;
        }

        // If silence extends too long, we remain "inSpeech" until caller commits.
        // Caller will call markTurnCompleted() which resets state appropriately.
      }
    }
  }

  /// True when we have seen speech, then sufficient silence, and enough speech duration.
  bool shouldCommitTurnComplete(int nowMs) {
    if (!_inSpeech) return false;
    if (!_endpointArmed) return false;

    final speechDuration = nowMs - _speechStartMs;
    if (speechDuration < minSpeechMsBeforeCommit) return false;

    final silenceMs = nowMs - _lastVoiceMs;
    return silenceMs >= commitSilenceMs;
  }

  /// Call after you actually send turnComplete.
  void markTurnCompleted({required int nowMs}) {
    // Reset speech state but keep learned noise floor.
    _inSpeech = false;
    _endpointArmed = false;
    _speechStartMs = 0;
    _lastVoiceMs = 0;

    // brief recalibration window helps after playback stops / environment changes
    _calibrating = true;
    _calibrationStartMs = nowMs;
  }

  /// Optional: expose debugging info
  double get noiseFloorDb => _noiseFloorDb;
  bool get inSpeech => _inSpeech;
  bool get endpointArmed => _endpointArmed;

  // --- Utilities ---

  // Compute dBFS from PCM16LE bytes:
  // RMS in [-1,1], then 20*log10(rms). Clamp.
  static double _dbfsFromPcm16le(Uint8List bytes) {
    if (bytes.isEmpty) return -90.0;
    final bd = ByteData.sublistView(bytes);

    int sampleCount = bytes.length ~/ 2;
    if (sampleCount <= 0) return -90.0;

    double sumSquares = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      final x = s / 32768.0;
      sumSquares += x * x;
    }
    final rms = sqrt(sumSquares / sampleCount);

    // Avoid log(0)
    final clamped = max(rms, 1e-9);
    final db = 20.0 * (log(clamped) / ln10);

    // Typical mic noise in dBFS: -60 to -35
    return db.clamp(-90.0, 0.0);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _clamp(double v, double lo, double hi) => max(lo, min(hi, v));
}
