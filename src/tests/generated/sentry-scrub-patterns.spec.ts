// src/tests/generated/sentry-scrub-patterns.spec.ts
//
// Tests for the auto-generated Sentry scrub patterns.
// These tests verify that scrubSensitivePath() correctly redacts sensitive
// identifiers from API paths derived from route metadata.
//
// Run:
//   pnpm test src/tests/generated/sentry-scrub-patterns.spec.ts

import { describe, it, expect } from 'vitest';
import {
  scrubSensitivePath,
  SENSITIVE_PATH_PATTERNS,
} from '@/generated/sentry-scrub-patterns';

describe('generated sentry-scrub-patterns', () => {
  describe('SENSITIVE_PATH_PATTERNS', () => {
    it('exports an array of RegExp patterns', () => {
      expect(Array.isArray(SENSITIVE_PATH_PATTERNS)).toBe(true);
      expect(SENSITIVE_PATH_PATTERNS.length).toBeGreaterThan(0);
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern).toBeInstanceOf(RegExp);
      });
    });

    it('contains patterns for v1, v2, and v3 APIs', () => {
      const patternStrings = SENSITIVE_PATH_PATTERNS.map((p) => p.source);
      expect(patternStrings.some((s) => s.includes('api\\/v1'))).toBe(true);
      expect(patternStrings.some((s) => s.includes('api\\/v2'))).toBe(true);
      expect(patternStrings.some((s) => s.includes('api\\/v3'))).toBe(true);
    });
  });

  describe('scrubSensitivePath', () => {
    describe('v1 API paths', () => {
      it('scrubs /api/v1/secret/:key', () => {
        expect(scrubSensitivePath('/api/v1/secret/abc123')).toBe(
          '/api/v1/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v1/metadata/:key', () => {
        expect(scrubSensitivePath('/api/v1/metadata/xyz789')).toBe(
          '/api/v1/metadata/[REDACTED]'
        );
      });

      it('scrubs /api/v1/metadata/:key/burn', () => {
        expect(scrubSensitivePath('/api/v1/metadata/abc123/burn')).toBe(
          '/api/v1/metadata/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v1/private/:key', () => {
        expect(scrubSensitivePath('/api/v1/private/secretkey')).toBe(
          '/api/v1/private/[REDACTED]'
        );
      });

      it('scrubs /api/v1/private/:key/burn', () => {
        expect(scrubSensitivePath('/api/v1/private/secretkey/burn')).toBe(
          '/api/v1/private/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v1/receipt/:key', () => {
        expect(scrubSensitivePath('/api/v1/receipt/receipt123')).toBe(
          '/api/v1/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v1/receipt/:key/burn', () => {
        expect(scrubSensitivePath('/api/v1/receipt/receipt123/burn')).toBe(
          '/api/v1/receipt/[REDACTED]/burn'
        );
      });
    });

    describe('v2 API paths', () => {
      it('scrubs /api/v2/secret/:identifier', () => {
        expect(scrubSensitivePath('/api/v2/secret/identifier123')).toBe(
          '/api/v2/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v2/secret/:identifier/reveal', () => {
        expect(scrubSensitivePath('/api/v2/secret/identifier123/reveal')).toBe(
          '/api/v2/secret/[REDACTED]/reveal'
        );
      });

      it('scrubs /api/v2/secret/:identifier/status', () => {
        expect(scrubSensitivePath('/api/v2/secret/identifier123/status')).toBe(
          '/api/v2/secret/[REDACTED]/status'
        );
      });

      it('scrubs /api/v2/private/:identifier', () => {
        expect(scrubSensitivePath('/api/v2/private/privatekey')).toBe(
          '/api/v2/private/[REDACTED]'
        );
      });

      it('scrubs /api/v2/private/:identifier/burn', () => {
        expect(scrubSensitivePath('/api/v2/private/privatekey/burn')).toBe(
          '/api/v2/private/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v2/receipt/:identifier', () => {
        expect(scrubSensitivePath('/api/v2/receipt/receipt456')).toBe(
          '/api/v2/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v2/receipt/:identifier/burn', () => {
        expect(scrubSensitivePath('/api/v2/receipt/receipt456/burn')).toBe(
          '/api/v2/receipt/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v2/guest/secret/:identifier', () => {
        expect(scrubSensitivePath('/api/v2/guest/secret/guestsecret')).toBe(
          '/api/v2/guest/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v2/guest/secret/:identifier/reveal', () => {
        expect(
          scrubSensitivePath('/api/v2/guest/secret/guestsecret/reveal')
        ).toBe('/api/v2/guest/secret/[REDACTED]/reveal');
      });

      it('scrubs /api/v2/guest/receipt/:identifier', () => {
        expect(scrubSensitivePath('/api/v2/guest/receipt/guestreceipt')).toBe(
          '/api/v2/guest/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v2/guest/receipt/:identifier/burn', () => {
        expect(
          scrubSensitivePath('/api/v2/guest/receipt/guestreceipt/burn')
        ).toBe('/api/v2/guest/receipt/[REDACTED]/burn');
      });
    });

    describe('v3 API paths', () => {
      it('scrubs /api/v3/secret/:identifier', () => {
        expect(scrubSensitivePath('/api/v3/secret/secret789')).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v3/secret/:identifier/reveal', () => {
        expect(scrubSensitivePath('/api/v3/secret/secret789/reveal')).toBe(
          '/api/v3/secret/[REDACTED]/reveal'
        );
      });

      it('scrubs /api/v3/secret/:identifier/status', () => {
        expect(scrubSensitivePath('/api/v3/secret/secret789/status')).toBe(
          '/api/v3/secret/[REDACTED]/status'
        );
      });

      it('scrubs /api/v3/receipt/:identifier', () => {
        expect(scrubSensitivePath('/api/v3/receipt/receipt789')).toBe(
          '/api/v3/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v3/receipt/:identifier/burn', () => {
        expect(scrubSensitivePath('/api/v3/receipt/receipt789/burn')).toBe(
          '/api/v3/receipt/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v3/guest/secret/:identifier', () => {
        expect(scrubSensitivePath('/api/v3/guest/secret/guestsecret3')).toBe(
          '/api/v3/guest/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v3/guest/secret/:identifier/reveal', () => {
        expect(
          scrubSensitivePath('/api/v3/guest/secret/guestsecret3/reveal')
        ).toBe('/api/v3/guest/secret/[REDACTED]/reveal');
      });

      it('scrubs /api/v3/guest/receipt/:identifier', () => {
        expect(scrubSensitivePath('/api/v3/guest/receipt/guestreceipt3')).toBe(
          '/api/v3/guest/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v3/guest/receipt/:identifier/burn', () => {
        expect(
          scrubSensitivePath('/api/v3/guest/receipt/guestreceipt3/burn')
        ).toBe('/api/v3/guest/receipt/[REDACTED]/burn');
      });
    });

    describe('edge cases', () => {
      it('handles empty string', () => {
        expect(scrubSensitivePath('')).toBe('');
      });

      it('leaves non-sensitive paths unchanged', () => {
        expect(scrubSensitivePath('/api/v3/colonel/status')).toBe(
          '/api/v3/colonel/status'
        );
        expect(scrubSensitivePath('/api/health')).toBe('/api/health');
        expect(scrubSensitivePath('/pricing')).toBe('/pricing');
      });

      it('handles full URLs with protocol and host', () => {
        expect(
          scrubSensitivePath('https://example.com/api/v3/secret/abc123')
        ).toBe('https://example.com/api/v3/secret/[REDACTED]');
      });

      it('preserves query strings', () => {
        expect(
          scrubSensitivePath('/api/v3/secret/abc123?timestamp=12345')
        ).toBe('/api/v3/secret/[REDACTED]?timestamp=12345');
      });

      it('handles alphanumeric identifiers', () => {
        expect(scrubSensitivePath('/api/v3/secret/ABC123xyz')).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('handles very long identifiers', () => {
        const longId = 'a'.repeat(100);
        expect(scrubSensitivePath(`/api/v3/secret/${longId}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs alphanumeric prefix before special characters', () => {
        // Generated patterns match [a-zA-Z0-9]+ which stops at special chars
        // So 'abc-123' matches 'abc' and scrubs it, leaving '-123'
        const urlWithDash = '/api/v3/secret/abc-123';
        expect(scrubSensitivePath(urlWithDash)).toBe('/api/v3/secret/[REDACTED]-123');
      });

      it('handles case-insensitive matching', () => {
        expect(scrubSensitivePath('/API/V3/SECRET/abc123')).toBe(
          '/API/V3/SECRET/[REDACTED]'
        );
      });

      it('does not double-scrub already scrubbed paths', () => {
        // If a path already contains [REDACTED], it should not be altered further
        const alreadyScrubbed = '/api/v3/secret/[REDACTED]';
        // The pattern won't match [REDACTED] since it contains brackets
        expect(scrubSensitivePath(alreadyScrubbed)).toBe(alreadyScrubbed);
      });
    });

    describe('multiple occurrences', () => {
      it('scrubs multiple sensitive segments', () => {
        // While unlikely in practice, test that the function handles multiple matches
        const url =
          '/api/v3/secret/abc123?redirect=/api/v2/secret/xyz789';
        expect(scrubSensitivePath(url)).toBe(
          '/api/v3/secret/[REDACTED]?redirect=/api/v2/secret/[REDACTED]'
        );
      });
    });
  });
});
