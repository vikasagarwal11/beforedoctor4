import { v4 as uuidv4 } from "uuid";
import type { DbPool } from "../db/db.connection.js";
import { AsrService } from "../services/asr.service.js";
import { LlmService } from "../services/llm.service.js";
import { TtsService } from "../services/tts.service.js";

export type TurnResult = {
  session_id: string;
  transcript_text: string;
  response_text: string;
  response_audio_pcm_b64: string;
  response_audio_sample_rate: number;
};

export type TranscribeResult = {
  session_id: string;
  transcript_text: string;
};

export type AudioPipelineLike = {
  handleTurn(wavAudio: Buffer, sessionId?: string): Promise<TurnResult>;
  handleTextTurn(text: string, sessionId?: string): Promise<TurnResult>;
  transcribeOnly(wavAudio: Buffer, sessionId?: string): Promise<TranscribeResult>;
  handleTurnTextOnly(wavAudio: Buffer, sessionId?: string): Promise<{ session_id: string; transcript_text: string; response_text: string }>;
  handleTextTurnTextOnly(text: string, sessionId?: string): Promise<{ session_id: string; response_text: string }>;
  streamAssistantAudio(text: string, onChunk: (chunk: Buffer) => Promise<void> | void): Promise<void>;
};

type TtsResult = { audio_pcm_b64: string; sample_rate: number; channels: number };

enum PipelineState {
  IDLE = "IDLE",
  LISTENING = "LISTENING",
  TRANSCRIBED = "TRANSCRIBED",
  WAITING_FOR_SEND = "WAITING_FOR_SEND",
  GENERATING_TEXT = "GENERATING_TEXT",
  SPEAKING = "SPEAKING",
  DONE = "DONE"
}

type SessionState = {
  state: PipelineState;
  assistantTextBuffer: string;
  ttsInFlight: boolean;
  ttsQueue: Promise<void>;
};

export class AudioPipeline {
  private readonly sessionState = new Map<string, SessionState>();

  constructor(
    private readonly db: DbPool,
    private readonly asr: AsrService,
    private readonly llm: LlmService,
    private readonly tts: TtsService,
    private readonly ttsFallback: "fail" | "silent" = "fail",
    private readonly ttsFallbackSampleRate: number = 24000
  ) {}

  async handleTurn(wavAudio: Buffer, sessionId?: string): Promise<TurnResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const state = this.getSessionState(resolvedSessionId);

    await this.ensureSession(resolvedSessionId);
    this.transition(state, PipelineState.LISTENING, "asr_start");

    const asr = await this.asr.transcribeWav(wavAudio);
    const transcriptText = asr.transcript.trim();

