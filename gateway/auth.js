// Firebase Authentication Module
// Production-grade: Validates Firebase ID tokens from Flutter app
// Uses Application Default Credentials (ADC) in Cloud Run

import admin from 'firebase-admin';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { config } from './config.js';
import { logger } from './logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

let firebaseApp = null;

/**
 * Initialize Firebase Admin SDK
 * Production: Uses Application Default Credentials (ADC) in Cloud Run
 * Development: Uses service account file if provided
 */
export async function initializeFirebase() {
  try {
    // In Cloud Run, use Application Default Credentials (ADC)
    // The service account attached to Cloud Run is automatically used
    if (process.env.NODE_ENV === 'production' || !config.firebase.serviceAccountPath) {
      // Production: Use ADC (no file needed)
      firebaseApp = admin.initializeApp({
        projectId: config.firebase.projectId,
        // ADC is used automatically in Cloud Run
      });
      logger.info('firebase.initialized', {
        method: 'application_default_credentials',
        environment: 'production',
      });
    } else {
      // Development: Use service account file if provided
      try {
        const serviceAccountPath = config.firebase.serviceAccountPath.startsWith('./')
          ? join(__dirname, config.firebase.serviceAccountPath.replace('./', ''))
          : config.firebase.serviceAccountPath;
        
        const serviceAccountJson = readFileSync(serviceAccountPath, 'utf8');
        const serviceAccount = JSON.parse(serviceAccountJson);
        
        firebaseApp = admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: config.firebase.projectId,
        });
        logger.info('firebase.initialized', {
          method: 'service_account_file',
          environment: 'development',
        });
      } catch (fileError) {
        logger.warn('firebase.service_account_file_failed', {
          error: fileError.message,
        });
        // Fallback to ADC even in development
        firebaseApp = admin.initializeApp({
          projectId: config.firebase.projectId,
        });
        logger.info('firebase.initialized', {
          method: 'application_default_credentials',
          environment: 'development_fallback',
        });
      }
    }
  } catch (error) {
    logger.error('firebase.initialization_failed', {
      error: error.message,
      environment: process.env.NODE_ENV,
    });
    
    // In development, allow continuing without Firebase (for testing)
    if (process.env.NODE_ENV === 'development') {
      logger.warn('firebase.continuing_without_auth', {
        note: 'Development mode - auth will be bypassed',
      });
      firebaseApp = null;
    } else {
      // In production, Firebase is required
      throw new Error(`Firebase initialization failed: ${error.message}`);
    }
  }
}

/**
 * Verify Firebase ID token
 * Production-grade: Validates token, returns user info for audit logging
 * @param {string} idToken - Firebase ID token from client
 * @returns {Promise<{uid: string, email?: string, sessionId?: string}>} Decoded token data
 */
export async function verifyFirebaseToken(idToken) {
  // Development mode: Check for mock tokens and bypass verification
  if (process.env.NODE_ENV === 'development' || config.server.nodeEnv === 'development') {
    // Common mock token patterns used in local testing
    const mockTokens = ['mock_token_for_testing', 'mock', 'test_token', 'dev_token'];
    if (mockTokens.includes(idToken)) {
      logger.warn('firebase.token_verification_bypassed', {
        reason: 'mock_token_detected',
        token_prefix: idToken.substring(0, 10),
      });
      return { 
        uid: 'dev-user', 
        email: 'dev@example.com',
        sessionId: 'dev-session',
      };
    }
  }

  if (!firebaseApp) {
    // Development mode: simplified check (for local testing)
    if (process.env.NODE_ENV === 'development' || config.server.nodeEnv === 'development') {
      logger.warn('firebase.token_verification_bypassed', {
        reason: 'firebase_not_initialized',
      });
      return { 
        uid: 'dev-user', 
        email: 'dev@example.com',
        sessionId: 'dev-session',
      };
    }
    throw new Error('Firebase not initialized - authentication required');
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    
    // Log successful authentication (no PHI)
    logger.info('firebase.token_verified', {
      user_id: decodedToken.uid,
      has_email: !!decodedToken.email,
      auth_time: decodedToken.auth_time,
    });

    return {
      uid: decodedToken.uid,
      email: decodedToken.email,
      name: decodedToken.name,
      sessionId: decodedToken.session_id,
      authTime: decodedToken.auth_time,
    };
  } catch (error) {
    logger.error('firebase.token_verification_failed', {
      error_code: error.code,
      error_message: error.message,
      // No token content logged (security)
    });
    throw new Error('Invalid Firebase token');
  }
}

export default { initializeFirebase, verifyFirebaseToken };

