// src/tests/schemas/contracts/secretDisplayType.spec.ts
//
// display_type on the secret contract: lenient on read (missing or unknown
// values fall back to plain text so the record still parses), strict on the
// request payload (an unknown type is a client bug, not something to send).

import { concealPayloadSchema } from '@/schemas/api/v3/requests/content/conceal';
import {
  DEFAULT_SECRET_DISPLAY_TYPE,
  SecretDisplayType,
  isValidSecretDisplayType,
  secretDisplayTypeValues,
} from '@/schemas/contracts/secret';
import { secretSchema } from '@/schemas/shapes/v3/secret';
import { describe, expect, it } from 'vitest';

import { mockSecretRecordRaw } from '../../fixtures/receipt.fixture';

describe('secret display_type contract', () => {
  it('knows text and markdown, with text as the default', () => {
    expect(secretDisplayTypeValues).toEqual(['text', 'markdown']);
    expect(DEFAULT_SECRET_DISPLAY_TYPE).toBe(SecretDisplayType.TEXT);
    expect(isValidSecretDisplayType('markdown')).toBe(true);
    expect(isValidSecretDisplayType('httplink')).toBe(false);
  });

  describe('on read (V3 secret shape)', () => {
    it('defaults to text when the backend omits the field', () => {
      const parsed = secretSchema.parse(mockSecretRecordRaw);
      expect(parsed.display_type).toBe('text');
    });

    it('keeps markdown', () => {
      const parsed = secretSchema.parse({ ...mockSecretRecordRaw, display_type: 'markdown' });
      expect(parsed.display_type).toBe('markdown');
    });

    it('falls back to text for a type this client does not know instead of failing the record', () => {
      const result = secretSchema.safeParse({ ...mockSecretRecordRaw, display_type: 'httplink' });
      expect(result.success).toBe(true);
      expect(result.data?.display_type).toBe('text');
    });
  });

  describe('on write (conceal payload)', () => {
    const base = { kind: 'conceal', secret: 'hello', share_domain: '' } as const;

    it('is optional', () => {
      expect(concealPayloadSchema.safeParse(base).success).toBe(true);
    });

    it('accepts markdown', () => {
      const result = concealPayloadSchema.safeParse({ ...base, display_type: 'markdown' });
      expect(result.success).toBe(true);
      expect(result.data?.display_type).toBe('markdown');
    });

    it('rejects an unknown display type', () => {
      expect(concealPayloadSchema.safeParse({ ...base, display_type: 'httplink' }).success).toBe(
        false
      );
    });
  });
});
