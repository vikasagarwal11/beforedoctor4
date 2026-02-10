import { serviceUnavailable } from "../utils/errors.js";

export type AsrResult = {
  transcript: string;
};

export class AsrService {
  constructor(private readonly baseUrl: string) {}

  async transcribeWav(wavBytes: Buffer): Promise<AsrResult> {
    const res = await fetch(`${this.baseUrl}/v1/asr`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        audio_b64: wavBytes.toString("base64")
      })
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw serviceUnavailable("ASR worker failed", { status: res.status, body: text });
    }

    return (await res.json()) as AsrResult;
  }
}
