import 'dart:math';
import 'dart:typed_data';

enum VadSensitivity { high, medium, low }

enum VadDecision { speech, silence, unknown }

class VadFrame {
  final Uint8List audioData; // Original PCM16 data
  final VadDecision decision; // Detected: speech or silence
  final double confidence; // 0.0..1.0 confidence of detection
  final int timestampMs;

  VadFrame({
    required this.audioData,
    required this.decision,
    required this.confidence,
    required this.timestampMs,
  });
}

/// Simple VAD processor that applies pre-roll and hang-over buffering.
/// Production systems would use a real ML model (e.g., WebRTC VAD, Silero, Google's VAD).
class VadProcessor {
  final VadSensitivity sensitivity;
  final int preRollFrames; // Frames to buffer before speech detected
  final int hangoverFrames; // Frames to keep after speech ends

  late int _silenceThresholdDb;
  late List<Uint8List> _preRollBuffer;
  late int _hangoverCounter;
  late bool _inSpeech;

  VadProcessor({
    this.sensitivity = VadSensitivity.medium,
    this.preRollFrames = 10, // ~200ms @ 20ms/frame
    this.hangoverFrames = 12, // ~240ms @ 20ms/frame
  }) {
    _initSensitivity();
    _preRollBuffer = [];
    _hangoverCounter = 0;
    _inSpeech = false;
  }

  void _initSensitivity() {
    _silenceThresholdDb = switch (sensitivity) {
      VadSensitivity.high => -50, // Very sensitive
      VadSensitivity.medium => -40, // Balanced
      VadSensitivity.low => -30, // Conservative
    };
  }

  /// Process a frame and return VAD decision.
  VadDecision processFrame(Uint8List audioData) {
    final energy = _computeEnergy(audioData);
    final energyDb = _energyToDb(energy);
    final hasSpeech = energyDb > _silenceThresholdDb;

    if (hasSpeech) {
      // Speech detected
      _inSpeech = true;
      _hangoverCounter = hangoverFrames;
      _preRollBuffer.clear(); // Don't need pre-roll anymore
      return VadDecision.speech;
    } else {
      // Silence/noise detected
      if (_inSpeech && _hangoverCounter > 0) {
        // Still within hang-over window
        _hangoverCounter--;
        return VadDecision.speech; // Report as speech (hang-over)
      } else if (!_inSpeech && _preRollBuffer.length < preRollFrames) {
        // Buffer for pre-roll
        _preRollBuffer.add(audioData);
        return VadDecision.silence;
      } else {
        // Pre-roll full or not in speech
        _inSpeech = false;
        _hangoverCounter = 0;
        return VadDecision.silence;
      }
    }
  }

  /// Compute RMS energy of audio frame (16-bit PCM).
  double _computeEnergy(Uint8List audioData) {
    if (audioData.isEmpty) return 0.0;

    double sum = 0.0;
    // Read as int16 (2 bytes per sample)
    for (int i = 0; i < audioData.length; i += 2) {
      if (i + 1 < audioData.length) {
        final sample = _readInt16(audioData, i);
        sum += sample * sample;
      }
    }

    final rms = sqrt(sum / (audioData.length ~/ 2));
    return rms;
  }

  /// Convert energy to dB scale.
  double _energyToDb(double energy) {
    if (energy < 1e-10) return -100;
    return 20 * (log(energy) / ln10);
  }

  /// Read signed 16-bit integer (little-endian).
  int _readInt16(Uint8List bytes, int offset) {
    final low = bytes[offset];
    final high = bytes[offset + 1];
    int value = (high << 8) | low;
    if (value & 0x8000 != 0) value -= 0x10000;
    return value;
  }

  /// Reset VAD state (e.g., on reconnect).
  void reset() {
    _preRollBuffer.clear();
    _hangoverCounter = 0;
    _inSpeech = false;
  }

  /// Check if we should include pre-roll buffer in outgoing frames.
  List<Uint8List> flushPreRoll() {
    final result = List<Uint8List>.from(_preRollBuffer);
    _preRollBuffer.clear();
    return result;
  }
}
