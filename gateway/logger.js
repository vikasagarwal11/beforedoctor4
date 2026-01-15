// Structured Logging Module
// Production-grade: No PHI in logs, structured JSON format

/**
 * Structured logger that redacts PHI (Protected Health Information)
 * Logs only metadata, error codes, and structured data
 */
export class StructuredLogger {
  constructor(context = {}) {
    this.context = {
      service: 'beforedoctor-gateway',
      ...context,
    };
  }

  /**
   * Create a child logger with additional context
   */
  child(additionalContext) {
    return new StructuredLogger({
      ...this.context,
      ...additionalContext,
    });
  }

  /**
   * Log structured event (no PHI)
   */
  log(level, event, data = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      event,
      ...this.context,
      ...this.redactPHI(data),
    };

    // In production, use structured JSON logging
    if (process.env.NODE_ENV === 'production') {
      console.log(JSON.stringify(logEntry));
    } else {
      // Development: human-readable format
      console.log(`[${level.toUpperCase()}] ${event}`, logEntry);
    }
  }

  /**
   * Redact PHI from log data
   */
  redactPHI(data) {
    const redacted = { ...data };
    
    // Redact common PHI fields
    const phiFields = [
      'transcript',
      'text',
      'audio',
      'data',
      'email',
      'phone',
      'name',
      'patient',
      'narrative',
      'symptoms',
      'diagnosis',
    ];

    for (const field of phiFields) {
      if (redacted[field]) {
        redacted[field] = '[REDACTED]';
      }
    }

    // Redact nested objects
    for (const key in redacted) {
      if (typeof redacted[key] === 'object' && redacted[key] !== null) {
        redacted[key] = this.redactPHI(redacted[key]);
      }
    }

    return redacted;
  }

  /**
   * Log info level
   */
  info(event, data) {
    this.log('info', event, data);
  }

  /**
   * Log warning level
   */
  warn(event, data) {
    this.log('warn', event, data);
  }

  /**
   * Log error level
   */
  error(event, data) {
    this.log('error', event, data);
  }

  /**
   * Log debug level (only in development)
   */
  debug(event, data) {
    if (process.env.NODE_ENV !== 'production') {
      this.log('debug', event, data);
    }
  }

  /**
   * Log session event (audit trail)
   */
  session(event, sessionId, userId, data = {}) {
    this.log('info', `session.${event}`, {
      session_id: sessionId,
      user_id: userId,
      ...data,
    });
  }

  /**
   * Log gateway event (no PHI)
   */
  gateway(event, data = {}) {
    this.log('info', `gateway.${event}`, {
      event_type: data.type,
      seq: data.seq,
      // No payload content (may contain PHI)
    });
  }

  /**
   * Log Vertex AI event (no PHI)
   */
  vertexAI(event, data = {}) {
    this.log('info', `vertex.${event}`, {
      // Only log metadata, not content
      has_audio: !!data.hasAudio,
      has_transcript: !!data.hasTranscript,
      chunk_count: data.chunkCount,
      error_code: data.errorCode,
    });
  }
}

// Default logger instance
export const logger = new StructuredLogger();

export default logger;


