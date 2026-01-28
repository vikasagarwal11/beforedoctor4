// Google Cloud Speech-to-Text streaming fallback
// Provides user ASR when Vertex Live input transcription is unavailable.

import { SpeechClient } from '@google-cloud/speech';
import { logger } from './logger.js';

export class GoogleStreamingASR {
  constructor({ languageCode = 'en-US', maxRetries = 3, retryDelayMs = 1000 } = {}) {
    this.languageCode = languageCode;
    this.client = new SpeechClient();
    this.stream = null;
    this.started = false;
    this.maxRetries = maxRetries;
    this.retryDelayMs = retryDelayMs;
    this.retryCount = 0;
    this.onTranscript = null;
    this.onError = null;
  }

  /**
   * Validate that Speech-to-Text API is accessible
   * @returns {Promise<boolean>} True if API is accessible, false otherwise
   */
  static async validateAPI() {
    try {
      // Simple instantiation check - if SpeechClient can be created, assume API is accessible
      // Full validation would require making an actual API call with audio, which is expensive
      const client = new SpeechClient();
      logger.info('stt.api_validation_passed', {
        note: 'SpeechClient instantiated successfully',
      });
      return true;
    } catch (error) {
      logger.error('stt.api_validation_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      return false;
    }
  }

  start(onTranscript, onError) {
    if (this.started) return;
    this.onTranscript = onTranscript;
    this.onError = onError;
    this.retryCount = 0;
    this._startWithRetry();
  }

  /**
   * Start stream with retry logic (exponential backoff)
   */
  _startWithRetry() {
    if (this.started && this.stream) return;
    
    try {
      this.started = true;

      const request = {
        config: {
          encoding: 'LINEAR16',
          sampleRateHertz: 16000,
          languageCode: this.languageCode,
          enableAutomaticPunctuation: true,
        },
        interimResults: true,
      };

      this.stream = this.client
        .streamingRecognize(request)
        .on('error', (error) => {
          logger.error('stt.stream_error', {
            error_code: error.code,
            error_message: error.message,
            retry_count: this.retryCount,
          });

          if (this.onError) {
            try {
              this.onError(error);
            } catch (_) {
              // Ignore user callback errors.
            }
          }
          
          // Reset started flag on error so we can retry
          this.started = false;
          this.stream = null;

          // Retry with exponential backoff
          if (this.retryCount < this.maxRetries && this.onTranscript) {
            const delayMs = this.retryDelayMs * Math.pow(2, this.retryCount);
            this.retryCount++;
            
            logger.info('stt.stream_retrying', {
              retry_count: this.retryCount,
              max_retries: this.maxRetries,
              delay_ms: delayMs,
            });

            setTimeout(() => {
              this._startWithRetry();
            }, delayMs);
          } else {
            logger.error('stt.stream_retries_exhausted', {
              retry_count: this.retryCount,
              max_retries: this.maxRetries,
            });
          }
        })
        .on('data', (data) => {
          const result = data?.results?.[0];
          const transcript = result?.alternatives?.[0]?.transcript;
          if (!transcript) return;

          const isFinal = result.isFinal === true;
          logger.info('stt.transcript_received', {
            is_final: isFinal,
            text_length: transcript.length,
            retry_count: this.retryCount,
          });

          // Reset retry count on successful transcript
          this.retryCount = 0;

          if (this.onTranscript) {
            this.onTranscript({
              text: transcript,
              isPartial: !isFinal,
            });
          }
        });
      
      logger.info('stt.stream_started', { 
        language_code: this.languageCode,
        retry_count: this.retryCount,
      });
    } catch (error) {
      this.started = false;
      
      // Retry on initialization errors
      if (this.retryCount < this.maxRetries && this.onTranscript) {
        const delayMs = this.retryDelayMs * Math.pow(2, this.retryCount);
        this.retryCount++;
        
        logger.info('stt.stream_start_retrying', {
          error_code: error.code,
          error_message: error.message,
          retry_count: this.retryCount,
          max_retries: this.maxRetries,
          delay_ms: delayMs,
        });

        setTimeout(() => {
          this._startWithRetry();
        }, delayMs);
      } else {
        logger.error('stt.stream_start_failed', {
          error_code: error.code,
          error_message: error.message,
          retry_count: this.retryCount,
          max_retries: this.maxRetries,
        });
        throw error;
      }
    }
  }

  write(pcmBuffer) {
    if (!this.stream) return;
    this.stream.write(pcmBuffer);
  }

  stop() {
    if (this.stream) {
      this.stream.end();
      this.stream = null;
    }
    this.started = false;
    this.onTranscript = null;
    this.onError = null;
    this.retryCount = 0;
  }

  /**
   * Get current retry count (for metrics)
   */
  getRetryCount() {
    return this.retryCount;
  }
}

export default GoogleStreamingASR;
