import type { FastifyInstance } from "fastify";
import type { AudioPipelineLike } from "../pipeline/audio.pipeline.js";
import { extractPcmFromWav } from "../utils/audio.utils.js";
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
    
    // Convert WAV to PCM for Flutter playback
    let audioPcmB64 = "";
    if (result.response_audio_wav_b64) {
      try {
        const wavBuffer = Buffer.from(result.response_audio_wav_b64, "base64");
        const pcmBuffer = extractPcmFromWav(wavBuffer);
        audioPcmB64 = pcmBuffer.toString("base64");
      } catch (err) {
        app.log.warn({ error: String(err) }, "Failed to extract PCM from WAV, returning empty audio");
      }
    }
    
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
    
    // Convert WAV to PCM for Flutter playback
    let audioPcmB64 = "";
    if (result.response_audio_wav_b64) {
      try {
        const wavBuffer = Buffer.from(result.response_audio_wav_b64, "base64");
        console.log(`[AUDIO_CONTROLLER] WAV buffer size: ${wavBuffer.length}`);
        console.log(`[AUDIO_CONTROLLER] WAV header (first 12 bytes): ${wavBuffer.toString('hex', 0, 12)}`);
        const pcmBuffer = extractPcmFromWav(wavBuffer);
        console.log(`[AUDIO_CONTROLLER] Extracted PCM size: ${pcmBuffer.length}`);
        console.log(`[AUDIO_CONTROLLER] PCM data (first 20 bytes): ${pcmBuffer.toString('hex', 0, 20)}`);
        audioPcmB64 = pcmBuffer.toString("base64");
      } catch (err) {
        console.error(`[AUDIO_CONTROLLER] WAV extraction failed: ${err}`);
        app.log.warn({ error: String(err) }, "Failed to extract PCM from WAV, returning empty audio");
      }
    }
    
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
