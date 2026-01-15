// Safety Guardrail Loop
// Deterministic layer that scans transcripts for "Red Flags"
// Forces Dialogue Loop to prioritize emergency instructions

import { logger } from './logger.js';

/**
 * Safety Guardrail - Scans transcripts for emergency indicators
 * Returns emergency level and banner message if red flags detected
 */
export class SafetyGuardrail {
  constructor() {
    // Red flag keywords/phrases that indicate emergency
    this.redFlags = {
      critical: [
        'difficulty breathing',
        'can\'t breathe',
        'chest pain',
        'heart attack',
        'stroke',
        'unconscious',
        'severe allergic reaction',
        'anaphylaxis',
        'severe bleeding',
        'severe pain',
      ],
      high: [
        'severe',
        'emergency',
        'urgent',
        'immediate',
        'critical',
        'life threatening',
      ],
    };
  }

  /**
   * Scan transcript for red flags
   * @param {string} transcript - Transcript text to scan
   * @returns {Object|null} Emergency info if red flags found, null otherwise
   */
  scan(transcript) {
    if (!transcript || typeof transcript !== 'string') {
      return null;
    }

    const lowerTranscript = transcript.toLowerCase();

    // Check for critical red flags
    for (const flag of this.redFlags.critical) {
      if (lowerTranscript.includes(flag)) {
        logger.info('safety.critical_red_flag_detected', {
          flag: flag,
          // No transcript content logged (PHI)
        });

        return {
          severity: 'critical',
          banner: 'If you are experiencing severe symptoms, please seek urgent medical care immediately. Call emergency services if needed.',
          interrupt: true, // Force immediate interruption
        };
      }
    }

    // Check for high-priority red flags
    for (const flag of this.redFlags.high) {
      if (lowerTranscript.includes(flag)) {
        logger.info('safety.high_priority_red_flag_detected', {
          flag: flag,
        });

        return {
          severity: 'high',
          banner: 'If you are experiencing severe symptoms, please seek urgent medical care.',
          interrupt: false, // Don't interrupt, but show banner
        };
      }
    }

    return null;
  }

  /**
   * Update red flags (for customization)
   */
  addRedFlag(category, flag) {
    if (this.redFlags[category]) {
      this.redFlags[category].push(flag.toLowerCase());
    }
  }
}

export default SafetyGuardrail;


