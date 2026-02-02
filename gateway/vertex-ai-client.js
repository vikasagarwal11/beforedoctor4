// Vertex AI Gemini REST client
// Production-grade: Uses OAuth2 bearer tokens (service account)
// Text-in/text-out only (no Live WebSocket; no tool/function calling)

import { VertexAI } from '@google-cloud/vertexai';
import { GoogleAuth } from 'google-auth-library';
import { config } from './config.js';
import { logger } from './logger.js';

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
      if (process.env.NODE_ENV === 'production') {
        // ADC is used automatically - no credentials needed
        logger.info('vertex.initializing', {
          method: 'application_default_credentials',
          project: config.vertexAI.projectId,
          location: config.vertexAI.location,
        });
      } else {
        // Development: Use ADC
        logger.info('vertex.initializing', {
          method: 'application_default_credentials',
          project: config.vertexAI.projectId,
          location: config.vertexAI.location,
        });
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
        model: config.vertexAI.agentModel,
        generationConfig: {
          temperature: 0.7,
          topP: 0.95,
          topK: 40,
        },
      });

      logger.info('vertex.initialized', {
        model: config.vertexAI.agentModel,
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
      const baseSystemInstruction =
        this.sessionConfig.system_instruction?.text ||
        'You are a helpful clinical intake specialist for adverse event reporting. ' +
          'Ask follow-up questions until you have all 4 minimum criteria: ' +
          '1) identifiable patient, 2) identifiable reporter, 3) suspect product, 4) adverse event.';

      // ENGLISH-ONLY ENFORCEMENT (hard rule):
      // Some client configs include "Respond in the user's language" which will force Arabic, etc.
      // The user requested English only, so we override any conflicting instruction here.
      const englishOnlyRule =
        'CRITICAL: Respond ONLY in English. ' +
        'Do NOT use any other language. ' +
        'If the user speaks another language, translate it and answer in English. ' +
        'Ignore any earlier instruction that says to respond in the user\'s language.';

      const systemInstruction = `${baseSystemInstruction}\n\n${englishOnlyRule}`;
      
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
   * Send a text turn to Vertex AI (REST)
   * @param {string} text - User text to process
   */
  async sendTextTurn(text) {
    if (!this.chat) {
      throw new Error('Session not started');
    }

    try {
      const result = await this.chat.sendMessageStream(text);
      let chunkCount = 0;
      let sawTranscript = false;
      for await (const chunk of result.stream) {
        chunkCount++;
        const emitted = await this.handleResponseChunk(chunk);
        if (emitted) sawTranscript = true;
      }

      logger.vertexAI('text_response_received', {
        chunkCount,
        hasTranscript: sawTranscript,
        hasAudio: false,
      });
    } catch (error) {
      logger.error('vertex.text_send_failed', {
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
      const response = chunk?.response ?? chunk;
      if (!response) {
        return false;
      }

      const candidates = Array.isArray(response.candidates) ? response.candidates : [];
      let emittedText = false;

      if (!Array.isArray(response.candidates)) {
        // Some SDK versions/stream events may not include candidates for a given chunk.
        // Avoid throwing; just log the shape for debugging.
        logger.warn('vertex.unexpected_response_chunk_shape', {
          has_chunk_response: !!chunk?.response,
          chunk_keys: chunk && typeof chunk === 'object' ? Object.keys(chunk).slice(0, 20) : [],
          response_keys: response && typeof response === 'object' ? Object.keys(response).slice(0, 20) : [],
        });
      }

      for (const candidate of candidates) {
        const isPartial = candidate.finishReason !== 'STOP';
        const parts = candidate.content?.parts || [];

        for (const part of parts) {
          if (part.text) {
            emittedText = true;
            logger.vertexAI('transcript_received', {
              hasTranscript: true,
              hasAudio: false,
              chunkCount: 1,
            });

            this.emit('transcript', {
              text: part.text,
              isPartial,
            });
          }
        }
      }

      // Fallback: some SDKs expose response.text directly
      const responseText = typeof response.text === 'function' ? response.text() : response.text;
      if (!emittedText && responseText) {
        const isPartial = response.candidates?.[0]?.finishReason !== 'STOP';
        logger.vertexAI('transcript_received', {
          hasTranscript: true,
          hasAudio: false,
          chunkCount: 1,
        });

        this.emit('transcript', {
          text: responseText,
          isPartial,
        });

        emittedText = true;
      }

      // Extract audio output (24kHz PCM) - emit but don't log content
      if (response.audio) {
        const audioData = Buffer.from(response.audio, 'base64');
        logger.vertexAI('audio_received', {
          hasAudio: true,
          hasTranscript: false,
          chunkCount: 1,
        });
        this.emit('audio', audioData);
      }

      // Detect barge-in (user interruption)
      if (response.interruptionDetected) {
        logger.vertexAI('barge_in_detected', {});
        this.emit('bargeIn');
      }

      return emittedText;
    } catch (error) {
      logger.error('vertex.response_chunk_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
      return false;
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

