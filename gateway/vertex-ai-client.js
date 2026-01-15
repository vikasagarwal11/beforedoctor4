// Vertex AI Gemini Live API Client
// Production-grade: Uses OAuth2 bearer tokens (service account)
// Handles bidirectional audio streaming with Gemini

import { VertexAI } from '@google-cloud/vertexai';
import { GoogleAuth } from 'google-auth-library';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { config } from './config.js';
import { logger } from './logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Vertex AI Session Manager
 * Manages Gemini Live sessions with native audio support
 */
export class VertexAISession {
  constructor(sessionConfig) {
    this.sessionConfig = sessionConfig;
    this.vertexAI = null;
    this.session = null;
    this.seq = 0;
    this.eventHandlers = {
      transcript: [],
      audio: [],
      bargeIn: [],
      draftUpdate: [],
      narrativeUpdate: [],
      error: [],
    };
  }

  /**
   * Initialize Vertex AI client
   * Production-grade: Uses Application Default Credentials (ADC) for OAuth2 bearer tokens
   * In Cloud Run, the service account attached to the service is automatically used
   */
  async initialize() {
    try {
      let authMethod = 'application_default_credentials';
      let credentials = null;

      // Production: Use Application Default Credentials (ADC)
      // Cloud Run automatically uses the attached service account
      if (process.env.NODE_ENV === 'production' || !config.firebase.serviceAccountPath) {
        // ADC is used automatically - no credentials needed
        logger.info('vertex.initializing', {
          method: 'application_default_credentials',
          project: config.vertexAI.projectId,
          location: config.vertexAI.location,
        });
      } else {
        // Development: Use service account file if provided
        try {
          const serviceAccountPath = config.firebase.serviceAccountPath.startsWith('./')
            ? join(__dirname, config.firebase.serviceAccountPath.replace('./', ''))
            : config.firebase.serviceAccountPath;
          
          const serviceAccountJson = readFileSync(serviceAccountPath, 'utf8');
          credentials = JSON.parse(serviceAccountJson);
          authMethod = 'service_account_file';
          
          logger.info('vertex.initializing', {
            method: 'service_account_file',
            service_account: credentials.client_email,
            project: config.vertexAI.projectId,
            location: config.vertexAI.location,
          });
        } catch (e) {
          logger.warn('vertex.service_account_file_failed', {
            error: e.message,
            fallback: 'application_default_credentials',
          });
          // Fallback to ADC
        }
      }

      // Initialize Vertex AI with OAuth2 authentication
      this.vertexAI = new VertexAI({
        project: config.vertexAI.projectId,
        location: config.vertexAI.location,
        // Use service account credentials if available (dev only)
        // In production, ADC is used automatically
        ...(credentials && {
          googleAuthOptions: {
            credentials: credentials,
          }
        }),
      });

      // Get access token for logging (verifies auth works)
      const auth = new GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/cloud-platform'],
        ...(credentials && { credentials }),
      });
      
      const client = await auth.getClient();
      const projectId = await auth.getProjectId();
      
      logger.info('vertex.authenticated', {
        auth_method: authMethod,
        project_id: projectId,
      });

      // Create generative model instance
      this.generativeModel = this.vertexAI.getGenerativeModel({
        model: config.vertexAI.model,
        generationConfig: {
          temperature: 0.7,
          topP: 0.95,
          topK: 40,
        },
      });

