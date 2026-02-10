// Minimal WAV wrapper for PCM16LE audio.
// Used for WS streaming mode: client sends raw PCM16 frames.

export function pcm16ToWavBuffer(pcm16le: Buffer, sampleRate: number, channels = 1): Buffer {
  const bytesPerSample = 2;
  const blockAlign = channels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;

  const wavHeader = Buffer.alloc(44);
  wavHeader.write("RIFF", 0);
  wavHeader.writeUInt32LE(36 + pcm16le.length, 4);
  wavHeader.write("WAVE", 8);
  wavHeader.write("fmt ", 12);
  wavHeader.writeUInt32LE(16, 16); // PCM
  wavHeader.writeUInt16LE(1, 20); // format
  wavHeader.writeUInt16LE(channels, 22);
  wavHeader.writeUInt32LE(sampleRate, 24);
  wavHeader.writeUInt32LE(byteRate, 28);
  wavHeader.writeUInt16LE(blockAlign, 32);
  wavHeader.writeUInt16LE(16, 34); // bits
  wavHeader.write("data", 36);
  wavHeader.writeUInt32LE(pcm16le.length, 40);

  return Buffer.concat([wavHeader, pcm16le]);
}

/**
 * Extract raw PCM data from a WAV file buffer.
 * Assumes PCM16LE format. Returns the data chunk without WAV headers.
 */
export function extractPcmFromWav(wavBuffer: Buffer): Buffer {
  if (wavBuffer.length < 44) {
    throw new Error("WAV file too small (< 44 bytes)");
  }

  // Check RIFF header
  const riff = wavBuffer.toString("ascii", 0, 4);
  const wave = wavBuffer.toString("ascii", 8, 12);
  if (riff !== "RIFF" || wave !== "WAVE") {
    throw new Error("Not a valid WAV file");
  }

  // Find the 'data' chunk
  let offset = 12;
  while (offset + 8 <= wavBuffer.length) {
    const chunkId = wavBuffer.toString("ascii", offset, offset + 4);
    const chunkSize = wavBuffer.readUInt32LE(offset + 4);
    
    if (chunkId === "data") {
      // Found data chunk - return the PCM data
      const dataStart = offset + 8;
      const dataEnd = Math.min(dataStart + chunkSize, wavBuffer.length);
      return wavBuffer.subarray(dataStart, dataEnd);
    }
    
    // Move to next chunk
    offset += 8 + chunkSize;
  }

  throw new Error("No 'data' chunk found in WAV file");
}
