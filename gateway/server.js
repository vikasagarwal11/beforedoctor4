// Main Gateway Server
// Production-grade: WebSocket server that bridges Flutter app to Vertex AI
// Uses OAuth2 bearer tokens, structured logging (no PHI), audit trails

import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';
import { config } from './config.js';
import { initializeFirebase, verifyFirebaseToken } from './auth.js';
import { VertexLiveWSSession } from './vertex-live-ws-client.js';
import { GatewayEventHandler } from './event-handler.js';
import { SafetyGuardrail } from './safety-guardrail.js';
import { logger } from './logger.js';

// Initialize Firebase and start server
(async () => {
  await initializeFirebase();
  
  // Create WebSocket server
  const wss = new WebSocketServer({
    port: config.server.port,
    perMessageDeflate: false, // Disable compression for low latency
  });

  logger.info('gateway.server_starting', {
    port: config.server.port,
    environment: config.server.nodeEnv,
    project: config.vertexAI.projectId,
    location: config.vertexAI.location,
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
    let eventHandler = null;
    let userId = null;
    let sessionConfig = null;
    let authenticated = false;

    // Helper to send events in gateway protocol format
    const sendEvent = (type, payload) => {
      if (!eventHandler) {
        eventHandler = new GatewayEventHandler((t, p) => {
          const seq = eventHandler.nextSeq();
          const message = JSON.stringify({
            type: t,
            seq: seq,
            payload: p,
          });
          if (ws.readyState === ws.OPEN) {
            ws.send(message);
            // Log event sent (no payload content - may contain PHI)
            logger.gateway('event_sent', { type: t, seq });
          }
        });
      }
      
      const seq = eventHandler.nextSeq();
      const message = JSON.stringify({
        type: type,
        seq: seq,
        payload: payload,
      });
      
      if (ws.readyState === ws.OPEN) {
        ws.send(message);
        // Log event sent (no payload content)
        logger.gateway('event_sent', { type, seq });
      }
    };

    // Handle incoming messages
    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        
        // Log message received (no payload content - may contain PHI)
        logger.gateway('event_received', { type: message.type });

        switch (message.type) {
          case 'client.hello': {
            try {
              // Verify Firebase token
              const tokenData = await verifyFirebaseToken(
                message.payload.firebase_id_token
              );
              userId = tokenData.uid;
              sessionConfig = message.payload.session_config;
              authenticated = true;

              logger.session('authenticated', sessionId, userId, {
                has_session_config: !!sessionConfig,
              });

              // Initialize Vertex Live WebSocket session
              vertexSession = new VertexLiveWSSession(sessionConfig);
              await vertexSession.initialize();
              await vertexSession.startSession();

              // Set up event handlers
              eventHandler = new GatewayEventHandler(sendEvent);
              
              // Initialize safety guardrail
              const safetyGuardrail = new SafetyGuardrail();

              vertexSession.on('transcript', (data) => {
                // Safety Guardrail Loop: Scan for red flags
                const emergency = safetyGuardrail.scan(data.text);
                if (emergency) {
                  logger.session('emergency_detected', sessionId, userId, {
                    severity: emergency.severity,
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
                
                // Continue with normal transcript handling
                eventHandler.handleTranscript(data);
              });

              vertexSession.on('audio', (audioBuffer) => {
                eventHandler.handleAudio(audioBuffer);
              });

              vertexSession.on('bargeIn', () => {
                logger.session('barge_in', sessionId, userId, {});
                eventHandler.handleBargeIn();
              });

              vertexSession.on('draftUpdate', (patch) => {
                eventHandler.handleDraftUpdate(patch);
              });

              vertexSession.on('narrativeUpdate', (data) => {
                eventHandler.handleNarrativeUpdate(data);
              });

              vertexSession.on('error', (error) => {
                logger.error('vertex.session_error', {
                  session_id: sessionId,
                  user_id: userId,
                  error_code: error.code,
                  error_message: error.message,
                });
                eventHandler.sendError(error.message);
              });

              // Send ready state
              sendEvent('server.session.state', { state: 'ready' });
              sendEvent('server.session.state', { state: 'listening' });
              
              logger.session('session_ready', sessionId, userId, {});

            } catch (error) {
              logger.error('gateway.session_init_failed', {
                session_id: sessionId,
                error_code: error.code,
                error_message: error.message,
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
            if (!vertexSession || !authenticated) {
              logger.warn('gateway.audio_chunk_rejected', {
                session_id: sessionId,
                reason: !vertexSession ? 'session_not_initialized' : 'not_authenticated',
              });
              sendEvent('server.error', {
                message: 'Session not initialized',
              });
              return;
            }

            try {
              // Decode base64 PCM audio
              const pcmBuffer = Buffer.from(message.payload.data, 'base64');
              
              // Log audio chunk received (no audio content)
              logger.gateway('audio_chunk_received', {
                chunk_size_bytes: pcmBuffer.length,
                message_type: message.type,
              });
              
              // Send to Vertex AI
              await vertexSession.sendAudio(pcmBuffer);
              
              // Update state to listening if needed
              sendEvent('server.session.state', { state: 'listening' });
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

          case 'client.session.stop':
          case 'client.stop': {
            // Backward compatibility: accept both client.session.stop and client.stop
            logger.session('stopped_by_client', sessionId, userId, {});
            
            if (vertexSession) {
              await vertexSession.close();
            }
            
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
      
      if (vertexSession) {
        await vertexSession.close();
      }
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
