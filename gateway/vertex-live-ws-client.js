// Vertex AI Live WebSocket Client
// Production-grade: True bidirectional WebSocket connection to Vertex Live API
// Replaces the placeholder chat-based implementation

import { GoogleAuth } from 'google-auth-library';
import { dirname } from 'path';
import { fileURLToPath } from 'url';
import WebSocket from 'ws';
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
    this.lastError = null;
    this.audioSendCounter = 0;
    this.audioReceiveCounter = 0;
    this.stopAudioForwarding = false; // Pause audio forwarding on barge-in
    
    // Keepalive mechanism for long sessions
    this.keepaliveInterval = null;
    this.lastActivityAt = Date.now();
    
    // Transcript caching to prevent loss due to timing issues
    this.lastPartialTranscript = '';
    this.lastFinalTranscript = '';
    this._hasLoggedRawMessage = false;
    this.eventHandlers = {
      transcript: [],
      userTranscript: [],
      audio: [],
      bargeIn: [],
      draftUpdate: [],
      narrativeUpdate: [],
      error: [],
      closed: [],
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

      // Use Application Default Credentials (ADC)
      // Cloud Run and local dev both use ADC
      logger.info('vertex.initializing', {
        method: 'application_default_credentials',
        project: config.vertexAI.projectId,
        location: config.vertexAI.location,
      });

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

      this.lastError = null;

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
        perMessageDeflate: false,
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
        if (!this.isSetup) {
          this.lastError = new Error(
            `WebSocket closed before setup complete (code ${code})`
          );
        }
        this.isConnected = false;
        this.isSetup = false;
        this.emit('closed', { code, reason: reason?.toString() });
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
        }, 60000); // Increased from 10s to 60s for slow networks

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
        }, 30000); // Increased from 15s to 30s for reliable setup

        const checkSetup = setInterval(() => {
          if (this.lastError) {
            clearTimeout(timeout);
            clearInterval(checkSetup);
            reject(this.lastError);
            return;
          }
          if (this.isSetup) {
            clearTimeout(timeout);
            clearInterval(checkSetup);
            resolve();
          }
        }, 100);

        const onError = (error) => {
          clearTimeout(timeout);
          clearInterval(checkSetup);
          reject(error);
        };
        const onClose = (code, reason) => {
          clearTimeout(timeout);
          clearInterval(checkSetup);
          const reasonText = reason?.toString?.() || '';
          const detail = reasonText ? `, reason: ${reasonText}` : '';
          reject(new Error(`WebSocket closed before setup complete (code ${code}${detail})`));
        };

        this.ws.once('error', onError);
        this.ws.once('close', onClose);
      });

      logger.info('vertex.session_started', {
        has_system_instruction: !!this.sessionConfig.system_instruction,
      });

      // Start keepalive ping to prevent session timeout during long audio captures
      this._startKeepalive();

    } catch (error) {
      logger.error('vertex.session_start_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      throw error;
    }
  }

  /**
   * Start keepalive mechanism to prevent session timeout
   * Sends periodic activity to keep the WebSocket connection alive
   */
  _startKeepalive() {
    // Clear any existing keepalive
    if (this.keepaliveInterval) {
      clearInterval(this.keepaliveInterval);
    }

    // Send keepalive ping every 30 seconds
    this.keepaliveInterval = setInterval(() => {
      if (this.ws && this.isConnected && this.isSetup) {
        const timeSinceActivity = Date.now() - this.lastActivityAt;
        
        // Only send ping if no activity for 25 seconds
        if (timeSinceActivity > 25000) {
          try {
            // Send a small setup message as keepalive (no-op that keeps connection alive)
            this.ws.ping(() => {
              logger.debug('vertex.keepalive_sent', { 
                time_since_activity_ms: timeSinceActivity 
              });
            });
            this.lastActivityAt = Date.now();
          } catch (error) {
            logger.warn('vertex.keepalive_failed', { 
              error_message: error?.message || String(error) 
            });
          }
        }
      }
    }, 30000); // Check every 30 seconds

    logger.info('vertex.keepalive_started', { interval_ms: 30000 });
  }

  /**
   * Stop keepalive mechanism
   */
  _stopKeepalive() {
    if (this.keepaliveInterval) {
      clearInterval(this.keepaliveInterval);
      this.keepaliveInterval = null;
      logger.info('vertex.keepalive_stopped');
    }
  }

  /**
   * Send setup message (first message after connection)
   * This defines the "Brain" of the agent
   */
  _sendSetupMessage() {
    try {
      const setupMessage = {
        setup: {
          model: `projects/${config.vertexAI.projectId}/locations/${config.vertexAI.location}/publishers/google/models/${config.vertexAI.model}`,
        },
      };

      this.ws.send(JSON.stringify(setupMessage));
      logger.info('vertex.setup_sent', {
        model: setupMessage.setup.model,
      });
      // Log raw setup message for debugging (truncated for size)
      logger.info('vertex.setup_message_raw', {
        message_preview: JSON.stringify(setupMessage).substring(0, 200),
        model: setupMessage.setup.model,
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
      // Log raw message for debugging (first message only or on errors)
      if (!this._hasLoggedRawMessage || message.error) {
        logger.info('vertex.raw_message_received', {
          message_keys: Object.keys(message),
          has_setupComplete: !!message.setupComplete,
          has_setup_complete: !!message.setup_complete,
          has_setupCompleted: !!message.setupCompleted,
          has_BidiGenerateContentSetupComplete: !!message.BidiGenerateContentSetupComplete,
          has_bidiGenerateContentSetupComplete: !!message.bidiGenerateContentSetupComplete,
          has_error: !!message.error,
          has_status: !!message.status,
          has_serverContent: !!message.serverContent,
          message_preview: JSON.stringify(message).substring(0, 300),
        });
        this._hasLoggedRawMessage = true;
      }

      // Handle errors or status messages from Vertex AI
      if (message.error || message.status) {
        const errorMessage = message.error?.message || message.status?.message || message.error || message.status || 'Vertex returned an error during setup';
        this.lastError = new Error(errorMessage);
        logger.error('vertex.server_error_message', {
          message_keys: Object.keys(message),
          error: message.error,
          status: message.status,
          error_message: errorMessage,
        });
        this.emit('error', this.lastError);
        return;
      }

      // Handle setup response - check multiple possible field names
      if (message.setupComplete || 
          message.setup_complete || 
          message.setupCompleted ||
          message.BidiGenerateContentSetupComplete ||
          message.bidiGenerateContentSetupComplete) {
        logger.info('vertex.setup_complete', {});
        this.isSetup = true;
        // Emit setup event so gateway knows Vertex is ready
        this.emit('setup');
        return;
      }

      // Handle server content (model responses)
      if (message.serverContent) {
        // Log serverContent structure for debugging
        logger.vertexAI('server_content_received', {
          has_modelTurn: !!message.serverContent.modelTurn,
          has_inputTranscription: !!(message.serverContent.inputTranscription || 
                                      message.serverContent.userTranscript || 
                                      message.serverContent.userTranscription),
          has_outputTranscription: !!(message.serverContent.outputAudioTranscription ||
                                       message.serverContent.outputTranscription ||
                                       message.serverContent.modelTranscription),
          has_interrupted: message.serverContent.interrupted === true,
          serverContent_keys: Object.keys(message.serverContent).join(','),
        });

        // Check for interruption (barge-in)
        if (message.serverContent.interrupted === true) {
          logger.vertexAI('barge_in_detected', {});
          this.stopAudioForwarding = true; // Stop forwarding immediately
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
            text_preview: inputTranscript.text.substring(0, 100),
          });
          this.emit('userTranscript', {
            text: inputTranscript.text,
            isPartial: isPartial,
          });
        }

        // Handle model turn (audio + text output)
        if (message.serverContent.modelTurn) {
          const parts = message.serverContent.modelTurn.parts || [];
          const isCompleted = message.serverContent.modelTurn.complete === true;

          for (const part of parts) {
            // Handle audio output (24kHz PCM)
            if (part.inlineData && part.inlineData.mimeType?.includes('audio')) {
              const audioData = Buffer.from(part.inlineData.data, 'base64');
              this.audioReceiveCounter++;
              if (this.audioReceiveCounter % 25 === 0) {
                logger.vertexAI('audio_received', {
                  has_audio: true,
                  audio_size_bytes: audioData.length,
                  total_received: this.audioReceiveCounter,
                });
              }
              
              // Skip forwarding audio if barge-in occurred (client already flushed)
              if (!this.stopAudioForwarding) {
                this.emit('audio', audioData);
              } else {
                logger.vertexAI('audio_dropped_barge_in', {
                  audio_size_bytes: audioData.length,
                });
              }
            }

            // Handle text (transcript) from model response
            if (part.text) {
              logger.vertexAI('transcript_received', {
                has_transcript: true,
                is_partial: !isCompleted,
                text_preview: part.text.substring(0, 100),
              });
              this.emit('transcript', {
                text: part.text,
                isPartial: !isCompleted,
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

        // Handle output audio transcription (assistant speech captions)
        // This is the transcription of what the AI is saying (like CC for the AI's voice)
        const outputTranscript =
          message.serverContent.outputAudioTranscription ||
          message.serverContent.outputTranscription ||
          message.serverContent.modelTranscription ||
          message.serverContent.assistantTranscription;
        
        if (outputTranscript && outputTranscript.text) {
          const isFinal = outputTranscript.isFinal ?? outputTranscript.final ?? outputTranscript.is_final;
          const isPartial = isFinal === undefined ? true : !isFinal;
          logger.vertexAI('output_audio_transcript_received', {
            has_transcript: true,
            is_partial: isPartial,
            text_length: outputTranscript.text.length,
            text_preview: outputTranscript.text.substring(0, 100),
          });
          // Emit as transcript (same event as modelTurn.parts[].text for consistency)
          this.emit('transcript', {
            text: outputTranscript.text,
            isPartial: isPartial,
          });
        }

        // CRITICAL: Also check for standalone text parts in serverContent
        // (not under modelTurn, but at top level of serverContent)
        if (message.serverContent.text) {
          logger.vertexAI('standalone_text_received', {
            has_text: true,
            text_length: message.serverContent.text.length,
            text_preview: message.serverContent.text.substring(0, 100),
          });
          this.emit('transcript', {
            text: message.serverContent.text,
            isPartial: !message.serverContent.complete,
          });
        } 
      }

      // Log unrecognized message shapes (for debugging setup issues)
      // Only log if we haven't handled it above (not setupComplete, not serverContent, not error)
      if (!message.setupComplete && 
          !message.setup_complete && 
          !message.setupCompleted &&
          !message.BidiGenerateContentSetupComplete &&
          !message.bidiGenerateContentSetupComplete &&
          !message.serverContent && 
          !message.error &&
          !message.status) {
        logger.warn('vertex.unhandled_message', {
          message_keys: Object.keys(message),
          message_preview: JSON.stringify(message).substring(0, 500),
        });
      }

      // Handle errors (duplicate check - this is for runtime errors not caught earlier)
      if (message.error) {
        this.lastError = new Error(message.error.message || 'Vertex API error');
        logger.error('vertex.api_error', {
          error_code: message.error.code,
          error_message: message.error.message,
        });
        this.emit('error', new Error(message.error.message));
      }

    } catch (error) {
      logger.error('vertex.message_handle_failed', {
        error_message: error.message,
        error_stack: error.stack,
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
      // Update activity timestamp for keepalive
      this.lastActivityAt = Date.now();
      
      // Convert PCM to base64
      const audioBase64 = pcm16k.toString('base64');

      // Log audio chunk sent (no audio content)
      this.audioSendCounter++;
      if (this.audioSendCounter % 25 === 0) {
        logger.vertexAI('audio_chunk_sent', {
          chunk_size_bytes: pcm16k.length,
          has_audio: true,
          total_sent: this.audioSendCounter,
        });
      }

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
                    mimeType: 'audio/l16;rate=16000',
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
      throw error; // CRITICAL: fail fast so gateway can recover
    }
  }

  /**
   * Send a text turn to Vertex Live API (used for edited transcripts)
   * @param {string} text - User text to process
   */
  async sendTextTurn(text) {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      throw new Error('Session not ready - WebSocket not connected or setup not complete');
    }

    try {
      if (!text || !text.trim()) return;

      this.lastActivityAt = Date.now();

      const inputMessage = {
        clientContent: {
          turns: [
            {
              role: 'user',
              parts: [
                {
                  text: text,
                },
              ],
            },
          ],
          turnComplete: true,
        },
      };

      this.ws.send(JSON.stringify(inputMessage));

      logger.vertexAI('text_turn_sent', {
        text_length: text.length,
      });
    } catch (error) {
      logger.error('vertex.text_turn_send_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
      throw error;
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
   * Cancel current model output (for barge-in scenarios)
   * Best-effort: stop forwarding locally and send a turn boundary.
   * IMPORTANT: do NOT re-enable forwarding as part of cancel.
   */
  async cancelOutput() {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      throw new Error('Session not ready - WebSocket not connected or setup not complete');
    }

    // Stop forwarding immediately (prevents stale audio leaking to client)
    this.stopAudioForwarding = true;

    try {
      logger.vertexAI('cancel_output_requested', {
        is_connected: this.isConnected,
        is_setup: this.isSetup,
      });

      // Do NOT re-enable forwarding during cancel
      await this.sendTurnComplete({ reenableForwarding: false });

      logger.vertexAI('cancel_output_completed', {
        method: 'turnComplete_reset',
        forwarding_disabled: true,
      });
    } catch (error) {
      // Keep stopAudioForwarding=true to prevent audio leakage even if Vertex call fails
      logger.error('vertex.cancel_output_failed', { error_message: error.message });
      throw error;
    }
  }

  /**
   * Signal end of user utterance (turnComplete: true)
   * @param {Object} options
   * @param {boolean} options.reenableForwarding - default true; set false for barge-in cancel
   */
  async sendTurnComplete({ reenableForwarding = true } = {}) {
    if (!this.ws || !this.isConnected || !this.isSetup) {
      throw new Error('Session not ready - WebSocket not connected or setup not complete');
    }

    try {
      // Minimal empty user turn is more compatible than turns:[]
      const msg = {
        clientContent: {
          turns: [{ role: 'user', parts: [] }],
          turnComplete: true,
        },
      };

      this.ws.send(JSON.stringify(msg));

      if (reenableForwarding) {
        this.stopAudioForwarding = false;
      }

      logger.vertexAI('turn_complete_sent_to_vertex', {
        message_sent: true,
        has_minimal_turn: true,
        reenabled_forwarding: reenableForwarding,
      });
    } catch (error) {
      logger.error('vertex.turn_complete_send_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      this.emit('error', error);
      throw error; // CRITICAL: fail fast so gateway can recover
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
      // Stop keepalive before closing
      this._stopKeepalive();
      
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
