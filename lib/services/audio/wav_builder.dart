import 'dart:typed_data';

/// Builds a minimal PCM16LE WAV container.
///
/// This is used when we capture mic PCM (16kHz, mono, s16le) and need to send a
/// single WAV payload to a backend (e.g., Supabase Edge Function).
Uint8List buildPcm16Wav(
  Uint8List pcm16le, {
  required int sampleRate,
  int channels = 1,
}) {
  const int bitsPerSample = 16;
  const int bytesPerSample = bitsPerSample ~/ 8;
  final int blockAlign = channels * bytesPerSample;
  final int byteRate = sampleRate * blockAlign;

  final header = ByteData(44);

  // RIFF header
  header.setUint32(0, 0x46464952, Endian.little); // "RIFF"
  header.setUint32(4, 36 + pcm16le.length, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little); // "WAVE"

  // fmt chunk
  header.setUint32(12, 0x20746d66, Endian.little); // "fmt "
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  header.setUint16(20, 1, Endian.little); // audio format = PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);

  // data chunk
  header.setUint32(36, 0x61746164, Endian.little); // "data"
  header.setUint32(40, pcm16le.length, Endian.little);

  final out = Uint8List(44 + pcm16le.length);
  out.setAll(0, header.buffer.asUint8List());
  out.setAll(44, pcm16le);
  return out;
}