    this.transition(state, PipelineState.TRANSCRIBED, "asr_done");

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "user",
      transcriptText
    });

    this.transition(state, PipelineState.GENERATING_TEXT, "llm_start");
    const responseText = await this.generateAssistantText(resolvedSessionId, transcriptText);
    this.transition(state, PipelineState.SPEAKING, "llm_complete");

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    const tts = await this.synthesizeFinalText(resolvedSessionId, responseText);
    this.transition(state, PipelineState.DONE, "tts_complete");

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText,
      response_audio_pcm_b64: tts.audio_pcm_b64,
      response_audio_sample_rate: tts.sample_rate
    };
  }

  async handleTextTurn(text: string, sessionId?: string): Promise<TurnResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const transcriptText = text.trim();
    if (!transcriptText) {
      return {
        session_id: resolvedSessionId,
        transcript_text: "",
        response_text: "",
        response_audio_pcm_b64: "",
        response_audio_sample_rate: 24000
      };
    }

    const state = this.getSessionState(resolvedSessionId);
    this.transition(state, PipelineState.WAITING_FOR_SEND, "text_turn_received");

    await this.ensureSession(resolvedSessionId);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "user",
      transcriptText
    });

    this.transition(state, PipelineState.GENERATING_TEXT, "llm_start");
    const responseText = await this.generateAssistantText(resolvedSessionId, transcriptText);
    this.transition(state, PipelineState.SPEAKING, "llm_complete");

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    const tts = await this.synthesizeFinalText(resolvedSessionId, responseText);
    this.transition(state, PipelineState.DONE, "tts_complete");

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText,
      response_audio_pcm_b64: tts.audio_pcm_b64,
      response_audio_sample_rate: tts.sample_rate
    };
  }

  async handleTurnTextOnly(wavAudio: Buffer, sessionId?: string): Promise<{ session_id: string; transcript_text: string; response_text: string }> {
    const resolvedSessionId = sessionId ?? uuidv4();

    await this.ensureSession(resolvedSessionId);

    const asr = await this.asr.transcribeWav(wavAudio);
    const transcriptText = asr.transcript.trim();

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "user",
      transcriptText
    });

    const responseText = await this.llm.chat([
      {
        role: "system",
        content:
          "You are a helpful conversational voice assistant. You receive the user's voice via transcription, so do not claim you cannot hear them. Be concise, natural, and safe. If the user is ambiguous, ask one short clarifying question."
      },
      { role: "user", content: transcriptText }
    ]);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText
    };
  }

  async handleTextTurnTextOnly(text: string, sessionId?: string): Promise<{ session_id: string; response_text: string }> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const transcriptText = text.trim();
    if (!transcriptText) {
      return {
        session_id: resolvedSessionId,
        response_text: ""
      };
    }

    await this.ensureSession(resolvedSessionId);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "user",
      transcriptText
    });

    const responseText = await this.llm.chat([
      {
        role: "system",
        content:
          "You are a helpful conversational voice assistant. You receive the user's voice via transcription, so do not claim you cannot hear them. Be concise, natural, and safe. If the user is ambiguous, ask one short clarifying question."
      },
      { role: "user", content: transcriptText }
    ]);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    return {
      session_id: resolvedSessionId,
      response_text: responseText
    };
  }

  async transcribeOnly(wavAudio: Buffer, sessionId?: string): Promise<TranscribeResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const state = this.getSessionState(resolvedSessionId);
    this.transition(state, PipelineState.LISTENING, "asr_start");
    const asr = await this.asr.transcribeWav(wavAudio);
    const transcriptText = asr.transcript.trim();
    this.transition(state, PipelineState.TRANSCRIBED, "asr_done");

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText
    };
  }

  async streamAssistantAudio(
    text: string,
    onChunk: (chunk: Buffer) => Promise<void> | void
  ): Promise<void> {
    const cleaned = text.trim();
    if (!cleaned) return;

    const sentences = splitSentences(cleaned);
    for (const sentence of sentences) {
      const tts = await this.synthesizeWithFallback(sentence);
      const pcmBytes = Buffer.from(tts.audio_pcm_b64, "base64");
      for (const chunk of chunkPcmFrames(pcmBytes)) {
        await onChunk(chunk);
      }
    }
  }

  private getSessionState(sessionId: string): SessionState {
    const existing = this.sessionState.get(sessionId);
    if (existing) return existing;

    const created: SessionState = {
      state: PipelineState.IDLE,
      assistantTextBuffer: "",
      ttsInFlight: false,
      ttsQueue: Promise.resolve()
    };
    this.sessionState.set(sessionId, created);
    return created;
  }

  private transition(state: SessionState, next: PipelineState, reason: string) {
    state.state = next;
    console.log(`[PIPELINE] state=${next} reason=${reason}`);
  }

  private async generateAssistantText(sessionId: string, transcriptText: string): Promise<string> {
    const state = this.getSessionState(sessionId);
    state.assistantTextBuffer = "";

    const responseText = await this.llm.chat([
      {
        role: "system",
        content:
          "You are a helpful conversational voice assistant. You receive the user's voice via transcription, so do not claim you cannot hear them. Be concise, natural, and safe. If the user is ambiguous, ask one short clarifying question."
      },
      { role: "user", content: transcriptText }
    ]);

    this.onLlmToken(state, responseText);
    return this.onLlmComplete(state);
  }

  private onLlmToken(state: SessionState, token: string) {
    // Buffer LLM output for UI only. TTS is triggered ONLY in onLlmComplete.
    state.assistantTextBuffer += token;
  }

  private onLlmComplete(state: SessionState): string {
    const finalText = state.assistantTextBuffer.trim();
    if (!finalText) {
      throw new Error("LLM completed with empty text");
    }
    return finalText;
  }

  private async synthesizeFinalText(sessionId: string, text: string): Promise<TtsResult> {
    const state = this.getSessionState(sessionId);
    if (!text.trim()) {
      return { audio_pcm_b64: "", sample_rate: 24000, channels: 1 };
    }

    let result: TtsResult = { audio_pcm_b64: "", sample_rate: 24000, channels: 1 };

    // Serialize TTS per session to prevent overlap.
    state.ttsQueue = state.ttsQueue.then(async () => {
      if (state.ttsInFlight) {
        console.warn("[TTS] Duplicate synth prevented");
        return;
      }
      state.ttsInFlight = true;
      try {
        result = await this.synthesizeWithFallback(text);
      } finally {
        state.ttsInFlight = false;
      }
    });

    await state.ttsQueue;
    return result;
  }

  private async ensureSession(sessionId: string) {
    await this.db.query(
      "INSERT INTO conversation.sessions (id) VALUES ($1) ON CONFLICT (id) DO NOTHING",
      [sessionId]
    );
  }

  private async insertTranscript(input: {
    id: string;
    sessionId: string;
    role: "user" | "assistant";
    transcriptText: string;
  }) {
    await this.db.query(
      "INSERT INTO transcript_store.transcripts (id, session_id, transcript_text, role) VALUES ($1,$2,$3,$4)",
      [input.id, input.sessionId, input.transcriptText, input.role]
    );
  }

  private async synthesizeWithFallback(text: string): Promise<TtsResult> {
    try {
      console.log(`[TTS] Synthesizing ${text.length} characters of text`);
      const result = await this.tts.synthesizeToPcm(text);
      console.log(`[TTS] Synthesis successful: ${result.audio_pcm_b64.length} bytes of base64 audio`);
      return result;
    } catch (err) {
      console.error(`[TTS] Synthesis failed:`, err);
      if (this.ttsFallback !== "silent") throw err;
      const seconds = 1;
      const pcm = Buffer.alloc(this.ttsFallbackSampleRate * seconds * 2, 0);
      return {
        audio_pcm_b64: pcm.toString("base64"),
        sample_rate: this.ttsFallbackSampleRate,
        channels: 1
      };
    }
  }
}

const PCM_SAMPLE_RATE = 24000;
const PCM_FRAME_MS = 40;
const PCM_FRAME_BYTES = (PCM_SAMPLE_RATE * PCM_FRAME_MS * 2) / 1000;

function splitSentences(text: string): string[] {
  const parts = text.split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
  return parts.length > 0 ? parts : [text];
}

function chunkPcmFrames(pcm: Buffer): Buffer[] {
  if (!pcm.length) return [];
  const chunks: Buffer[] = [];
  for (let i = 0; i < pcm.length; i += PCM_FRAME_BYTES) {
    const end = Math.min(i + PCM_FRAME_BYTES, pcm.length);
    chunks.push(pcm.subarray(i, end));
  }
  return chunks;
}
