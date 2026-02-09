import multipart from "@fastify/multipart";
import websocket from "@fastify/websocket";
import Fastify from "fastify";
import { registerAudioRoutes } from "./src/api/audio.controller.js";
import { registerAudioWebSocket } from "./src/api/ws.js";
import { loadEnv } from "./src/config/env.config.js";
import { createDbPool } from "./src/db/db.connection.js";
import { AudioPipeline } from "./src/pipeline/audio.pipeline.js";
import { StubAudioPipeline } from "./src/pipeline/stub.pipeline.js";
import { AsrService } from "./src/services/asr.service.js";
import { LlmService } from "./src/services/llm.service.js";
import { TtsService } from "./src/services/tts.service.js";

export async function buildApp() {
  const env = loadEnv();

  const isDev = env.NODE_ENV !== "production";
  const app = Fastify({
    logger: {
      level: env.LOG_LEVEL,
      transport: isDev
        ? {
            target: "pino-pretty",
            options: { colorize: true, translateTime: "SYS:standard" }
          }
        : undefined
    }
  });
  await app.register(multipart);
  await app.register(websocket);

  let db: ReturnType<typeof createDbPool> | null = null;

  const pipeline =
    env.PIPELINE_MODE === "stub"
      ? new StubAudioPipeline(env.AUDIO_SAMPLE_RATE)
      : (() => {
          db = createDbPool(env.DATABASE_URL);
          const asr = new AsrService(env.ASR_WORKER_URL);
          const tts = new TtsService(env.TTS_WORKER_URL);
          const llm = new LlmService(
            env.LLM_PROVIDER,
            env.LLM_BASE_URL,
            env.LLM_API_KEY,
            env.LLM_MODEL,
            env.LLM_TEMPERATURE,
            env.LLM_MAX_TOKENS
          );
          return new AudioPipeline(db, asr, llm, tts, env.TTS_FALLBACK, env.AUDIO_SAMPLE_RATE);
        })();

  if (db) {
    try {
      await db.query("select 1 as ok");
    } catch (err) {
      try {
        await db.end();
      } catch {
        // ignore
      }
      throw new Error(
        "Database connection failed. If you are using Supabase, set DATABASE_URL to the Supabase Postgres connection string and set DB_PASSWORD (or SUPABASE_DB_PASSWORD). Also ensure TLS (PGSSLMODE=require).",
        { cause: err }
      );
    }
  }

  await registerAudioRoutes(app, pipeline);
  await registerAudioWebSocket(app, pipeline, env.AUDIO_SAMPLE_RATE);

  app.get("/healthz", async () => ({ ok: true }));

  if (db) {
    app.addHook("onClose", async () => {
      if (db) await db.end();
    });
  }

  return { app, env };
}
