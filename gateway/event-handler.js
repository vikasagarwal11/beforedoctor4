// Event Handler Module
// Converts Vertex AI events to gateway protocol events

/**
 * Convert Vertex AI session events to gateway protocol events
 */
export class GatewayEventHandler {
  constructor(sendEventCallback, initialSeq = 0) {
    this.sendEvent = sendEventCallback;
    this.seq = Number.isFinite(initialSeq) ? initialSeq : 0;
  }

  /**
   * Get next sequence number
   */
  nextSeq() {
    return ++this.seq;
  }

  /**
   * Handle transcript from Vertex AI
   */
  handleTranscript(data) {
    // Default behavior: emit only the final assistant message.
    // Streaming produces partial chunks first, then a final chunk, which many UIs
    // mistakenly render as "two responses". If you want streaming, set
    // `ASSISTANT_EMIT_PARTIALS=true`.
    const emitPartials = process.env.ASSISTANT_EMIT_PARTIALS === 'true';

    if (data.isPartial) {
      if (!emitPartials) return;
      this.sendEvent('server.transcript.partial', { text: data.text });
      return;
    }

    this.sendEvent('server.transcript.final', { text: data.text });
  }

  /**
   * Handle user transcript (ASR) from Vertex AI
   */
  handleUserTranscript(data) {
    if (data.isPartial) {
      this.sendEvent('server.user.transcript.partial', {
        text: data.text,
      });
    } else {
      this.sendEvent('server.user.transcript.final', {
        text: data.text,
      });
    }
  }

  /**
   * Handle audio output from Vertex AI
   */
  handleAudio(audioBuffer) {
    // Convert Buffer to base64
    const base64 = audioBuffer.toString('base64');
    this.sendEvent('server.audio.out', {
      data: base64,
    });
  }

  /**
   * Handle barge-in (interruption)
   */
  handleBargeIn() {
    this.sendEvent('server.audio.stop', {
      reason: 'interrupted',
    });
  }

  /**
   * Send session state
   */
  sendState(state) {
    this.sendEvent('server.session.state', {
      state: state,
    });
  }

  /**
   * Send error
   */
  sendError(message) {
    this.sendEvent('server.error', {
      message: message,
    });
  }

  /**
   * Send emergency escalation
   */
  sendEmergency(severity, banner) {
    this.sendEvent('server.triage.emergency', {
      severity: severity,
      banner: banner,
    });
  }
}

export default GatewayEventHandler;
