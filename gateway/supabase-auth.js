// Supabase Authentication Module
// Production-grade: Validates Supabase JWT tokens from Flutter app
// Replaces Firebase Admin SDK with Supabase verification

import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';
import { logger } from './logger.js';

let supabaseAdmin = null;

/**
 * Initialize Supabase Admin Client
 * Uses service role key for server-side operations
 */
export async function initializeSupabase() {
  try {
    if (!config.supabase.url || !config.supabase.serviceRoleKey) {
      throw new Error('Supabase URL and SERVICE_ROLE_KEY are required');
    }

    supabaseAdmin = createClient(
      config.supabase.url,
      config.supabase.serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    logger.info('supabase.initialized', {
      url: config.supabase.url,
      environment: config.server.nodeEnv,
    });
  } catch (error) {
    logger.error('supabase.initialization_failed', {
      error: error.message,
      environment: process.env.NODE_ENV,
    });

    if (process.env.NODE_ENV === 'development') {
      logger.warn('supabase.continuing_without_auth', {
        note: 'Development mode - auth will be bypassed',
      });
      supabaseAdmin = null;
    } else {
      throw new Error(`Supabase initialization failed: ${error.message}`);
    }
  }
}

/**
 * Verify Supabase JWT token
 * Production-grade: Validates token, returns user info for audit logging
 * @param {string} accessToken - Supabase access token from client
 * @returns {Promise<{uid: string, email?: string, isAnonymous: boolean}>} Decoded token data
 */
export async function verifySupabaseToken(accessToken) {
  // Check for mock tokens in development
  const allowMockTokens = process.env.ALLOW_MOCK_TOKENS === 'true' 
    || process.env.NODE_ENV === 'development' 
    || config.server.nodeEnv === 'development';
  
  if (allowMockTokens) {
    const mockTokens = ['mock_token_for_testing', 'mock', 'test_token', 'dev_token'];
    if (mockTokens.includes(accessToken)) {
      logger.warn('supabase.token_verification_bypassed', {
        reason: 'mock_token_detected',
        token_prefix: accessToken.substring(0, 10),
        environment: config.server.nodeEnv,
        allow_mock_tokens: process.env.ALLOW_MOCK_TOKENS,
      });
      return { 
        uid: 'dev-user', 
        email: 'dev@example.com',
        isAnonymous: false,
      };
    }
  }

  if (!supabaseAdmin) {
    if (process.env.NODE_ENV === 'development' || config.server.nodeEnv === 'development') {
      logger.warn('supabase.token_verification_bypassed', {
        reason: 'supabase_not_initialized',
      });
      return { 
        uid: 'dev-user', 
        email: 'dev@example.com',
        isAnonymous: false,
      };
    }
    throw new Error('Supabase not initialized - authentication required');
  }

  try {
    // Verify JWT token using Supabase
    const { data: { user }, error } = await supabaseAdmin.auth.getUser(accessToken);

    if (error) {
      logger.error('supabase.token_verification_failed', {
        error: error.message,
      });
      throw new Error(`Invalid token: ${error.message}`);
    }

    if (!user) {
      throw new Error('No user found for token');
    }

    // Log successful authentication (no PHI)
    logger.info('supabase.token_verified', {
      user_id: user.id,
      has_email: !!user.email,
      is_anonymous: user.is_anonymous || false,
      created_at: user.created_at,
    });

    return {
      uid: user.id,
      email: user.email,
      isAnonymous: user.is_anonymous || false,
      createdAt: user.created_at,
    };
  } catch (error) {
    logger.error('supabase.token_verification_error', {
      error: error.message,
      token_prefix: accessToken ? accessToken.substring(0, 10) : 'none',
    });
    throw new Error(`Token verification failed: ${error.message}`);
  }
}

/**
 * Get Supabase admin client (for server-side operations)
 * @returns {SupabaseClient} Supabase admin client
 */
export function getSupabaseAdmin() {
  if (!supabaseAdmin) {
    throw new Error('Supabase not initialized');
  }
  return supabaseAdmin;
}

export default {
  initializeSupabase,
  verifySupabaseToken,
  getSupabaseAdmin,
};
