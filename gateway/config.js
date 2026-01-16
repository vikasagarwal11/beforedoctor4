// Configuration loader
// Production-grade: Uses Application Default Credentials (ADC) for Vertex AI
// No API keys - uses service account OAuth2 bearer tokens

import dotenv from 'dotenv';

// Load .env for local development
dotenv.config();

export const config = {
  vertexAI: {
    // No API key - uses service account OAuth2 bearer tokens
    projectId: process.env.VERTEX_AI_PROJECT_ID || 'gen-lang-client-0337309484',
    location: process.env.VERTEX_AI_LOCATION || 'us-central1',
    model: process.env.VERTEX_AI_MODEL || 'gemini-2.5-flash-native-audio',
  },
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID,
    // Local dev: path to service account JSON
    // Cloud Run: uses Application Default Credentials (ADC) automatically
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
  },
  server: {
    port: parseInt(process.env.PORT || '8080', 10),
    nodeEnv: process.env.NODE_ENV || 'development',
    allowedOrigins: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
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
