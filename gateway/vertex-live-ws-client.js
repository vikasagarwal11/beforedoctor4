// Vertex AI Live WebSocket Client
// Production-grade: True bidirectional WebSocket connection to Vertex Live API
// Replaces the placeholder chat-based implementation

import WebSocket from 'ws';
import { GoogleAuth } from 'google-auth-library';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { config } from './config.js';
import { logger } from './logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Vertex Live WebSocket Session Manager
 * Implements the true bidirectional WebSocket connection to Vertex AI Live API
 */
export class VertexLiveWSSession {
  constructor(sessionConfig) {
    this.sessionConfig = sessionConfig;
    this.ws = null;
    this.auth = null;
    this.accessToken = null;
    this.isConnected = false;
    this.isSetup = false;
    this.eventHandlers = {
      transcript: [],
      userTranscript: [],
      audio: [],
      bargeIn: [],
      draftUpdate: [],
      narrativeUpdate: [],
      error: [],
    };
  }

  /**
   * Initialize authentication
   * Uses Application Default Credentials (ADC) for OAuth2 bearer tokens
   */
  async initialize() {
    try {
      let authMethod = 'application_default_credentials';
      let credentials = null;

      // Production: Use Application Default Credentials (ADC)
      if (process.env.NODE_ENV === 'production' || !config.firebase.serviceAccountPath) {
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
        }
      }

      // Initialize Google Auth for OAuth2 token
      this.auth = new GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/cloud-platform'],
        ...(credentials && { credentials }),
      });

      // Get access token
      const client = await this.auth.getClient();
      const tokenResponse = await client.getAccessToken();
      this.accessToken = tokenResponse.token;

      if (!this.accessToken) {
        throw new Error('Failed to obtain OAuth2 access token');
      }

      logger.info('vertex.authenticated', {
        auth_method: authMethod,
        project_id: config.vertexAI.projectId,
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
   * Start Vertex Live WebSocket session
   * Connects to Vertex Live API and sends setup message
   */
  async startSession() {
    try {
      if (!this.accessToken) {
        throw new Error('Not initialized - call initialize() first');
      }

      // Build WebSocket URL
      const location = config.vertexAI.location;
      const wsUrl = `wss://${location}-aiplatform.googleapis.com/ws/google.cloud.aiplatform.v1beta1.LlmBidiService/BidiGenerateContent`;

      logger.info('vertex.connecting', {
        url: wsUrl.replace(this.accessToken, '[REDACTED]'),
        location: location,
      });

      // Connect to Vertex Live WebSocket
      this.ws = new WebSocket(wsUrl, {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json',
        },
      });

      // Handle connection open
      this.ws.on('open', () => {
        logger.info('vertex.websocket_connected', {});
        this.isConnected = true;
        this._sendSetupMessage();
      });

      // Handle incoming messages
      this.ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          this._handleVertexMessage(message);
        } catch (error) {
          logger.error('vertex.message_parse_failed', {
            error_message: error.message,
          });
          this.emit('error', error);
        }
      });

      // Handle connection close
      this.ws.on('close', (code, reason) => {
        logger.info('vertex.websocket_closed', {
          code: code,
          reason: reason?.toString(),
        });
        this.isConnected = false;
        this.isSetup = false;
      });

      // Handle errors
      this.ws.on('error', (error) => {
        logger.error('vertex.websocket_error', {
          error_code: error.code,
          error_message: error.message,
        });
        this.isConnected = false;
        this.emit('error', error);
      });

      // Wait for connection to be established
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('WebSocket connection timeout'));
        }, 10000);

        this.ws.once('open', () => {
          clearTimeout(timeout);
          resolve();
        });

        this.ws.once('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });

      // Wait for setup to complete
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Setup message timeout'));
        }, 5000);

        const checkSetup = setInterval(() => {
          if (this.isSetup) {
            clearTimeout(timeout);
            clearInterval(checkSetup);
            resolve();
          }
        }, 100);

        this.ws.once('error', (error) => {
          clearTimeout(timeout);
          clearInterval(checkSetup);
          reject(error);
        });
      });

      logger.info('vertex.session_started', {
        has_system_instruction: !!this.sessionConfig.system_instruction,
      });

    } catch (error) {
      logger.error('vertex.session_start_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      throw error;
    }
  }

  /**
   * Send setup message (first message after connection)
   * This defines the "Brain" of the agent
   */
  _sendSetupMessage() {
    try {
      // Get language code and determine output language
      const languageCode = this.sessionConfig.language_code || 'en-US';
      const outputLanguage = languageCode.startsWith('en') ? 'ENGLISH' : 
                            languageCode.startsWith('es') ? 'SPANISH' :
                            languageCode.startsWith('fr') ? 'FRENCH' :
                            languageCode.startsWith('de') ? 'GERMAN' :
                            languageCode.startsWith('hi') ? 'HINDI' :
                            'ENGLISH'; // Default to English

      const systemInstruction = this.sessionConfig.system_instruction?.text || 
        '**Persona:**\n' +
        'You are a professional PV (Pharmacovigilance) Intake Specialist for adverse event reporting. ' +
        'You are empathetic, thorough, and professional.\n\n' +
        '**Conversational Rules:**\n' +
        '1. **Intake:** Ask follow-up questions until you have all 4 minimum criteria: ' +
        '1) identifiable patient (age OR gender OR initials), ' +
        '2) identifiable reporter (role OR contact OR authenticated user), ' +
        '3) suspect product (name), ' +
        '4) adverse event (symptom(s) or narrative).\n' +
        '2. **Data Collection:** Use the update_ae_draft tool to update the adverse event report as you gather information. ' +
        'Invoke this tool after each relevant piece of information is provided by the user.\n' +
        '3. **Conversational Flow:** You may engage in follow-up questions and clarifications as long as the user wants to provide information.\n\n' +
        '**Language Requirement:**\n' +
        `RESPOND IN ${outputLanguage}. YOU MUST RESPOND UNMISTAKABLY IN ${outputLanguage}.\n\n` +
        '**Guardrails:**\n' +
        'If the user reports severe symptoms or emergency situations, acknowledge their concern and ensure they understand when to seek immediate medical care.';

      const setupMessage = {
        setup: {
          model: `projects/${config.vertexAI.projectId}/locations/${config.vertexAI.location}/publishers/google/models/gemini-2.5-flash-native-audio`,
          generation_config: {
            // Note: language_code is not a valid field in generation_config for Vertex AI Live API
            // Language is handled via system_instruction instead
            // Request both AUDIO and TEXT so model emits text captions for UI and guardrails
            // TEXT is required for captions, guardrails, and transcript-driven features
            response_modalities: ['AUDIO', 'TEXT'],
            speech_config: {
              voice_config: {
                prebuilt_voice_config: {
                  voice_name: 'Puck', // Professional, empathetic voice
                },
              },
            },
            temperature: 0.7,
            top_p: 0.95,
            top_k: 40,
            // Context window compression for long sessions (native audio accumulates ~25 tokens/sec)
            context_window_compression_config: {
              compression_ratio: 0.5, // Compress to 50% to prevent token overflow in long sessions
            },
          },
          system_instruction: {
            parts: [
              {
                text: systemInstruction,
              },
            ],
          },
          tools: [
            {
              function_declarations: [
                {
                  name: 'update_ae_draft',
                  description: 'Update the adverse event report draft with extracted information',
                  parameters: {
                    type: 'OBJECT',
                    properties: {
                      patient_info: {
                        type: 'OBJECT',
                        properties: {
                          initials: { type: 'STRING' },
                          age: { type: 'INTEGER' },
                          gender: { type: 'STRING' },
                        },
                      },
                      product_details: {
                        type: 'OBJECT',
                        properties: {
                          product_name: { type: 'STRING' },
                          dosage_strength: { type: 'STRING' },
                          frequency: { type: 'STRING' },
                          indication: { type: 'STRING' },
                          lot_number: { type: 'STRING' },
                        },
                      },
                      event_details: {
                        type: 'OBJECT',
                        properties: {
                          symptoms: {
                            type: 'ARRAY',
                            items: { type: 'STRING' },
                          },
                          onset_date: { type: 'STRING' },
                          duration: { type: 'STRING' },
                          outcome: { type: 'STRING' },
                          narrative: { type: 'STRING' },
                        },
                      },
                      seriousness: { type: 'STRING' },
                    },
                  },
                },
                {
                  name: 'update_narrative',
                  description: 'Update the narrative summary of the adverse event',
                  parameters: {
                    type: 'OBJECT',
                    properties: {
                      narrative: { type: 'STRING' },
                    },
                  },
                },
              ],
            },
          ],
        },
      };

      this.ws.send(JSON.stringify(setupMessage));
      logger.info('vertex.setup_sent', {
        model: setupMessage.setup.model,
        language_code: languageCode,
        has_tools: setupMessage.setup.tools.length > 0,
        has_compression: !!setupMessage.setup.generation_config.context_window_compression_config,
      });

    } catch (error) {
      logger.error('vertex.setup_send_failed', {
        error_message: error.message,
      });
      this.emit('error', error);
    }
  }

  /**
   * Handle messages from Vertex Live API
   */
  _handleVertexMessage(message) {
    try {
      // Handle setup response
      if (message.setupComplete) {
        logger.info('vertex.setup_complete', {});
        this.isSetup = true;
        return;
      }

      // Handle server content (model responses)
      if (message.serverContent) {
        // Check for interruption (barge-in)
        if (message.serverContent.interrupted === true) {
          logger.vertexAI('barge_in_detected', {});
          this.emit('bargeIn');
        }

        // Handle user input transcription (ASR)
        const inputTranscript =
          message.serverContent.inputTranscription ||
          message.serverContent.userTranscript ||
          message.serverContent.userTranscription;
        if (inputTranscript && inputTranscript.text) {
          const isFinal = inputTranscript.isFinal ?? inputTranscript.final ?? inputTranscript.is_final;
          const isPartial = isFinal === undefined ? true : !isFinal;
          logger.vertexAI('user_transcript_received', {
            has_transcript: true,
            is_partial: isPartial,
          });
          this.emit('userTranscript', {
            text: inputTranscript.text,
            isPartial: isPartial,
          });
        }

        // Handle model turn (audio + text output)
        if (message.serverContent.modelTurn) {
          const parts = message.serverContent.modelTurn.parts || [];

          for (const part of parts) {
            // Handle audio output (24kHz PCM)
            if (part.inlineData && part.inlineData.mimeType?.includes('audio')) {
              const audioData = Buffer.from(part.inlineData.data, 'base64');
              logger.vertexAI('audio_received', {
                has_audio: true,
                audio_size_bytes: audioData.length,
              });
              this.emit('audio', audioData);
            }

            // Handle text (transcript)
            if (part.text) {
              const isPartial = !message.serverContent.modelTurn.complete;
              logger.vertexAI('transcript_received', {
                has_transcript: true,
                is_partial: isPartial,
              });
              this.emit('transcript', {
                text: part.text,
                isPartial: isPartial,
              });
            }

            // Handle function calls (tool calls for draft updates)
            if (part.functionCall) {
              const functionCallId = part.functionCall.id || null;
              logger.vertexAI('function_call_received', {
                function_name: part.functionCall.name,
                has_call_id: !!functionCallId,
              });

              if (part.functionCall.name === 'update_ae_draft') {
                const args = part.functionCall.args || {};
                this.emit('draftUpdate', args);
                this.sendFunctionResponse(part.functionCall.name, { status: 'ok' }, functionCallId);
              }

              if (part.functionCall.name === 'update_narrative') {
                const args = part.functionCall.args || {};
                if (args.narrative) {
                  this.emit('narrativeUpdate', { text: args.narrative });
                  this.sendFunctionResponse(part.functionCall.name, { status: 'ok' }, functionCallId);
                }
              }
            }
          }
        }
      }

      // Handle errors
      if (message.error) {
        logger.error('vertex.api_error', {
          error_code: message.error.code,
          error_message: message.error.message,
        });
        this.emit('error', new Error(message.error.message));
      }

    } catch (error) {
      logger.error('vertex.message_handle_failed', {
        error_message: error.message,
      });
      this.emit('error', error);
    }
  }

  /**
   * Send audio chunk to Vertex Live API
   * @param {Buffer} pcm16k - PCM audio bytes (16kHz, s16le, mono)
   */
  async sendAudio(pcm16k) {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      throw new Error('Session not ready - WebSocket not connected or setup not complete');
    }

    try {
      // Convert PCM to base64
      const audioBase64 = pcm16k.toString('base64');

      // Log audio chunk sent (no audio content)
      logger.vertexAI('audio_chunk_sent', {
        chunk_size_bytes: pcm16k.length,
        has_audio: true,
      });

      // Send audio input message
      const inputMessage = {
        clientContent: {
          turns: [
            {
              role: 'user',
              parts: [
                {
                  inlineData: {
                    data: audioBase64,
                    mimeType: 'audio/pcm;rate=16000',
                  },
                },
              ],
            },
          ],
          turnComplete: false,
        },
      };

      this.ws.send(JSON.stringify(inputMessage));

    } catch (error) {
      logger.error('vertex.audio_send_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
    }
  }

  /**
   * Send function response (tool call acknowledgement)
   * @param {string} name - Function name that was called
   * @param {object} response - Function response/result data
   * @param {string} functionCallId - Optional function call ID to match response to call
   */
  async sendFunctionResponse(name, response, functionCallId = null) {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      return;
    }

    try {
      const responseMessage = {
        clientContent: {
          turns: [
            {
              role: 'user',
              parts: [
                {
                  functionResponse: {
                    name: name,
                    response: response || {},
                    ...(functionCallId && { id: functionCallId }),
                  },
                },
              ],
            },
          ],
          // Don't set turnComplete: true here - function responses should not end the turn
          // The model will continue processing after receiving the response
          turnComplete: false,
        },
      };

      this.ws.send(JSON.stringify(responseMessage));
      logger.vertexAI('function_response_sent', { 
        function_name: name,
        has_call_id: !!functionCallId,
      });
    } catch (error) {
      logger.error('vertex.function_response_failed', {
        error_code: error.code,
        error_message: error.message,
        function_name: name,
      });
    }
  }

  /**
   * Signal end of user utterance (turnComplete: true)
   * This tells the model that the user has finished speaking and it should process and respond
   */
  async sendTurnComplete() {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      throw new Error('Session not ready - WebSocket not connected or setup not complete');
    }

    try {
      // Send turnComplete message (empty turn with turnComplete: true)
      const turnCompleteMessage = {
        clientContent: {
          turns: [],
          turnComplete: true,
        },
      };

      this.ws.send(JSON.stringify(turnCompleteMessage));
      
      logger.vertexAI('turn_complete_sent', {});

    } catch (error) {
      logger.error('vertex.turn_complete_send_failed', {
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
          logger.error(`vertex.event_handler_error`, {
            event: event,
            error_message: error.message,
          });
        }
      });
    }
  }

  /**
   * Close session
   */
  async close() {
    try {
      if (this.ws) {
        this.ws.close();
        this.ws = null;
      }
      this.isConnected = false;
      this.isSetup = false;
      logger.info('vertex.session_closed', {});
    } catch (error) {
      logger.error('vertex.session_close_failed', {
        error_code: error.code,
        error_message: error.message,
      });
    }
  }
}

export default VertexLiveWSSession;

