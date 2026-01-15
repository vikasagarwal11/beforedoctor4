// Secret Manager Configuration (for Cloud Run)
// Falls back to environment variables for local development

import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

let secretClient = null;

/**
 * Initialize Secret Manager client (Cloud Run only)
 */
export function initializeSecretManager() {
  if (process.env.NODE_ENV === 'production' && process.env.GOOGLE_CLOUD_PROJECT) {
    try {
      secretClient = new SecretManagerServiceClient();
      console.log('✅ Secret Manager client initialized');
    } catch (error) {
      console.warn('⚠️  Secret Manager initialization failed:', error.message);
    }
  }
}

/**
 * Get secret from Secret Manager or environment
 */
export async function getSecret(secretName, defaultValue = null) {
  // In production (Cloud Run), try Secret Manager first
  if (secretClient && process.env.NODE_ENV === 'production') {
    try {
      const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.VERTEX_AI_PROJECT_ID;
      const name = `projects/${projectId}/secrets/${secretName}/versions/latest`;
      const [version] = await secretClient.accessSecretVersion({ name });
      return version.payload.data.toString();
    } catch (error) {
      console.warn(`⚠️  Could not fetch secret ${secretName} from Secret Manager:`, error.message);
      // Fall through to environment variable
    }
  }

  // Fallback to environment variable
  const envKey = secretName.toUpperCase().replace(/-/g, '_');
  return process.env[envKey] || defaultValue;
}

export default { initializeSecretManager, getSecret };


