import { v4 as uuidv4 } from "uuid";
import { pcm16ToWavBuffer } from "../utils/audio.utils.js";
import type { AudioPipelineLike, TurnResult } from "./audio.pipeline.js";

export class StubAudioPipeline implements AudioPipelineLike {
  constructor(private readonly sampleRate: number) {}

  async handleTurn(_wavAudio: Buffer, sessionId?: string): Promise<TurnResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const responseText = "Stub mode is enabled. Configure ASR/LLM/TTS to use real inference.";

    return {
      session_id: resolvedSessionId,
      transcript_text: "",
      response_text: responseText,
      response_audio_wav_b64: makeSilentWavB64(0.4, this.sampleRate),
      response_audio_sample_rate: this.sampleRate
    };
  }

  async handleTextTurn(text: string, sessionId?: string): Promise<TurnResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const transcriptText = text.trim();

    const responseText = transcriptText
      ? `Stub reply: ${transcriptText}`
      : "Stub mode is enabled. Send {text: ...} to test.";

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText,
      response_audio_wav_b64: makeSilentWavB64(0.4, this.sampleRate),
      response_audio_sample_rate: this.sampleRate
    };
  }

  async transcribeOnly(_wavAudio: Buffer, sessionId?: string): Promise<{ session_id: string; transcript_text: string }> {
    const resolvedSessionId = sessionId ?? uuidv4();
    return {
      session_id: resolvedSessionId,
      transcript_text: "Stub transcription."
    };
  }
}

function makeSilentWavB64(seconds: number, sampleRate: number): string {
  const frames = Math.max(1, Math.floor(seconds * sampleRate));
  const pcm = Buffer.alloc(frames * 2); // PCM16LE mono silence
  const wav = pcm16ToWavBuffer(pcm, sampleRate, 1);
  return wav.toString("base64");
}
