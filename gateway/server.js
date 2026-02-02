// Main Gateway Server
// Production-grade: WebSocket server that bridges Flutter app to Vertex AI
// Uses OAuth2 bearer tokens, structured logging (no PHI), audit trails

import { randomUUID } from 'crypto';
import { WebSocketServer } from 'ws';
import { config } from './config.js';
import { GatewayEventHandler } from './event-handler.js';
import { logger } from './logger.js';
import { SafetyGuardrail } from './safety-guardrail.js';
import { GoogleStreamingASR } from './stt_streamer.js';
import { getSupabaseAdmin, initializeSupabase, verifySupabaseToken } from './supabase-auth.js';
import { SupabaseMessagePersistence } from './supabase-persistence.js';
import { VertexAISession } from './vertex-ai-client.js';

const GATEWAY_PROTOCOL_VERSION = '1.1';
const GATEWAY_STARTED_AT = new Date().toISOString();

// IMPORTANT:
// The Flutter app already persists chat messages to Supabase.
// If the gateway also persists, the UI will show duplicates (and user ASR will appear in chat
// even before pressing Send). Keep gateway persistence OFF by default.
const GATEWAY_PERSIST_MESSAGES = process.env.GATEWAY_PERSIST_MESSAGES === 'true';

// Initialize Supabase and start server
(async () => {
  await initializeSupabase();

  // Validate Speech-to-Text API if STT fallback is enabled
  if (config.stt.enabled) {
    logger.info('stt.validation_starting', {});
    const sttValid = await GoogleStreamingASR.validateAPI();
    if (!sttValid) {
      logger.warn('stt.api_validation_failed_continuing', {
        note: 'STT fallback may not work - check Speech-to-Text API is enabled in GCP',
      });
      // Continue anyway - STT may still work in some cases, or Vertex transcripts will be used
    } else {
      logger.info('stt.api_validation_passed', {
        note: 'Speech-to-Text API is accessible',
      });
    }
  }
  
  // Create WebSocket server
  const wss = new WebSocketServer({
    port: config.server.port,
    host: '0.0.0.0', // Listen on all interfaces (required for Android emulator to reach 10.0.2.2)
    perMessageDeflate: false, // Disable compression for low latency
  });

  logger.info('gateway.server_starting', {
    port: config.server.port,
    environment: config.server.nodeEnv,
    project: config.vertexAI.projectId,
    location: config.vertexAI.location,
    persist_messages: GATEWAY_PERSIST_MESSAGES,
  });

  wss.on('connection', (ws, req) => {
    // Generate session ID for audit logging
    const sessionId = randomUUID();
    const clientIp = req.socket.remoteAddress || 'unknown';
    
    logger.session('connection_opened', sessionId, null, {
      client_ip: clientIp,
      user_agent: req.headers['user-agent'],
    });
    
    let vertexSession = null;
    let agentSession = null;
    let eventHandler = null;
    let userId = null;
    let sessionConfig = null;
    let authenticated = false;
    // Legacy flag from the former Vertex Live path. Live is disabled; keep for minimal diff.
    let vertexReady = false;
    let agentReady = false;
    // REST-only: disable Live regardless of env/config.
    let vertexDisabled = true;
    logger.info('vertex.live_disabled', {
      agent_model: config.vertexAI.agentModel,
    });
    let vertexConnecting = false;
    let lastVertexStartAttemptAt = 0;
    let stt = null;
    let sttFallbackEnabled = config.stt.enabled;
    let sttUsingFallback = config.stt.enabled;
    
    // Persistence: Initialize persistence module and track conversation
    let persistence = null;
    let currentConversationId = null;

    // Audio ingress stats (helps diagnose "listening but no transcripts")
    let audioInFrames = 0;
    let audioInBytes = 0;
    let lastAudioNotReadyAt = 0;
    
    // Track first model audio chunk per turn (used for latency KPI)
    let firstAudioInTurn = true;
    
    // Heartbeat for connection health monitoring
    let heartbeatInterval = null;
    let isAlive = true;
    const HEARTBEAT_INTERVAL_MS = 30000; // 30 seconds
    
    // Metrics tracking
    const metrics = {
      vertexTranscripts: { partial: 0, final: 0 },
      sttTranscripts: { partial: 0, final: 0 },
      emergencyDetections: { vertex: 0, stt: 0 },
      transcriptSource: 'none', // 'vertex', 'stt', or 'none'
    };

    // Temporary sequence counter for pre-session events
    let tempSeq = 0;
    
    // Helper to send events in gateway protocol format
    // Note: eventHandler will be properly initialized in client.hello handler
    const sendEvent = (type, payload) => {
      // Temporary handler for pre-session events (before eventHandler is initialized)
      if (!eventHandler) {
        const message = JSON.stringify({
          type: type,
          seq: tempSeq++,
          payload: payload,
        });
        
        if (ws.readyState === ws.OPEN) {
          ws.send(message);
          logger.gateway('event_sent_pre_session', { type, seq: tempSeq - 1 });
        }
        return;
      }
      
      // Normal path: use eventHandler for sequence management
      const seq = eventHandler.nextSeq();
      const message = JSON.stringify({
        type: type,
        seq: seq,
        payload: payload,
      });
      
      if (ws.readyState === ws.OPEN) {
        ws.send(message);
        logger.gateway('event_sent', { type, seq });
      }
    };

    // Emit a build/version handshake immediately so clients can confirm
    // they are connected to the expected gateway deployment.
    sendEvent('server.gateway.info', {
      protocol_version: GATEWAY_PROTOCOL_VERSION,
      build_id: config.server.buildId,
      node_env: config.server.nodeEnv,
      started_at: GATEWAY_STARTED_AT,
      agent_model: config.vertexAI.agentModel,
      assistant_language: process.env.ASSISTANT_LANGUAGE || 'English',
      stt_fallback_enabled: config.stt.enabled,
    });

    // Track last sent state to avoid spam
    let lastSentState = null;
    
    // Enhanced sendEvent that suppresses duplicate state transitions
    const sendStateEvent = (state) => {
      if (state !== lastSentState) {
        lastSentState = state;
        sendEvent('server.session.state', { state });
      }
    };

    // REST-only: no Vertex Live sessions.
    const ensureVertexSessionReady = async () => false;

    // Handle incoming messages (both JSON and binary)
    ws.on('message', async (data, isBinary) => {
      try {
        const asBuffer =
          Buffer.isBuffer(data)
            ? data
            : data instanceof ArrayBuffer
              ? Buffer.from(data)
              : ArrayBuffer.isView(data)
                ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
                : null;

        const canAcceptAudio = () => !!(authenticated && sttFallbackEnabled && sttUsingFallback && stt);

        const handleBinaryAudio = async (pcmBuffer) => {
          if (!pcmBuffer || pcmBuffer.length < 2) return;

          // REST-only: ignore audio before auth/session init or if STT isn't running.
          if (!canAcceptAudio()) return;

          // Ensure PCM16 frames are even length
          if (pcmBuffer.length % 2 !== 0) {
            pcmBuffer = pcmBuffer.subarray(0, pcmBuffer.length - 1);
            if (pcmBuffer.length < 2) return;
          }

          audioInFrames++;
          audioInBytes += pcmBuffer.length;
          if (audioInFrames % 50 === 0) {
            logger.info('gateway.audio_ingress', {
              session_id: sessionId,
              user_id: userId,
              frames: audioInFrames,
              bytes: audioInBytes,
              avg_bytes_per_frame: Math.round(audioInBytes / audioInFrames),
            });
          }

          try {
            stt.write(pcmBuffer);
          } catch (e) {
            logger.warn('stt.fallback_write_failed', { session_id: sessionId, error: String(e) });
          }

          sendStateEvent('listening');
        };

        // =========================================================
        // 1) BINARY FRAMES: raw PCM16k s16le mono audio frames
        // =========================================================
        if (isBinary === true) {
          await handleBinaryAudio(asBuffer ?? Buffer.from(data));
          return;
        }

        // =========================================================
        // 2) TEXT FRAMES: JSON protocol messages
        // =========================================================
        // NOTE: if `ws` (or proxies) deliver a Buffer here with isBinary=false,
        // never try to JSON.parse raw PCM; treat it as binary audio instead.
        if (typeof data !== 'string') {
          if (asBuffer == null) {
            logger.warn('gateway.unknown_frame_type', {
              session_id: sessionId,
              data_type: typeof data,
            });
            return;
          }

          // If the client accidentally sent JSON as bytes, it will still parse.
          // If parsing fails, fall back to binary audio (no server.error spam).
          const textCandidate = asBuffer.toString('utf8');
          try {
            const parsed = JSON.parse(textCandidate);
            // If it parses, proceed as a normal JSON message.
            data = JSON.stringify(parsed);
          } catch (_) {
            await handleBinaryAudio(asBuffer);
            return;
          }
        }

        const text = data;

        let message;
        try {
          message = JSON.parse(text);
        } catch (parseError) {
          // Robust fallback: some clients mistakenly send raw base64 audio as a plain string.
          // If it looks like base64 PCM, accept it without spamming server.error.
          const looksLikeBase64 = (s) => {
            if (typeof s !== 'string') return false;
            const trimmed = s.trim();
            if (trimmed.length < 64) return false;
            if (trimmed.length % 4 !== 0) return false;
            if (!/^[A-Za-z0-9+/=\r\n]+$/.test(trimmed)) return false;
            return true;
          };

          if (looksLikeBase64(text)) {
            if (canAcceptAudio()) {
              try {
                const pcmBuffer = Buffer.from(text.trim(), 'base64');
                await handleBinaryAudio(pcmBuffer);
              } catch (e) {
                logger.warn('gateway.base64_audio_decode_failed', {
                  session_id: sessionId,
                  error: e?.message || String(e),
                });
              }
            } else {
              logger.warn('gateway.base64_audio_received_before_ready', {
                session_id: sessionId,
                reason: !authenticated
                  ? 'not_authenticated'
                  : !sttFallbackEnabled
                    ? 'stt_disabled'
                    : !stt
                      ? 'stt_not_started'
                      : 'not_ready',
              });
            }
            return;
          }

          logger.warn('gateway.json_parse_failed', {
            session_id: sessionId,
            is_binary: !!isBinary,
            text_preview: text.slice(0, 120),
            error_message: parseError.message,
          });

          // Do NOT surface this to the client: some proxies/misconfigurations deliver
          // binary audio as text. Dropping softly prevents hard session failures.
          return;
        }
        
        logger.gateway('event_received', { session_id: sessionId, type: message?.type });
        
        // Track conversation ID from any client message if provided
        if (message?.payload?.conversation_id && !currentConversationId) {
          currentConversationId = message.payload.conversation_id;
          logger.session('conversation_tracked_from_message', sessionId, userId, {
            conversationId: currentConversationId,
            messageType: message.type,
          });
        }
        
        // ---------------------------------------------------------
        // GATE JSON AUDIO MESSAGES ON vertexReady TOO (IMPORTANT)
        // ---------------------------------------------------------
        if (!vertexDisabled && (
          message?.type === 'client.audio.chunk' ||
          message?.type === 'client.audio.chunk.base64'
        )) {
          if (!vertexSession || !authenticated || !vertexReady) {
            logger.warn('gateway.audio_chunk_rejected', {
              session_id: sessionId,
              reason: !vertexSession
                ? 'session_not_initialized'
                : !authenticated
                  ? 'not_authenticated'
                  : 'vertex_not_ready',
            });
            return;
          }
        }

        switch (message.type) {
          case 'client.hello': {
            try {
              // Diagnostic logging: Check what we received
              logger.info('gateway.client_hello_received', {
                has_payload: !!message.payload,
                has_token: !!(message.payload?.supabase_access_token),
                token_length: message.payload?.supabase_access_token?.length || 0,
                has_session_config: !!(message.payload?.session_config),
              });
              
              // Verify Supabase token
              const tokenData = await verifySupabaseToken(
                message.payload.supabase_access_token
              );
              userId = tokenData.uid;
              sessionConfig = message.payload.session_config;
              authenticated = true;
              
              // Initialize persistence module with Supabase admin client (optional)
              if (GATEWAY_PERSIST_MESSAGES) {
                try {
                  const supabase = getSupabaseAdmin();
                  if (supabase) {
                    persistence = new SupabaseMessagePersistence(supabase);
                    logger.session('persistence_initialized', sessionId, userId, {});
                  }
                } catch (error) {
                  logger.error('persistence_initialization_failed', {
                    session_id: sessionId,
                    error: error.message,
                  });
                }
              } else {
                logger.session('persistence_disabled', sessionId, userId, {
                  reason: 'GATEWAY_PERSIST_MESSAGES is not true',
                });
              }
              
              // Track conversation ID from client if provided
              if (message.payload.conversation_id) {
                currentConversationId = message.payload.conversation_id;
                logger.session('conversation_tracked', sessionId, userId, {
                  conversationId: currentConversationId,
                });
              }

              logger.session('authenticated', sessionId, userId, {
                has_session_config: !!sessionConfig,
              });

              // Vertex Live is intentionally disabled (REST-only).
              if (false) {
                // Initialize Vertex Live WebSocket session
                try {
                  vertexSession = new VertexLiveWSSession(sessionConfig);
                  await vertexSession.initialize();

                  // CRITICAL: Register setup handler BEFORE startSession()
                  // Otherwise the setup event fires before this handler is registered
                  vertexSession.on('setup', () => {
                    // CRITICAL: Set flag to allow audio processing
                    vertexReady = true;
                    
                    logger.session('vertex_setup_complete', sessionId, userId, {
                      vertex_ready: true,
                    });
                    
                    // NOW it's safe to tell Flutter we're ready and listening
                    sendStateEvent('ready');
                    sendStateEvent('listening');
                    
                    logger.session('session_ready', sessionId, userId, {
                      audio_accepted: true,
                    });
                  });

                  // Send initial connecting state (before startSession for UX responsiveness)
                  sendStateEvent('connecting');

                  // Start session (waits for setupComplete internally)
                  await vertexSession.startSession();

                  // Safety net: if setup already completed before handler fired
                  if (vertexSession.isSetup === true && vertexReady !== true) {
                    vertexReady = true;
                    sendStateEvent('ready');
                    sendStateEvent('listening');
                    logger.session('session_ready_safety_net', sessionId, userId, {
                      audio_accepted: true,
                    });
                  }
                } catch (vertexError) {
                  logger.error('vertex.session_initialization_failed', {
                    session_id: sessionId,
                    user_id: userId,
                    error_message: vertexError.message,
                    error_code: vertexError.code,
                  });
                  
                  if (!vertexDisabled) {
                    sendEvent('server.error', {
                      message: `Vertex AI initialization failed: ${vertexError.message}`,
                      code: 'VERTEX_INIT_FAILED',
                    });
                  } else {
                    logger.warn('vertex.live_init_skipped', {
                      session_id: sessionId,
                      user_id: userId,
                      reason: vertexError.message,
                    });
                  }

                  // Degrade to REST agent + STT fallback; keep connection open
                  vertexSession = null;
                  vertexReady = false;
                  vertexDisabled = true;
                }
              }

              // Initialize REST assistant session (text-only)
              try {
                agentSession = new VertexAISession(sessionConfig);
                await agentSession.initialize();
                await agentSession.startSession();
                agentReady = true;
                logger.session('agent_session_ready', sessionId, userId, {
                  model: config.vertexAI.agentModel,
                });
                if (vertexDisabled) {
                  sendStateEvent('ready');
                  sendStateEvent('listening');
                }
              } catch (agentError) {
                agentReady = false;
                logger.error('agent.session_initialization_failed', {
                  session_id: sessionId,
                  user_id: userId,
                  error_message: agentError.message,
                  error_code: agentError.code,
                });
              }

              // Set up event handlers
              // IMPORTANT: keep sequence numbers monotonic across pre-session and post-session
              // to avoid client-side out-of-order drops.
              eventHandler = new GatewayEventHandler(
                sendEvent,
                Math.max(0, tempSeq - 1)
              );
              
              // Initialize safety guardrail
              const safetyGuardrail = new SafetyGuardrail();

              // Track transcript state to ensure we send all responses
              let lastAssistantText = '';
              let lastAssistantPartial = '';

              const handleAssistantTranscript = async (data, source) => {
                logger.session('transcript_event_received', sessionId, userId, {
                  source,
                  text_length: data.text.length,
                  is_partial: data.isPartial,
                  text_preview: data.text.substring(0, 100),
                });

                eventHandler.handleTranscript(data);

                if (data.isPartial) {
                  lastAssistantPartial = data.text;
                } else {
                  lastAssistantText = data.text;
                  lastAssistantPartial = '';
                }

                if (GATEWAY_PERSIST_MESSAGES && !data.isPartial && data.text && currentConversationId && persistence) {
                  try {
                    await persistence.saveAssistantMessage(
                      currentConversationId,
                      data.text,
                      randomUUID()
                    );
                    logger.session('assistant_message_persisted', sessionId, userId, {
                      responseLength: data.text.length,
                      conversationId: currentConversationId,
                      textPreview: data.text.substring(0, 100),
                      source,
                    });
                  } catch (error) {
                    logger.error('persist_assistant_message_failed', {
                      error: error.message,
                      sessionId,
                      userId,
                    });
                  }
                }
              };

              if (vertexSession) {
                vertexSession.on('transcript', async (data) => {
                  await handleAssistantTranscript(data, 'live');
                });
              }

              if (agentSession) {
                agentSession.on('transcript', async (data) => {
                  await handleAssistantTranscript(data, 'rest');
                });
              }

              if (vertexSession) {
              vertexSession.on('userTranscript', (data) => {
                // If Vertex provides user transcripts, prefer it over fallback STT
                if (sttUsingFallback) {
                  sttUsingFallback = false;
                  metrics.transcriptSource = 'vertex';
                  logger.session('switching_to_vertex_transcripts', sessionId, userId, {
                    metrics: {
                      stt_transcripts_before_switch: metrics.sttTranscripts.partial + metrics.sttTranscripts.final,
                    },
                  });
                  if (config.stt.disableOnVertex && stt) {
                    stt.stop();
                    stt = null;
                  }
                }

                // Update metrics
                if (data.isPartial) {
                  metrics.vertexTranscripts.partial++;
                } else {
                  metrics.vertexTranscripts.final++;
                }

                // Safety Guardrail Loop: Scan USER transcript for red flags
                const emergency = safetyGuardrail.scan(data.text);
                if (emergency) {
                  metrics.emergencyDetections.vertex++;
                  logger.session('emergency_detected', sessionId, userId, {
                    severity: emergency.severity,
                    source: 'vertex',
                  });
                  sendEvent('server.triage.emergency', {
                    severity: emergency.severity,
                    banner: emergency.banner,
                  });
                  
                  // If critical, interrupt immediately
                  if (emergency.interrupt) {
                    sendEvent('server.audio.stop', {
                      reason: 'emergency_interrupt',
                    });
                  }
                }

                // Optional: Save final user transcript to Supabase (disabled by default)
                if (GATEWAY_PERSIST_MESSAGES && !data.isPartial && data.text && currentConversationId && persistence) {
                  (async () => {
                    try {
                      await persistence.saveUserMessage(
                        currentConversationId,
                        data.text,
                        randomUUID()
                      );
                      logger.session('user_message_persisted', sessionId, userId, {
                        contentLength: data.text.length,
                        conversationId: currentConversationId,
                      });
                    } catch (error) {
                      logger.error('persist_user_message_failed', {
                        error: error.message,
                        sessionId,
                        userId,
                      });
                    }
                  })();
                }

                // REST-only UX: do NOT auto-send transcripts to the model.
                // The client controls when to send via `client.text.turn`.

                eventHandler.handleUserTranscript(data);
              });
              }

              if (vertexSession) {
                vertexSession.on('closed', ({ code, reason }) => {
                  vertexReady = false;
                  logger.session('vertex_session_closed', sessionId, userId, {
                    code,
                    reason,
                  });
                  sendStateEvent('connecting');
                });

                vertexSession.on('error', (err) => {
                  vertexReady = false;
                  logger.session('vertex_session_error', sessionId, userId, {
                    error_message: err?.message || String(err),
                  });
                  sendStateEvent('connecting');
                });
              }

              // Start fallback STT stream if enabled
              if (sttFallbackEnabled) {
                try {
                  const languageCode = sessionConfig?.language_code || 'en-US';
                  stt = new GoogleStreamingASR({ languageCode });
                  stt.start((sttData) => {
                    // Only process STT transcripts if we're still using fallback
                    if (!sttUsingFallback) return;
                    
                    // Update metrics
                    metrics.transcriptSource = 'stt';
                    if (sttData.isPartial) {
                      metrics.sttTranscripts.partial++;
                    } else {
                      metrics.sttTranscripts.final++;
                    }
                    
                    const emergency = safetyGuardrail.scan(sttData.text);
                    if (emergency) {
                      metrics.emergencyDetections.stt++;
                      logger.session('emergency_detected', sessionId, userId, {
                        severity: emergency.severity,
                        source: 'stt_fallback',
                      });
                      sendEvent('server.triage.emergency', {
                        severity: emergency.severity,
                        banner: emergency.banner,
                      });
                      if (emergency.interrupt) {
                        sendEvent('server.audio.stop', {
                          reason: 'emergency_interrupt',
                        });
                      }
                    }
                      // Optional: Save final user transcript to Supabase (STT fallback)
                      if (GATEWAY_PERSIST_MESSAGES && !sttData.isPartial && sttData.text && currentConversationId && persistence) {
                        (async () => {
                          try {
                            await persistence.saveUserMessage(
                              currentConversationId,
                              sttData.text,
                              randomUUID()
                            );
                            logger.session('user_message_persisted', sessionId, userId, {
                              contentLength: sttData.text.length,
                              conversationId: currentConversationId,
                            });
                          } catch (error) {
                            logger.error('persist_user_message_failed', {
                              error: error.message,
                              sessionId,
                              userId,
                            });
                          }
                        })();
                      }

                      // REST-only UX: do NOT auto-send STT finals to the model.
                      // The client controls when to send via `client.text.turn`.
                    eventHandler.handleUserTranscript(sttData);
                  }, (sttError) => {
                    // Surface a clear actionable error to the client and avoid silent "listening".
                    const msg = sttError?.message || String(sttError);
                    const code = sttError?.code;

                    // If Speech API is disabled/not enabled, retries won't help.
                    const looksDisabled =
                      code === 7 &&
                      typeof msg === 'string' &&
                      (msg.includes('speech.googleapis.com') || msg.toLowerCase().includes('api has not been used'));

                    if (looksDisabled) {
                      sendEvent('server.error', {
                        code: 'STT_API_DISABLED',
                        message:
                          'Speech-to-Text API is disabled for the Google Cloud project of your service account. Enable `speech.googleapis.com` in GCP, then restart the gateway.',
                      });

                      logger.session('stt_fallback_disabled', sessionId, userId, {
                        reason: 'speech_api_disabled',
                        error_code: code,
                      });

                      sttFallbackEnabled = false;
                      sttUsingFallback = false;
                      try {
                        stt?.stop();
                      } catch (_) {}
                      stt = null;
                    }
                  });
                  metrics.transcriptSource = 'stt'; // Initial state
                  logger.session('stt_fallback_started', sessionId, userId, {
                    language_code: languageCode,
                  });
                } catch (error) {
                  logger.error('stt.fallback_start_failed', {
                    session_id: sessionId,
                    user_id: userId,
                    error_code: error.code,
                    error_message: error.message,
                  });
                  // Continue without STT fallback - Vertex transcripts may still work
                  sttFallbackEnabled = false;
                  sttUsingFallback = false;
                  metrics.transcriptSource = 'vertex'; // Fall back to vertex-only
                }
              }

              // Track if this is first audio in the turn (already declared at connection scope)
              firstAudioInTurn = true;
              
              if (vertexSession) {
                vertexSession.on('audio', (audioBuffer) => {
                  // LATENCY KPI: Emit on first audio chunk
                  if (firstAudioInTurn) {
                    sendEvent('server.kpi', {
                      type: 'first_model_audio',
                      atMs: Date.now(),
                    });
                    firstAudioInTurn = false;
                  }

                  eventHandler.handleAudio(audioBuffer);
                });

                vertexSession.on('bargeIn', () => {
                  logger.session('barge_in', sessionId, userId, {});
                  eventHandler.handleBargeIn();
                });
              }

              if (vertexSession) {
                vertexSession.on('error', (error) => {
                  logger.error('vertex.session_error', {
                    session_id: sessionId,
                    user_id: userId,
                    error_code: error.code,
                    error_message: error.message,
                  });
                  eventHandler.sendError(error.message);
                });
              }

            } catch (error) {
              // Enhanced error logging with stack trace in development
              logger.error('gateway.session_init_failed', {
                session_id: sessionId,
                error_code: error.code,
                error_message: error.message,
                error_stack: process.env.NODE_ENV === 'development' ? error.stack : undefined,
                has_payload: !!message.payload,
                has_token: !!(message.payload?.firebase_id_token),
                token_length: message.payload?.firebase_id_token?.length || 0,
              });
              sendEvent('server.error', {
                message: `Failed to initialize session: ${error.message}`,
              });
              ws.close();
            }
            break;
          }

          case 'client.audio.chunk':
          case 'client.audio.chunk.base64': {
            // Backward compatibility: accept both client.audio.chunk and client.audio.chunk.base64
            if (!authenticated) {
              logger.warn('gateway.audio_chunk_rejected', {
                session_id: sessionId,
                reason: 'not_authenticated',
              });
              return;
            }

            try {
              // Decode base64 PCM audio
              let pcmBuffer = Buffer.from(message.payload.data, 'base64');

              // Ensure PCM16 frames are even length
              if (pcmBuffer.length % 2 !== 0) {
                pcmBuffer = pcmBuffer.subarray(0, pcmBuffer.length - 1);
                if (pcmBuffer.length < 2) return;
              }
              
              // Log audio chunk received (no audio content)
              logger.gateway('audio_chunk_received', {
                chunk_size_bytes: pcmBuffer.length,
                message_type: message.type,
              });
              
              // Feed fallback STT (REST-only)
              if (sttFallbackEnabled && sttUsingFallback && stt) {
                stt.write(pcmBuffer);
              }
              
              // Update state to listening if needed (sendStateEvent will suppress duplicates)
              sendStateEvent('listening');
            } catch (error) {
              logger.error('gateway.audio_processing_failed', {
                session_id: sessionId,
                user_id: userId,
                error_code: error.code,
                error_message: error.message,
              });
              sendEvent('server.error', {
                message: `Audio processing error: ${error.message}`,
              });
            }
            break;
          }

          case 'client.audio.turnComplete': {
            // REST-only: accept but treat as a no-op (STT finalization is silence-based).
            logger.gateway('turn_complete_received_from_client', {
              session_id: sessionId,
              user_id: userId,
              timestamp: Date.now(),
            });
            firstAudioInTurn = true;
            break;
          }

          case 'client.text.turn': {
            if (!authenticated) {
              logger.warn('gateway.text_turn_rejected', {
                session_id: sessionId,
                reason: 'not_authenticated',
              });
              return;
            }

            try {
              const text = message.payload?.text || '';
              if (!text.trim()) return;

              logger.gateway('text_turn_received_from_client', {
                session_id: sessionId,
                user_id: userId,
                text_length: text.length,
              });

              if (agentSession && agentReady) {
                await agentSession.sendTextTurn(text);
                logger.gateway('text_turn_forwarded_to_agent', {
                  session_id: sessionId,
                  user_id: userId,
                });
              } else if (vertexSession) {
                // Ensure Vertex session is ready (may need to reconnect)
                if (!vertexSession?.isConnected || !vertexSession?.isSetup || !vertexReady) {
                  const ready = !vertexDisabled ? await ensureVertexSessionReady() : false;
                  if (!ready) {
                    logger.warn('gateway.text_turn_vertex_not_ready', {
                      session_id: sessionId,
                      user_id: userId,
                    });
                    sendEvent('server.error', {
                      message: 'Text turn rejected: session not ready yet. Please wait for Ready state.',
                      code: 'VERTEX_NOT_READY',
                    });
                    return;
                  }
                }

                await vertexSession.sendTextTurn(text);
                logger.gateway('text_turn_forwarded_to_vertex', {
                  session_id: sessionId,
                  user_id: userId,
                });
              } else {
                sendEvent('server.error', {
                  message: 'Text turn rejected: agent not ready and live session unavailable.',
                  code: 'AGENT_NOT_READY',
                });
              }
            } catch (error) {
              logger.error('gateway.text_turn_failed', {
                session_id: sessionId,
                user_id: userId,
                error_code: error.code,
                error_message: error.message,
              });
              sendEvent('server.error', {
                message: `Text turn error: ${error.message}`,
              });
            }
            break;
          }

          case 'client.audio.bargeIn': {
            logger.gateway('barge_in_received', {
              session_id: sessionId,
              user_id: userId,
              reason: message.payload?.reason,
              timestamp: message.payload?.timestamp,
            });

            if (vertexSession) {
              try {
                // Attempt explicit cancel (best-effort)
                await vertexSession.cancelOutput();
                logger.gateway('barge_in_vertex_cancel_sent', {
                  session_id: sessionId,
                });
              } catch (error) {
                logger.warn('barge_in_vertex_cancel_failed', {
                  session_id: sessionId,
                  error_message: error.message,
                });
                // Fallback: just stop forwarding
                vertexSession.stopAudioForwarding = true;
              }
            }

            // Acknowledge barge-in to client
            sendEvent('server.audio.bargeInAck', {
              timestamp: new Date().toISOString(),
            });

            // Update state back to listening
            sendStateEvent('listening');
            break;
          }

          case 'client.session.stop':
          case 'client.stop': {
            // Backward compatibility: accept both client.session.stop and client.stop
            logger.session('stopped_by_client', sessionId, userId, {});
            
            // Reset ready flag
            vertexReady = false;
            
            if (vertexSession) {
              await vertexSession.close();
            }
            stt?.stop();
            
            // Log session metrics
            logger.session('session_stopped', sessionId, userId, {
              metrics: {
                transcript_source: metrics.transcriptSource,
                vertex_transcripts: {
                  partial: metrics.vertexTranscripts.partial,
                  final: metrics.vertexTranscripts.final,
                },
                stt_transcripts: {
                  partial: metrics.sttTranscripts.partial,
                  final: metrics.sttTranscripts.final,
                },
                emergency_detections: {
                  vertex: metrics.emergencyDetections.vertex,
                  stt: metrics.emergencyDetections.stt,
                },
                stt_retry_count: stt?.getRetryCount() || 0,
              },
            });
            
            sendEvent('server.session.state', { state: 'stopped' });
            ws.close();
            break;
          }

          default:
            logger.warn('gateway.unknown_message_type', {
              session_id: sessionId,
              message_type: message.type,
            });
        }
      } catch (error) {
        logger.error('gateway.message_processing_failed', {
          session_id: sessionId,
          user_id: userId,
          error_code: error.code,
          error_message: error.message,
        });
        sendEvent('server.error', {
          message: `Message processing error: ${error.message}`,
        });
      }
    });

    // Handle connection close
    ws.on('close', async () => {
      logger.session('connection_closed', sessionId, userId, {});
      
      // Reset ready flag
      vertexReady = false;
      authenticated = false;
      
      // Stop heartbeat
      if (heartbeatInterval) {
        clearInterval(heartbeatInterval);
        heartbeatInterval = null;
      }
      
      if (vertexSession) {
        await vertexSession.close();
      }
      stt?.stop();
    });

    // Handle errors
    ws.on('error', (error) => {
      logger.error('gateway.websocket_error', {
        session_id: sessionId,
        user_id: userId,
        error_code: error.code,
        error_message: error.message,
      });
      if (eventHandler) {
        eventHandler.sendError(`Connection error: ${error.message}`);
      }
    });

    // Handle pong responses (heartbeat)
    ws.on('pong', () => {
      isAlive = true;
    });

    // Start heartbeat ping/pong loop
    heartbeatInterval = setInterval(() => {
      if (ws.readyState !== ws.OPEN) {
        return;
      }

      if (!isAlive) {
        logger.warn('gateway.heartbeat_failed_closing', { 
          session_id: sessionId,
          user_id: userId,
        });
        try {
          ws.terminate();
        } catch (_) {
          // Ignore termination errors
        }
        return;
      }

      isAlive = false;
      try {
        ws.ping();
      } catch (e) {
        logger.warn('gateway.ping_failed', { 
          session_id: sessionId,
          user_id: userId,
          error: String(e),
        });
      }
    }, HEARTBEAT_INTERVAL_MS);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    logger.info('gateway.shutdown_initiated', { signal: 'SIGTERM' });
    wss.close(() => {
      logger.info('gateway.server_closed', {});
      process.exit(0);
    });
  });

  process.on('SIGINT', () => {
    logger.info('gateway.shutdown_initiated', { signal: 'SIGINT' });
    wss.close(() => {
      logger.info('gateway.server_closed', {});
      process.exit(0);
    });
  });

  logger.info('gateway.server_ready', {
    port: config.server.port,
    environment: config.server.nodeEnv,
  });
})();
