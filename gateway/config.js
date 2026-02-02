// Configuration loader
// Production-grade: Uses Supabase for authentication and storage
// Vertex AI uses Application Default Credentials (ADC) for authentication

import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Load .env for local development
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function resolveMaybeRelativePath(maybePath) {
  if (!maybePath) return undefined;
  return path.isAbsolute(maybePath) ? maybePath : path.resolve(__dirname, maybePath);
}

const resolvedGoogleApplicationCredentialsPath = resolveMaybeRelativePath(
  process.env.GOOGLE_APPLICATION_CREDENTIALS,
);

if (resolvedGoogleApplicationCredentialsPath) {
  try {
    if (fs.existsSync(resolvedGoogleApplicationCredentialsPath)) {
      process.env.GOOGLE_APPLICATION_CREDENTIALS = resolvedGoogleApplicationCredentialsPath;
    }
  } catch {
    // Ignore filesystem errors; clients will report missing ADC if needed.
  }
}

export const config = {
  vertexAI: {
    // No API key - uses service account OAuth2 bearer tokens
    projectId: process.env.VERTEX_AI_PROJECT_ID || 'gen-lang-client-0337309484',
    location: process.env.VERTEX_AI_LOCATION || 'us-central1',
    // Live model is optional and disabled by default
    model: process.env.VERTEX_AI_MODEL || 'gemini-1.5-pro-live',
    // REST agent model (used for STT -> AI -> TTS flow)
    agentModel: process.env.VERTEX_AI_AGENT_MODEL || 'gemini-2.0-flash',
    liveEnabled: process.env.VERTEX_AI_LIVE_ENABLED === 'true',
  },
  supabase: {
    url: process.env.SUPABASE_URL,
    anonKey: process.env.SUPABASE_ANON_KEY,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    storageBucket: process.env.SUPABASE_STORAGE_BUCKET || 'audio-files',
  },
  google: {
    applicationCredentialsPath: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  },
  server: {
    port: parseInt(process.env.PORT || '8080', 10),
    nodeEnv: process.env.NODE_ENV || 'development',
    allowedOrigins: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
    // Helpful to confirm which deployment the client is connected to.
    // Cloud Run: K_REVISION is automatically set.
    buildId:
      process.env.GATEWAY_BUILD_ID ||
      process.env.K_REVISION ||
      process.env.GITHUB_SHA ||
      process.env.COMMIT_SHA ||
      'local',
  },
  stt: {
    enabled: process.env.STT_FALLBACK_ENABLED !== 'false',
    disableOnVertex: process.env.STT_DISABLE_ON_VERTEX !== 'false',
  },
};

// Validate required config
if (!config.vertexAI.projectId) {
  console.error('ERROR: VERTEX_AI_PROJECT_ID is required');
  process.exit(1);
}

if (!config.supabase.url || !config.supabase.serviceRoleKey) {
  console.warn('WARNING: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY should be set for production');
}

export default config;
