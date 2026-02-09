import { serviceUnavailable } from "../utils/errors.js";

export type TtsResult = {
  audio_wav_b64: string;
  sample_rate: number;
};

export class TtsService {
  constructor(private readonly baseUrl: string) {}

  async synthesizeToWav(text: string): Promise<TtsResult> {
    // Add timeout to prevent hanging on large text (180 second timeout for slow CPU synthesis)
    const controller = new AbortController();
    const timeoutHandle = setTimeout(() => controller.abort(), 180000);
    
    try {
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

      return (await res.json()) as TtsResult;
    } finally {
      clearTimeout(timeoutHandle);
    }
  }
}
