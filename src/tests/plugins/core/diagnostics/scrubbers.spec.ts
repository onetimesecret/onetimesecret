// src/tests/plugins/core/diagnostics/scrubbers.spec.ts
//
// Tests for the scrubbing utilities in the dependency-free scrubbers module.
//
// Run:
//   pnpm test src/tests/plugins/core/diagnostics/scrubbers.spec.ts

import { describe, it, expect } from 'vitest';
import {
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
} from '@/plugins/core/diagnostics/scrubbers';

describe('scrubbers', () => {
  describe('scrubSensitiveStrings', () => {
    it('scrubs email addresses', () => {
      const text = 'User user@example.com reported an error';
      expect(scrubSensitiveStrings(text)).toBe(
        'User [EMAIL REDACTED] reported an error'
      );
    });

    it('scrubs multiple email addresses', () => {
      const text = 'From: alice@example.com To: bob@test.org';
      expect(scrubSensitiveStrings(text)).toBe(
        'From: [EMAIL REDACTED] To: [EMAIL REDACTED]'
      );
    });

    it('scrubs 62-char verifiable IDs', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      const text = `Secret ID: ${id62}`;
      expect(scrubSensitiveStrings(text)).toBe('Secret ID: [REDACTED]');
    });

    it('scrubs sensitive path patterns', () => {
      const text = 'Error at /secret/abc123 endpoint';
      expect(scrubSensitiveStrings(text)).toBe(
        'Error at /secret/[REDACTED] endpoint'
      );
    });

    it('handles null/undefined gracefully', () => {
      expect(scrubSensitiveStrings(null as unknown as string)).toBe(null);
      expect(scrubSensitiveStrings(undefined as unknown as string)).toBe(undefined);
    });

    it('handles empty string', () => {
      expect(scrubSensitiveStrings('')).toBe('');
    });
  });

  describe('scrubUrlWithPatterns', () => {
    it('scrubs sensitive path patterns', () => {
      expect(scrubUrlWithPatterns('/api/v3/secret/abc123')).toBe(
        '/api/v3/secret/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/private/xyz789')).toBe(
        '/api/v3/private/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/receipt/token123')).toBe(
        '/api/v3/receipt/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/incoming/data456')).toBe(
        '/api/v3/incoming/[REDACTED]'
      );
    });

    it('scrubs 62-char verifiable IDs', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      expect(scrubUrlWithPatterns(`/api/v3/unknown/${id62}`)).toBe(
        '/api/v3/unknown/[REDACTED]'
      );
    });

    it('scrubs email addresses in query params', () => {
      expect(scrubUrlWithPatterns('/api/users?email=user@example.com')).toBe(
        '/api/users?email=[EMAIL REDACTED]'
      );
    });

    it('scrubs email addresses in path segments', () => {
      expect(scrubUrlWithPatterns('/api/users/user@example.com/profile')).toBe(
        '/api/users/[EMAIL REDACTED]/profile'
      );
    });

    it('scrubs multiple emails in URL', () => {
      expect(
        scrubUrlWithPatterns('/api/share?from=alice@a.com&to=bob@b.com')
      ).toBe('/api/share?from=[EMAIL REDACTED]&to=[EMAIL REDACTED]');
    });

    it('leaves non-sensitive URLs unchanged', () => {
      expect(scrubUrlWithPatterns('/api/v3/colonel/status')).toBe(
        '/api/v3/colonel/status'
      );
      expect(scrubUrlWithPatterns('/api/health')).toBe('/api/health');
    });

    it('handles null/undefined gracefully', () => {
      expect(scrubUrlWithPatterns(null as unknown as string)).toBe(null);
      expect(scrubUrlWithPatterns(undefined as unknown as string)).toBe(undefined);
    });

    it('handles empty string', () => {
      expect(scrubUrlWithPatterns('')).toBe('');
    });

    it('preserves URL structure while scrubbing', () => {
      const url = 'https://api.example.com/api/v3/secret/abc123?email=test@test.com';
      const scrubbed = scrubUrlWithPatterns(url);
      expect(scrubbed).toBe(
        'https://api.example.com/api/v3/secret/[REDACTED]?email=[EMAIL REDACTED]'
      );
    });
  });

  describe('pattern exports', () => {
    it('exports EMAIL_PATTERN', () => {
      expect(EMAIL_PATTERN).toBeInstanceOf(RegExp);
      expect('test@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('exports SENSITIVE_PATH_PATTERN', () => {
      expect(SENSITIVE_PATH_PATTERN).toBeInstanceOf(RegExp);
    });

    it('exports VERIFIABLE_ID_PATTERN', () => {
      expect(VERIFIABLE_ID_PATTERN).toBeInstanceOf(RegExp);
    });
  });
});
