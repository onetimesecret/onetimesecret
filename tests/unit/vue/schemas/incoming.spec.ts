// schemas/api/incoming.spec.ts

import { describe, expect, it } from 'vitest';
import {
  incomingConfigSchema,
  incomingRecipientSchema,
  incomingSecretPayloadSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';

/**
 * Fixtures modeled after actual V2 API responses from POST /api/v2/incoming/secret.
 * The incoming endpoint returns details.recipient as a string (the recipient hash),
 * not as an array. memo and recipients in metadata are optional strings.
 */

const validMetadata = {
  identifier: 'md:abc123',
  key: 'abc123def456',
  custid: 'anon',
  state: 'new',
  secret_shortkey: 'sk_xyz',
  shortkey: 'shortkey123',
  memo: 'test memo',
  recipients: 'user@example.com',
};

const validSecret = {
  identifier: 'se:abc123',
  key: 'secret-key-456',
  state: 'new',
  shortkey: 'secretshort',
};

const validResponse = {
  success: true,
  shrimp: 'shrimp-token-abc',
  custid: 'anon',
  record: {
    metadata: validMetadata,
    secret: validSecret,
  },
  details: {
    memo: 'test memo',
    recipient: 'abc123hash',
  },
};

describe('incomingRecipientSchema', () => {
  it('accepts a valid recipient', () => {
    const result = incomingRecipientSchema.safeParse({ hash: 'abc123', name: 'Alice' });
    expect(result.success).toBe(true);
  });

  it('rejects empty hash', () => {
    const result = incomingRecipientSchema.safeParse({ hash: '', name: 'Alice' });
    expect(result.success).toBe(false);
  });

  it('rejects missing hash', () => {
    const result = incomingRecipientSchema.safeParse({ name: 'Alice' });
    expect(result.success).toBe(false);
  });

  it('accepts empty name string', () => {
    const result = incomingRecipientSchema.safeParse({ hash: 'abc', name: '' });
    expect(result.success).toBe(true);
  });
});

describe('incomingConfigSchema', () => {
  it('accepts a full config', () => {
    const result = incomingConfigSchema.safeParse({
      enabled: true,
      memo_max_length: 100,
      recipients: [{ hash: 'abc', name: 'Alice' }],
      default_ttl: 3600,
    });
    expect(result.success).toBe(true);
  });

  it('applies defaults for memo_max_length and recipients', () => {
    const result = incomingConfigSchema.safeParse({ enabled: false });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.memo_max_length).toBe(50);
      expect(result.data.recipients).toEqual([]);
    }
  });

  it('rejects non-boolean enabled', () => {
    const result = incomingConfigSchema.safeParse({ enabled: 'yes' });
    expect(result.success).toBe(false);
  });

  it('rejects negative memo_max_length', () => {
    const result = incomingConfigSchema.safeParse({ enabled: true, memo_max_length: -1 });
    expect(result.success).toBe(false);
  });
});

describe('incomingSecretPayloadSchema', () => {
  it('accepts a valid payload with all fields', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      memo: 'a note',
      secret: 'my secret value',
      recipient: 'hash123',
    });
    expect(result.success).toBe(true);
  });

  it('applies default empty string for omitted memo', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      secret: 'my secret',
      recipient: 'hash123',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.memo).toBe('');
    }
  });

  it('rejects empty secret', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      secret: '',
      recipient: 'hash123',
    });
    expect(result.success).toBe(false);
  });

  it('rejects empty recipient', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      secret: 'value',
      recipient: '',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing secret', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      recipient: 'hash123',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing recipient', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      secret: 'value',
    });
    expect(result.success).toBe(false);
  });

  it('rejects non-string secret', () => {
    const result = incomingSecretPayloadSchema.safeParse({
      secret: 12345,
      recipient: 'hash123',
    });
    expect(result.success).toBe(false);
  });
});

describe('incomingSecretResponseSchema', () => {
  it('accepts a complete valid response', () => {
    const result = incomingSecretResponseSchema.safeParse(validResponse);
    expect(result.success).toBe(true);
  });

  describe('metadata optional fields', () => {
    it('accepts undefined (omitted) memo', () => {
      const response = structuredClone(validResponse);
      delete (response.record.metadata as any).memo;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts undefined (omitted) recipients', () => {
      const response = structuredClone(validResponse);
      delete (response.record.metadata as any).recipients;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts empty string for memo and recipients', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.memo = '';
      response.record.metadata.recipients = '';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });
  });

  describe('details.recipient as string (recipient hash)', () => {
    it('accepts a hash string for recipient', () => {
      const response = structuredClone(validResponse);
      response.details!.recipient = 'abc123hash';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts empty string for recipient', () => {
      const response = structuredClone(validResponse);
      response.details!.recipient = '';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('rejects an array for recipient', () => {
      const response = structuredClone(validResponse);
      (response.details as any).recipient = ['a@b.com'];
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });
  });

  describe('optional top-level fields', () => {
    it('accepts response without details', () => {
      const { details, ...rest } = validResponse;
      const result = incomingSecretResponseSchema.safeParse(rest);
      expect(result.success).toBe(true);
    });

    it('accepts response without message, shrimp, custid', () => {
      const result = incomingSecretResponseSchema.safeParse({
        success: true,
        record: validResponse.record,
      });
      expect(result.success).toBe(true);
    });
  });

  describe('required fields rejection', () => {
    it('rejects missing success', () => {
      const { success, ...rest } = validResponse;
      const result = incomingSecretResponseSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects missing record', () => {
      const { record, ...rest } = validResponse;
      const result = incomingSecretResponseSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects missing metadata in record', () => {
      const response = structuredClone(validResponse);
      delete (response.record as any).metadata;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });

    it('rejects missing secret in record', () => {
      const response = structuredClone(validResponse);
      delete (response.record as any).secret;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });

    it('rejects missing required metadata fields (identifier, key, shortkey)', () => {
      const response = structuredClone(validResponse);
      delete (response.record.metadata as any).identifier;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });

    it('rejects non-boolean success', () => {
      const response = structuredClone(validResponse);
      (response as any).success = 'true';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });
  });

  describe('realistic API response', () => {
    it('accepts a response with optional metadata fields omitted (via compact)', () => {
      const result = incomingSecretResponseSchema.safeParse({
        success: true,
        shrimp: 'token',
        custid: 'anon',
        record: {
          metadata: {
            identifier: 'md:1',
            key: 'key1',
            custid: 'anon',
            state: 'new',
            secret_shortkey: 'sk_xyz',
            shortkey: 'sk1',
            // memo and recipients omitted (compacted out when nil)
          },
          secret: {
            identifier: 'se:1',
            key: 'key2',
            state: 'new',
            shortkey: 'sk2',
          },
        },
        details: {
          memo: '',
          recipient: 'abc123hash',
        },
      });
      expect(result.success).toBe(true);
    });
  });
});
