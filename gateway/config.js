// Configuration loader
// Production-grade: Uses Application Default Credentials (ADC) for Vertex AI
// No API keys - uses service account OAuth2 bearer tokens

import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Load .env for local development
dotenv.config();

// In local development, many Google SDK clients (e.g. Speech-to-Text) require
// Application Default Credentials via GOOGLE_APPLICATION_CREDENTIALS.
// We already rely on a service account JSON for Firebase Admin; reuse it as ADC
// unless the user explicitly sets GOOGLE_APPLICATION_CREDENTIALS.
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function resolveMaybeRelativePath(maybePath) {
  if (!maybePath) return undefined;
  return path.isAbsolute(maybePath) ? maybePath : path.resolve(__dirname, maybePath);
}

const resolvedFirebaseServiceAccountPath = resolveMaybeRelativePath(
  process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
);

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

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && resolvedFirebaseServiceAccountPath) {
  try {
    if (fs.existsSync(resolvedFirebaseServiceAccountPath)) {
      process.env.GOOGLE_APPLICATION_CREDENTIALS = resolvedFirebaseServiceAccountPath;
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
    model: process.env.VERTEX_AI_MODEL || 'gemini-live-2.5-flash-native-audio',
  },
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID,
    // Local dev: path to service account JSON
    // Cloud Run: uses Application Default Credentials (ADC) automatically
    serviceAccountPath: resolvedFirebaseServiceAccountPath,
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

export default config;
