import { v4 as uuidv4 } from "uuid";
import type { DbPool } from "../db/db.connection.js";
import { AsrService } from "../services/asr.service.js";
import { LlmService } from "../services/llm.service.js";
import { TtsService } from "../services/tts.service.js";
import { pcm16ToWavBuffer } from "../utils/audio.utils.js";

export type TurnResult = {
  session_id: string;
  transcript_text: string;
  response_text: string;
  response_audio_wav_b64: string;
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
};

export class AudioPipeline {
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
          "You are a helpful conversational voice assistant. Be concise, natural, and safe. If the user is ambiguous, ask one short clarifying question."
      },
      { role: "user", content: transcriptText }
    ]);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    const tts = await this.synthesizeWithFallback(responseText);

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText,
      response_audio_wav_b64: tts.audio_wav_b64,
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
        response_audio_wav_b64: "",
        response_audio_sample_rate: 24000
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
          "You are a helpful conversational voice assistant. Be concise, natural, and safe. If the user is ambiguous, ask one short clarifying question."
      },
      { role: "user", content: transcriptText }
    ]);

    await this.insertTranscript({
      id: uuidv4(),
      sessionId: resolvedSessionId,
      role: "assistant",
      transcriptText: responseText
    });

    const tts = await this.synthesizeWithFallback(responseText);

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText,
      response_text: responseText,
      response_audio_wav_b64: tts.audio_wav_b64,
      response_audio_sample_rate: tts.sample_rate
    };
  }

  async transcribeOnly(wavAudio: Buffer, sessionId?: string): Promise<TranscribeResult> {
    const resolvedSessionId = sessionId ?? uuidv4();
    const asr = await this.asr.transcribeWav(wavAudio);
    const transcriptText = asr.transcript.trim();

    return {
      session_id: resolvedSessionId,
      transcript_text: transcriptText
    };
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

  private async synthesizeWithFallback(text: string): Promise<{ audio_wav_b64: string; sample_rate: number }> {
    try {
      console.log(`[TTS] Synthesizing ${text.length} characters of text`);
      const result = await this.tts.synthesizeToWav(text);
      console.log(`[TTS] Synthesis successful: ${result.audio_wav_b64.length} bytes of base64 audio`);
      return result;
    } catch (err) {
      console.error(`[TTS] Synthesis failed:`, err);
      if (this.ttsFallback !== "silent") throw err;
      const seconds = 1;
      const pcm = Buffer.alloc(this.ttsFallbackSampleRate * seconds * 2, 0);
      const wav = pcm16ToWavBuffer(pcm, this.ttsFallbackSampleRate, 1);
      return {
        audio_wav_b64: wav.toString("base64"),
        sample_rate: this.ttsFallbackSampleRate
      };
    }
  }
}
