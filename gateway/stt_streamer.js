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
  }

  /**
   * Validate that Speech-to-Text API is accessible
   * @returns {Promise<boolean>} True if API is accessible, false otherwise
   */
  static async validateAPI() {
    try {
      const client = new SpeechClient();
      // Try to list models as a lightweight validation
      // Note: This may require additional permissions, so we catch and continue
      await client.listModels({ pageSize: 1 });
      logger.info('stt.api_validation_passed', {});
      return true;
    } catch (error) {
      // If listModels fails, try a simple instantiation check
      // The API might still work even if listModels requires extra permissions
      if (error.code === 7 || error.code === 'PERMISSION_DENIED') {
        logger.warn('stt.api_validation_partial', {
          error_code: error.code,
          note: 'API may still work - listModels requires extra permissions',
        });
        return true; // Assume API is accessible, just can't list models
      }
      logger.error('stt.api_validation_failed', {
        error_code: error.code,
        error_message: error.message,
      });
      return false;
    }
  }

  start(onTranscript) {
    if (this.started) return;
    this.onTranscript = onTranscript;
    this._startWithRetry();
  }

  /**
   * Start stream with retry logic (exponential backoff)
   */
  _startWithRetry() {
    if (this.started && this.stream) return;
    
    try {
      this.started = true;
      this.retryCount = 0;

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
