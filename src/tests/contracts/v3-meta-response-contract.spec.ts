// src/tests/contracts/v3-meta-response-contract.spec.ts
//
// Contract tests for V3 meta endpoint response schemas.
//
// V3 meta endpoints follow pure REST semantics: HTTP status codes indicate
// success/failure, so responses do NOT include a `success` field. This test
// ensures the schema contract is maintained and prevents accidental regression.
//
// Endpoints covered:
// - GET /api/v3/status       -> systemStatusResponseSchema
// - GET /api/v3/version      -> systemVersionResponseSchema
// - GET /api/v3/locales      -> supportedLocalesResponseSchema

import {
  systemStatusResponseSchema,
  systemVersionResponseSchema,
  supportedLocalesResponseSchema,
} from '@/schemas/api/v3/responses/meta';
import { describe, expect, it } from 'vitest';

// ---------------------------------------------------------------------------
// V3 Meta Response Contract Tests
// ---------------------------------------------------------------------------

describe('V3 meta response contracts', () => {
  describe('systemStatusResponseSchema', () => {
    const schemaKeys = Object.keys(systemStatusResponseSchema.shape);

    it('declares expected fields: status, locale', () => {
      expect(schemaKeys).toContain('status');
      expect(schemaKeys).toContain('locale');
    });

    it('does NOT declare a success field (pure REST semantics)', () => {
      expect(schemaKeys).not.toContain('success');
    });

    it('parses a valid status response', () => {
      const payload = {
        status: 'nominal',
        locale: 'en',
      };
      const result = systemStatusResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('rejects payload with success field via strict parsing', () => {
      const payloadWithSuccess = {
        status: 'nominal',
        locale: 'en',
        success: true, // V2 legacy field - should NOT be in V3
      };
      const result = systemStatusResponseSchema.strict().safeParse(payloadWithSuccess);
      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues[0].message).toMatch(/unrecognized/i);
      }
    });
  });

  describe('systemVersionResponseSchema', () => {
    const schemaKeys = Object.keys(systemVersionResponseSchema.shape);

    it('declares expected fields: version, locale', () => {
      expect(schemaKeys).toContain('version');
      expect(schemaKeys).toContain('locale');
    });

    it('does NOT declare a success field (pure REST semantics)', () => {
      expect(schemaKeys).not.toContain('success');
    });

    it('parses a valid version response with string array', () => {
      const payload = {
        version: ['1', '2', '3'],
        locale: 'en',
      };
      const result = systemVersionResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('parses a valid version response with number array', () => {
      const payload = {
        version: [1, 2, 3],
        locale: 'en',
      };
      const result = systemVersionResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('parses a valid version response with mixed array', () => {
      // Ruby VERSION.to_a may return mixed types
      const payload = {
        version: [0, 19, 0, 'beta', 2],
        locale: 'en',
      };
      const result = systemVersionResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('rejects payload with success field via strict parsing', () => {
      const payloadWithSuccess = {
        version: [1, 0, 0],
        locale: 'en',
        success: true,
      };
      const result = systemVersionResponseSchema.strict().safeParse(payloadWithSuccess);
      expect(result.success).toBe(false);
    });
  });

  describe('supportedLocalesResponseSchema', () => {
    const schemaKeys = Object.keys(supportedLocalesResponseSchema.shape);

    it('declares expected fields: locales, default_locale, locale', () => {
      expect(schemaKeys).toContain('locales');
      expect(schemaKeys).toContain('default_locale');
      expect(schemaKeys).toContain('locale');
    });

    it('does NOT declare a success field (pure REST semantics)', () => {
      expect(schemaKeys).not.toContain('success');
    });

    it('parses a valid locales response', () => {
      const payload = {
        locales: ['en', 'es', 'fr', 'de'],
        default_locale: 'en',
        locale: 'en',
      };
      const result = supportedLocalesResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('rejects payload with success field via strict parsing', () => {
      const payloadWithSuccess = {
        locales: ['en'],
        default_locale: 'en',
        locale: 'en',
        success: true,
      };
      const result = supportedLocalesResponseSchema.strict().safeParse(payloadWithSuccess);
      expect(result.success).toBe(false);
    });
  });

  describe('schema field count regression guard', () => {
    // These tests act as a change detector: if someone adds fields to the
    // meta schemas, these tests will fail and prompt review.

    it('systemStatusResponseSchema has exactly 2 fields', () => {
      const fieldCount = Object.keys(systemStatusResponseSchema.shape).length;
      expect(fieldCount).toBe(2);
    });

    it('systemVersionResponseSchema has exactly 2 fields', () => {
      const fieldCount = Object.keys(systemVersionResponseSchema.shape).length;
      expect(fieldCount).toBe(2);
    });

    it('supportedLocalesResponseSchema has exactly 3 fields', () => {
      const fieldCount = Object.keys(supportedLocalesResponseSchema.shape).length;
      expect(fieldCount).toBe(3);
    });
  });
});
