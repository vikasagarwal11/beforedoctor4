// Event Handler Module
// Converts Vertex AI events to gateway protocol events

/**
 * Convert Vertex AI session events to gateway protocol events
 */
export class GatewayEventHandler {
  constructor(sendEventCallback) {
    this.sendEvent = sendEventCallback;
    this.seq = 0;
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
    if (data.isPartial) {
      this.sendEvent('server.transcript.partial', {
        text: data.text,
      });
    } else {
      this.sendEvent('server.transcript.final', {
        text: data.text,
      });
    }
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
   * Handle draft update from function call
   */
  handleDraftUpdate(patch) {
    this.sendEvent('server.ae_draft.update', {
      patch: patch,
    });
  }

  /**
   * Handle narrative update
   */
  handleNarrativeUpdate(data) {
    if (typeof data === 'string') {
      this.sendEvent('server.narrative.update', {
        text: data,
      });
    } else if (data.patch) {
      this.sendEvent('server.narrative.update', {
        patch: data.patch,
      });
    }
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
