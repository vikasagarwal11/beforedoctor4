import type { FastifyInstance } from "fastify";
import type { AudioPipelineLike } from "../pipeline/audio.pipeline.js";
import { badRequest } from "../utils/errors.js";

export async function registerAudioRoutes(app: FastifyInstance, pipeline: AudioPipelineLike) {
  app.post("/v1/audio/turn", async (req, reply) => {
    const mp = await req.file();
    if (!mp) throw badRequest("Missing multipart file field 'audio'");

    const sessionId = (req.query as any)?.session_id as string | undefined;
    const bytes = await mp.toBuffer();
    app.log.info({
      audioByteSize: bytes.length,
      sessionId
    }, "Audio turn request received");

    const result = await pipeline.handleTurn(bytes, sessionId);
    
    // PCM is already returned by the TTS worker
    const audioPcmB64 = result.response_audio_pcm_b64 || "";
    
    app.log.info({
      transcriptTextLength: result.transcript_text.length,
      responseTextLength: result.response_text.length,
      responseTextPreview: result.response_text.substring(0, 100),
      hasAudio: audioPcmB64.length > 0,
      audioBytesB64: audioPcmB64.length
    }, "Audio turn response completed");
    
    return reply.send({
      transcript_text: result.transcript_text,
      response_text: result.response_text,
      response_audio_pcm_b64: audioPcmB64
    });
  });

  app.post("/v1/asr/turn", async (req, reply) => {
    const mp = await req.file();
    if (!mp) throw badRequest("Missing multipart file field 'audio'");

    const sessionId = (req.query as any)?.session_id as string | undefined;
    const bytes = await mp.toBuffer();

    const result = await pipeline.transcribeOnly(bytes, sessionId);
    app.log.info({
      transcriptText: result.transcript_text
    }, "ASR-only response");
    return reply.send(result);
  });

  app.post("/v1/text/turn", async (req, reply) => {
    const body = (req.body ?? {}) as { text?: unknown };
    const text = typeof body.text === "string" ? body.text : "";
    if (!text.trim()) throw badRequest("Missing JSON field 'text'");

    const sessionId = (req.query as any)?.session_id as string | undefined;
    app.log.info({
      textLength: text.length,
      textPreview: text.substring(0, 100),
      sessionId
    }, "Text turn request received");
    
    const result = await pipeline.handleTextTurn(text, sessionId);
    
    // PCM is already returned by the TTS worker
    const audioPcmB64 = result.response_audio_pcm_b64 || "";
    
    app.log.info({
      responseTextLength: result.response_text.length,
      hasAudio: audioPcmB64.length > 0,
      audioBytesB64: audioPcmB64.length
    }, "Text turn response completed");
    
    return reply.send({
      response_text: result.response_text,
      response_audio_pcm_b64: audioPcmB64
    });
  });
}
