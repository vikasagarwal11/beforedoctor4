import { v4 as uuidv4 } from "uuid";
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
      response_audio_pcm_b64: makeSilentPcmB64(0.4, this.sampleRate),
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
      response_audio_pcm_b64: makeSilentPcmB64(0.4, this.sampleRate),
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

  async handleTurnTextOnly(_wavAudio: Buffer, sessionId?: string): Promise<{ session_id: string; transcript_text: string; response_text: string }> {
    const resolvedSessionId = sessionId ?? uuidv4();
    return {
      session_id: resolvedSessionId,
      transcript_text: "Stub transcription.",
      response_text: "Stub reply."
    };
  }

  async handleTextTurnTextOnly(text: string, sessionId?: string): Promise<{ session_id: string; response_text: string }> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const transcriptText = text.trim();
    return {
      session_id: resolvedSessionId,
      response_text: transcriptText ? `Stub reply: ${transcriptText}` : ""
    };
  }

  async streamAssistantAudio(
    _text: string,
    _onChunk: (chunk: Buffer) => Promise<void> | void
  ): Promise<void> {
    return;
  }
}

function makeSilentPcmB64(seconds: number, sampleRate: number): string {
  const frames = Math.max(1, Math.floor(seconds * sampleRate));
  const pcm = Buffer.alloc(frames * 2); // PCM16LE mono silence
  return pcm.toString("base64");
}
