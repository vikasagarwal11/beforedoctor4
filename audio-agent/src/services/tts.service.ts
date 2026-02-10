import { extractPcmFromWav } from "../utils/audio.utils.js";
import { serviceUnavailable } from "../utils/errors.js";

export type TtsResult = {
  audio_pcm_b64: string;
  sample_rate: number;
  channels: number;
};

type RawTtsResponse = {
  audio_pcm_b64?: string;
  audio_wav_b64?: string;
  sample_rate?: number;
  channels?: number;
};

/**
 * TTS Service - PCM16, 24kHz, Mono output from worker
 *
 * The worker returns raw PCM16LE base64 and resamples to 24kHz.
 * This service validates and reports metrics only.
 */
export class TtsService {
  constructor(private readonly baseUrl: string) {}

  async synthesizeToPcm(text: string): Promise<TtsResult> {
    // Add timeout to prevent hanging on large text (180 second timeout for slow CPU synthesis)
    const controller = new AbortController();
    const timeoutHandle = setTimeout(() => controller.abort(), 180000);
    
    try {
      console.log(`[TTS] Requesting synthesis: ${text.length} chars`);
      
      // TTS worker already handles format conversion (22050Hz → 24000Hz resampling)
      // and quality parameters are set in service.py
      const res = await fetch(`${this.baseUrl}/v1/tts`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ text }),
        signal: controller.signal
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        throw serviceUnavailable("TTS worker failed", { status: res.status, body });
      }

      const result = (await res.json()) as RawTtsResponse;
      
      let audioPcmB64 = result.audio_pcm_b64;
      if (!audioPcmB64 && result.audio_wav_b64) {
        const wavBuffer = Buffer.from(result.audio_wav_b64, "base64");
        const pcmBuffer = extractPcmFromWav(wavBuffer);
        audioPcmB64 = pcmBuffer.toString("base64");
      }

      // Validate output format
      if (!audioPcmB64) {
        throw serviceUnavailable("TTS worker returned empty audio", {});
      }
      
      // Decode base64 to get actual byte count
      const audioBytes = Buffer.from(audioPcmB64, "base64");
      const pcmBytes = audioBytes.length;
      const sampleRate = result.sample_rate || 24000;
      const channels = result.channels || 1;
      const sampleCount = pcmBytes / 2; // 2 bytes per sample (16-bit)
      const durationSec = sampleCount / sampleRate;
      
      console.log(`[TTS] Synthesis complete:`, {
        text_chars: text.length,
        audio_b64_length: audioPcmB64.length,
        audio_bytes: audioBytes.length,
        pcm_bytes: pcmBytes,
        sample_rate: sampleRate,
        channels,
        duration_sec: durationSec.toFixed(2),
      });
      
      // Force defaults if not provided
      return {
        audio_pcm_b64: audioPcmB64,
        sample_rate: sampleRate,
        channels,
      };
    } finally {
      clearTimeout(timeoutHandle);
    }
  }
}
