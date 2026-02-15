// schemas/api/incoming.spec.ts

import { describe, expect, it } from 'vitest';
import {
  incomingConfigSchema,
  incomingRecipientSchema,
  incomingSecretPayloadSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';

/**
 * Fixtures modeled after actual V2 API responses.
 * The bugs we caught: secret_shortkey/memo/recipients returned as null
 * from the backend (not undefined), and details.recipient is an array.
 */

const validMetadata = {
  identifier: 'md:abc123',
  key: 'abc123def456',
  custid: 'user@example.com',
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
  custid: 'user@example.com',
  record: {
    metadata: validMetadata,
    secret: validSecret,
  },
  details: {
    kind: 'incoming',
    memo: 'test memo',
    recipient: ['user@example.com'],
    recipient_safe: ['u***@example.com'],
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

  describe('metadata nullish fields (bug fix: backend returns null)', () => {
    it('accepts null for secret_shortkey', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.secret_shortkey = null as any;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts null for memo', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.memo = null as any;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts null for recipients', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.recipients = null as any;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts null for state', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.state = null as any;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts undefined (omitted) for all nullish metadata fields', () => {
      const response = structuredClone(validResponse);
      delete (response.record.metadata as any).secret_shortkey;
      delete (response.record.metadata as any).memo;
      delete (response.record.metadata as any).recipients;
      delete (response.record.metadata as any).state;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts empty string for nullish metadata fields', () => {
      const response = structuredClone(validResponse);
      response.record.metadata.secret_shortkey = '';
      response.record.metadata.memo = '';
      response.record.metadata.recipients = '';
      response.record.metadata.state = '';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });
  });

  describe('secret record nullish fields', () => {
    it('accepts null for secret state', () => {
      const response = structuredClone(validResponse);
      response.record.secret.state = null as any;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });
  });

  describe('details.recipient as array (bug fix: was string, now array)', () => {
    it('accepts an array of email strings', () => {
      const response = structuredClone(validResponse);
      response.details!.recipient = ['a@b.com', 'c@d.com'];
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts an empty array', () => {
      const response = structuredClone(validResponse);
      response.details!.recipient = [];
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts null for recipient', () => {
      const response = structuredClone(validResponse);
      (response.details as any).recipient = null;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts undefined (omitted) for recipient', () => {
      const response = structuredClone(validResponse);
      delete (response.details as any).recipient;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('rejects a plain string for recipient (old incorrect shape)', () => {
      const response = structuredClone(validResponse);
      (response.details as any).recipient = 'user@example.com';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(false);
    });
  });

  describe('details.recipient_safe as array', () => {
    it('accepts null for recipient_safe', () => {
      const response = structuredClone(validResponse);
      (response.details as any).recipient_safe = null;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts an array of masked strings', () => {
      const response = structuredClone(validResponse);
      response.details!.recipient_safe = ['u***@example.com'];
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });
  });

  describe('details.kind field', () => {
    it('accepts kind as a string', () => {
      const response = structuredClone(validResponse);
      response.details!.kind = 'incoming';
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
    });

    it('accepts omitted kind', () => {
      const response = structuredClone(validResponse);
      delete (response.details as any).kind;
      const result = incomingSecretResponseSchema.safeParse(response);
      expect(result.success).toBe(true);
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

  describe('realistic API response with all null optional fields', () => {
    it('accepts a minimal response where backend returns nulls', () => {
      const minimalResponse = {
        success: true,
        shrimp: 'token',
        custid: 'anon',
        record: {
          metadata: {
            identifier: 'md:1',
            key: 'key1',
            custid: 'anon',
            state: null,
            secret_shortkey: null,
            shortkey: 'sk1',
            memo: null,
            recipients: null,
          },
          secret: {
            identifier: 'se:1',
            key: 'key2',
            state: null,
            shortkey: 'sk2',
          },
        },
        details: {
          kind: 'incoming',
          memo: null,
          recipient: null,
          recipient_safe: null,
        },
      };
      const result = incomingSecretResponseSchema.safeParse(minimalResponse);
      expect(result.success).toBe(true);
    });
  });
});