      logger.info('vertex.initialized', {
        model: config.vertexAI.model,
        project: config.vertexAI.projectId,
        location: config.vertexAI.location,
      });
    } catch (error) {
      logger.error('vertex.initialization_failed', {
        error_code: error.code,
        error_message: error.message,
        project: config.vertexAI.projectId,
      });
      throw error;
    }
  }

  /**
   * Start a new chat session
   * NOTE: This is currently using the standard chat API
   * For true Vertex Live bidirectional WebSocket, this needs to be updated
   * when the Live API WebSocket endpoint is available
   */
  async startSession() {
    try {
      const systemInstruction = this.sessionConfig.system_instruction?.text || 
        'You are a helpful clinical intake specialist for adverse event reporting. ' +
        'Ask follow-up questions until you have all 4 minimum criteria: ' +
        '1) identifiable patient, 2) identifiable reporter, 3) suspect product, 4) adverse event.';
      
      // Initialize chat with system instruction
      // TODO: Replace with Vertex Live WebSocket when available
      this.chat = this.generativeModel.startChat({
        systemInstruction: systemInstruction,
        history: [],
      });

      logger.info('vertex.session_started', {
        has_system_instruction: !!systemInstruction,
        // No instruction content logged (may contain PHI)
      });
      
      return true;
    } catch (error) {
      logger.error('vertex.session_start_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      throw error;
    }
  }

  /**
   * Send audio chunk to Vertex AI
   * @param {Buffer} pcm16k - PCM audio bytes (16kHz, s16le, mono)
   * 
   * NOTE: This uses standard chat API with inline audio
   * For production Vertex Live, this should use bidirectional WebSocket
   */
  async sendAudio(pcm16k) {
    if (!this.chat) {
      throw new Error('Session not started');
    }

    try {
      // Convert PCM to base64 for API
      const audioBase64 = pcm16k.toString('base64');
      
      // Log audio chunk sent (no audio content)
      logger.vertexAI('audio_chunk_sent', {
        chunk_size_bytes: pcm16k.length,
        has_audio: true,
      });
      
      // Send audio to Gemini
      // TODO: Replace with Vertex Live WebSocket bidirectional streaming
      const result = await this.chat.sendMessageStream([
        {
          inlineData: {
            mimeType: 'audio/pcm;rate=16000',
            data: audioBase64,
          },
        },
      ]);

      let chunkCount = 0;
      // Handle streaming response
      for await (const chunk of result.stream) {
        chunkCount++;
        await this.handleResponseChunk(chunk);
      }
      
      logger.vertexAI('audio_response_received', {
        chunk_count: chunkCount,
      });
    } catch (error) {
      logger.error('vertex.audio_send_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
    }
  }

  /**
   * Handle response chunk from Vertex AI
   * Production-grade: Logs metadata only, no PHI
   */
  async handleResponseChunk(chunk) {
    try {
      const response = chunk.response;
      
      // Extract text (transcript) - emit to handlers, but don't log content
      if (response.text) {
        const isPartial = response.candidates?.[0]?.finishReason !== 'STOP';
        logger.vertexAI('transcript_received', {
          has_transcript: true,
          is_partial: isPartial,
          // No text content logged (PHI)
        });
        
        this.emit('transcript', {
          text: response.text,
          isPartial,
        });
      }

      // Extract audio output (24kHz PCM) - emit but don't log content
      if (response.audio) {
        const audioData = Buffer.from(response.audio, 'base64');
        logger.vertexAI('audio_received', {
          has_audio: true,
          audio_size_bytes: audioData.length,
        });
        this.emit('audio', audioData);
      }

      // Extract function calls (for draft updates)
      if (response.functionCalls) {
        for (const call of response.functionCalls) {
          logger.vertexAI('function_call_received', {
            function_name: call.name,
            // No args logged (may contain PHI)
          });
          
          if (call.name === 'update_ae_draft') {
            this.emit('draftUpdate', call.args);
          }
          if (call.name === 'update_narrative') {
            this.emit('narrativeUpdate', call.args);
          }
        }
      }

      // Detect barge-in (user interruption)
      if (response.interruptionDetected) {
        logger.vertexAI('barge_in_detected', {});
        this.emit('bargeIn');
      }
    } catch (error) {
      logger.error('vertex.response_chunk_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
    }
  }

  /**
   * Event emitter pattern
   */
  on(event, handler) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event].push(handler);
    }
  }

  off(event, handler) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event] = this.eventHandlers[event].filter(h => h !== handler);
    }
  }

  emit(event, data) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event].forEach(handler => {
        try {
          handler(data);
        } catch (error) {
          console.error(`Error in ${event} handler:`, error);
        }
      });
    }
  }

  /**
   * Close session
   */
  async close() {
    try {
      if (this.chat) {
        // Clean up resources
        this.chat = null;
      }
      logger.info('vertex.session_closed', {});
    } catch (error) {
      logger.error('vertex.session_close_failed', {
        error_code: error.code,
        error_message: error.message,
      });
    }
  }
}

export default VertexAISession;

