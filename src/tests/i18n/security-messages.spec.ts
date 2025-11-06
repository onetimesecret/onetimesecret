/**
 * Security Message Compliance Tests
 *
 * These tests ensure that security-critical authentication error messages
 * follow OWASP/NIST guidelines for preventing information disclosure.
 *
 * Test Categories:
 * 1. Credential-specific information leakage
 * 2. Precise timing information disclosure
 * 3. Attack progress information
 * 4. Generic message validation
 *
 * @see docs/i18n-security-messages.md for complete guidelines
 */

import { describe, it, expect } from 'vitest';
import enMessages from '@/locales/en.json';

describe('Security Message Compliance', () => {
  // Extract security messages from the i18n file
  const securityMessages = enMessages.web.auth.security;

  // Forbidden patterns that should NEVER appear in security messages
  const forbiddenPatterns = {
    credentialSpecific: [
      /password/i,
      /\botp\b/i, // word boundary to avoid matching "adoption"
      /code/i, // This is tricky - we allow "recovery code" but not "invalid code"
      /username/i,
      /email/i,
      /biometric/i,
      /fingerprint/i,
      /face\s*id/i,
      /touch\s*id/i,
    ],
    timingSpecific: [
      /wait\s+\d+\s*(minute|second|hour)/i,
      /locked\s+for\s+\d+/i,
      /try\s+again\s+in\s+\d+/i,
      /\d+\s*(minute|second|hour)s?\s+remaining/i,
    ],
    attackProgress: [
      /\d+\s+attempt/i,
      /\d+\s+remaining/i,
      /\d+\s+tries?\s+left/i,
      /\d+\s+more\s+attempt/i,
    ],
    specificErrors: [
      /incorrect/i,
      /invalid/i,
      /wrong/i,
      /failed\s+to\s+match/i,
      /does\s+not\s+exist/i,
      /not\s+found/i, // Exception: "recovery code not found" is allowed
      /expired/i, // Exception: "session expired" is allowed
    ],
  };

  describe('Authentication Failed Message', () => {
    const message = securityMessages.authentication_failed;

    it('should not reveal which credential failed', () => {
      forbiddenPatterns.credentialSpecific.forEach((pattern) => {
        expect(message).not.toMatch(pattern);
      });
    });

    it('should not contain specific error terms', () => {
      expect(message).not.toMatch(/incorrect/i);
      expect(message).not.toMatch(/invalid/i);
      expect(message).not.toMatch(/wrong/i);
    });

    it('should be generic and helpful', () => {
      expect(message).toContain('Authentication failed');
      expect(message.toLowerCase()).toContain('verify');
      expect(message.toLowerCase()).toContain('credentials');
    });
  });

  describe('Rate Limited Message', () => {
    const message = securityMessages.rate_limited;

    it('should not reveal precise timing information', () => {
      forbiddenPatterns.timingSpecific.forEach((pattern) => {
        expect(message).not.toMatch(pattern);
      });
    });

    it('should not reveal attempt counts', () => {
      forbiddenPatterns.attackProgress.forEach((pattern) => {
        expect(message).not.toMatch(pattern);
      });
    });

    it('should be generic about timing', () => {
      expect(message).toContain('Too many attempts');
      expect(message.toLowerCase()).toContain('later');
      expect(message).not.toMatch(/\d+/); // No numbers at all
    });
  });

  describe('Session Expired Message', () => {
    const message = securityMessages.session_expired;

    it('should be safe to mention session (not credential-specific)', () => {
      expect(message.toLowerCase()).toContain('session');
    });

    it('should not reveal credential information', () => {
      expect(message).not.toMatch(/password/i);
      expect(message).not.toMatch(/otp/i);
      expect(message).not.toMatch(/code/i);
    });

    it('should guide users to re-authenticate', () => {
      expect(message.toLowerCase()).toContain('log in');
    });
  });

  describe('Recovery Code Messages', () => {
    it('recovery_code_not_found should be safely generic', () => {
      const message = securityMessages.recovery_code_not_found;

      // This message IS allowed to mention "recovery code" because
      // the user explicitly selected recovery code authentication
      expect(message.toLowerCase()).toContain('recovery code');

      // But it should NOT reveal whether the code exists
      expect(message).not.toMatch(/does\s+not\s+exist/i);
      expect(message).not.toMatch(/invalid/i);
      expect(message).not.toMatch(/incorrect/i);

      // Should guide user to verify input
      expect(message.toLowerCase()).toContain('verify');
    });

    it('recovery_code_used should explain expected behavior', () => {
      const message = securityMessages.recovery_code_used;

      // Safe to explain recovery codes are single-use
      expect(message.toLowerCase()).toContain('recovery code');
      expect(message.toLowerCase()).toContain('used');
      expect(message.toLowerCase()).toContain('once');
    });
  });

  describe('Network and Internal Errors', () => {
    it('network_error should be generic', () => {
      const message = securityMessages.network_error;

      expect(message.toLowerCase()).toContain('network');
      expect(message).not.toMatch(/timeout/i);
      expect(message).not.toMatch(/\d+\s*ms/i);
    });

    it('internal_error should not reveal system details', () => {
      const message = securityMessages.internal_error;

      expect(message).not.toMatch(/database/i);
      expect(message).not.toMatch(/server/i);
      expect(message).not.toMatch(/exception/i);
      expect(message).not.toMatch(/\bsql\b/i);
      expect(message).not.toMatch(/connection/i);
    });
  });

  describe('All Security Messages - General Compliance', () => {
    // Get all actual message values (exclude metadata keys starting with _)
    const messageKeys = Object.keys(securityMessages).filter((key) => !key.startsWith('_'));
    const messages = messageKeys.map((key) => ({
      key,
      // @ts-ignore - we know these are strings
      message: securityMessages[key as keyof typeof securityMessages],
    }));

    it('should all be strings (not objects or arrays)', () => {
      messages.forEach(({ key, message }) => {
        expect(typeof message).toBe('string');
        expect(message.length).toBeGreaterThan(0);
      });
    });

    it('should not contain HTML or JavaScript', () => {
      messages.forEach(({ key, message }) => {
        expect(message).not.toMatch(/<script/i);
        expect(message).not.toMatch(/<iframe/i);
        expect(message).not.toMatch(/javascript:/i);
        expect(message).not.toMatch(/onerror=/i);
      });
    });

    it('should have proper capitalization and punctuation', () => {
      messages.forEach(({ key, message }) => {
        // Should start with capital letter
        expect(message[0]).toMatch(/[A-Z]/);

        // Should end with period (except for short status messages)
        if (message.length > 20 && !message.includes('?')) {
          expect(message).toMatch(/\.$/);
        }
      });
    });

    it('should be concise (under 150 characters)', () => {
      messages.forEach(({ key, message }) => {
        expect(message.length).toBeLessThan(150);
      });
    });
  });

  describe('Metadata Presence', () => {
    it('should have _README with security warning', () => {
      expect(securityMessages._README).toBeDefined();
      expect(securityMessages._README).toContain('SECURITY-CRITICAL');
      expect(securityMessages._README).toContain('OWASP');
    });

    it('should have _meta with security notes for critical messages', () => {
      expect(securityMessages._meta).toBeDefined();
      expect(securityMessages._meta.authentication_failed).toBeDefined();
      expect(securityMessages._meta.authentication_failed.security_note).toContain(
        'MUST NOT reveal'
      );
      expect(securityMessages._meta.authentication_failed.owasp_ref).toContain('ASVS');
    });

    it('should have _translation_guidelines', () => {
      expect(securityMessages._translation_guidelines).toBeDefined();
      expect(securityMessages._translation_guidelines.DO_NOT_translate_as).toBeInstanceOf(Array);
      expect(securityMessages._translation_guidelines.MUST_translate_as).toBeInstanceOf(Array);
      expect(securityMessages._translation_guidelines.WHY).toBeDefined();
    });

    it('should have _safe_information guidance', () => {
      expect(securityMessages._safe_information).toBeDefined();
      expect(securityMessages._safe_information.format_requirements).toBeDefined();
      expect(securityMessages._safe_information.expected_behavior).toBeDefined();
    });
  });

  describe('Message Consistency', () => {
    it('authentication_failed for 401 and 403 should use same generic message', () => {
      const message = securityMessages.authentication_failed;

      // Should be fully generic - usable for any auth failure
      expect(message).not.toMatch(/password/i);
      expect(message).not.toMatch(/otp/i);
      expect(message).not.toMatch(/recovery/i);
      expect(message).not.toMatch(/biometric/i);

      // Should provide helpful but generic guidance
      expect(message.toLowerCase()).toContain('credentials');
    });

    it('rate_limited should not leak any timing or count information', () => {
      const message = securityMessages.rate_limited;

      // Must not contain ANY numbers
      expect(message).not.toMatch(/\d/);

      // Must not contain time units
      expect(message).not.toMatch(/minute|second|hour|day/i);

      // Must not suggest specific wait times
      expect(message).not.toMatch(/soon|shortly|\d+/i);
    });
  });
});
