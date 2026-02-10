/**
 * Audio Chunking Utility
 *
 * Converts large base64 audio blobs into smaller chunks for streaming delivery.
 * This enables progressive audio playback and prevents single-message bottlenecks.
 */

/**
 * Split a base64 audio string into smaller chunks.
 *
 * Each chunk is approximately `chunkSizeBytes` bytes when decoded.
 * The actual base64-encoded chunk will be ~4/3 larger.
 *
 * @param audioB64 - Full audio as base64 string
 * @param chunkSizeBytes - Target size per chunk in raw bytes (default 48000 ≈ 1s @ 24kHz)
 * @returns Array of base64-encoded chunks
 */
export function chunkBase64Audio(audioB64: string, chunkSizeBytes = 48000): string[] {
  if (!audioB64 || audioB64.length === 0) {
    return [];
  }

  // Base64 encoding increases size by ~33% (4 chars per 3 bytes)
  // So we need 4/3 more base64 characters to cover chunkSizeBytes
  const chunkSizeB64 = Math.ceil((chunkSizeBytes * 4) / 3);

  const chunks: string[] = [];
  for (let i = 0; i < audioB64.length; i += chunkSizeB64) {
    chunks.push(audioB64.substring(i, i + chunkSizeB64));
  }

  return chunks.length > 0 ? chunks : [audioB64];
}

/**
 * Get rough duration of audio in seconds.
 *
 * Assumes 24kHz sample rate, 16-bit (2 bytes per sample).
 * Actual duration = bytes / (24000 * 2)
 *
 * @param audioBytes - Raw audio bytes
 * @returns Estimated duration in seconds
 */
export function estimateAudioDuration(audioBytes: number): number {
  const sampleRate = 24000; // Hz
  const bytesPerSample = 2; // 16-bit
  return audioBytes / (sampleRate * bytesPerSample);
}
