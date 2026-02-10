import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { z } from "zod";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables.
// - Always try process.cwd() first (standard behavior)
// - Then fall back to locating `.env` relative to this module (helps when launching from monorepo root)
dotenv.config();

const candidateEnvPaths = [
  path.resolve(__dirname, "../..", ".env"),
  path.resolve(__dirname, "../../..", ".env"),
  path.resolve(__dirname, "../../../..", ".env"),
];

for (const envPath of candidateEnvPaths) {
  try {
    if (fs.existsSync(envPath)) {
      dotenv.config({ path: envPath, override: false });
      break;
    }
  } catch {
    // ignore filesystem errors; env validation will surface missing vars
  }
}

const EnvSchema = z.object({
  PIPELINE_MODE: z.enum(["full", "stub"]).default("full"),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().int().positive().default(8089),
  LOG_LEVEL: z.string().default("info"),

  // Full mode only (stub mode can omit these)
  DATABASE_URL: z.string().optional().default(""),
  // Optional: direct DB connection string (recommended for migrations)
  DIRECT_URL: z.string().optional().default(""),
  ASR_WORKER_URL: z.string().optional().default(""),
  TTS_WORKER_URL: z.string().optional().default(""),

  // If TTS worker is unavailable (e.g., local Python env missing), optionally return silent WAV.
  TTS_FALLBACK: z.enum(["fail", "silent"]).default("fail"),

  LLM_PROVIDER: z.enum(["openai_compat", "tgi", "stub"]).default("openai_compat"),
  LLM_BASE_URL: z.string().optional().default(""),
  LLM_API_KEY: z.string().optional().default(""),
  LLM_MODEL: z.string().optional().default(""),
  LLM_TEMPERATURE: z.coerce.number().min(0).max(2).default(0.4),
  LLM_MAX_TOKENS: z.coerce.number().int().positive().default(2048),

  AUDIO_SAMPLE_RATE: z.coerce.number().int().positive().default(16000)
}).superRefine((env, ctx) => {
  if (env.PIPELINE_MODE !== "full") return;

  if (!env.DATABASE_URL) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["DATABASE_URL"], message: "Required in full mode" });
  }

  for (const key of ["ASR_WORKER_URL", "TTS_WORKER_URL"] as const) {
    const value = env[key];
    if (!value) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: [key], message: "Required in full mode" });
    } else {
      try {
        new URL(value);
      } catch {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: [key], message: "Must be a valid URL" });
      }
    }
  }

  if (env.LLM_PROVIDER !== "stub") {
    if (!env.LLM_BASE_URL) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["LLM_BASE_URL"], message: "Required in full mode" });
    } else {
      try {
        new URL(env.LLM_BASE_URL);
      } catch {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["LLM_BASE_URL"], message: "Must be a valid URL" });
      }
    }
  }

  if (env.LLM_PROVIDER !== "stub" && !env.LLM_MODEL) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["LLM_MODEL"], message: "Required in full mode" });
  }
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(): Env {
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const message = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`Invalid environment: ${message}`);
  }
  return parsed.data;
}
