// src/tests/schemas/api/incomingSchema.spec.ts

import { describe, expect, it } from 'vitest';

import {
  incomingConfigSchema,
  incomingSecretPayloadSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';

/** Base receipt fields matching a realistic safe_dump output. */
const baseReceipt = {
  identifier: 'veri:receipt-abc123def456',
  key: 'veri:receipt-abc123def456',
  custid: null,
  owner_id: 'anon',
  state: 'new',
  secret_shortid: 'veri:sec',
  shortid: 'veri:rec',
  memo: 'Test memo',
  recipients: 'test@example.com',
  secret_ttl: 604800,
  receipt_ttl: 604800,
  lifespan: 604800,
  share_domain: null,
  created: 1700000000,
  updated: 1700000000,
  shared: null,
  received: null,
  burned: null,
  viewed: null,
  show_recipients: true,
  is_viewed: false,
  is_received: false,
  is_burned: false,
  is_expired: false,
  is_orphaned: false,
  is_destroyed: false,
  has_passphrase: false,
};

/** Base secret fields matching a realistic safe_dump output. */
const baseSecret = {
  identifier: 'veri:secret-xyz789uvw012',
  key: 'veri:secret-xyz789uvw012',
  state: 'new',
  shortid: 'veri:sec',
  secret_ttl: 604800,
  lifespan: 604800,
  has_passphrase: false,
  verification: false,
  created: 1700000000,
  updated: 1700000000,
};

/** Builds a valid response, applying field-level overrides. */
function buildResponse(overrides: {
  receipt?: Record<string, unknown>;
  secret?: Record<string, unknown>;
  details?: Record<string, unknown> | null;
} = {}) {
  return {
    success: true,
    message: null,
    shrimp: null,
    custid: null,
    record: {
      receipt: { ...baseReceipt, ...overrides.receipt },
      secret: { ...baseSecret, ...overrides.secret },
    },
    details: overrides.details === null
      ? null
      : { memo: 'Test memo', recipient: 'abc123def45678', ...overrides.details },
  };
}

describe('incomingSecretResponseSchema', () => {
  // Bug #2500: V3 safe_dump returns null for unset fields.
  // Schema must tolerate null for state, details.memo, details.recipient.
  describe('Bug #2500: handles null values from safe_dump', () => {
    it('accepts response where receipt state is null', () => {
      const response = buildResponse({ receipt: { state: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where secret state is null', () => {
      const response = buildResponse({ secret: { state: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details memo is null', () => {
      const response = buildResponse({
        details: { memo: null, recipient: 'abc123' },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details recipient is null', () => {
      const response = buildResponse({
        details: { memo: 'test', recipient: null },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details is null', () => {
      const response = buildResponse({ details: null });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where receipt state is undefined (nullish)', () => {
      const response = buildResponse({
        receipt: { state: undefined },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where secret state is undefined (nullish)', () => {
      const response = buildResponse({
        secret: { state: undefined },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts minimal response with most fields null', () => {
      const response = {
        success: true,
        message: null,
        shrimp: null,
        custid: null,
        record: {
          receipt: {
            identifier: 'veri:receipt-abc123def456',
            key: 'veri:receipt-abc123def456',
            custid: null,
            owner_id: null,
            state: null,
            secret_shortid: null,
            shortid: null,
            memo: null,
            recipients: null,
            secret_ttl: null,
            receipt_ttl: null,
            lifespan: null,
            share_domain: null,
            created: null,
            updated: null,
            shared: null,
            received: null,
            burned: null,
            viewed: null,
            show_recipients: null,
            is_viewed: null,
            is_received: null,
            is_burned: null,
            is_expired: null,
            is_orphaned: null,
            is_destroyed: null,
            has_passphrase: null,
          },
          secret: {
            identifier: 'veri:secret-xyz789uvw012',
            key: 'veri:secret-xyz789uvw012',
            state: null,
            shortid: null,
            secret_ttl: null,
            lifespan: null,
            has_passphrase: null,
            verification: null,
            created: null,
            updated: null,
          },
        },
        details: null,
      };
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });
  });

  describe('still rejects truly invalid data', () => {
    it('rejects response missing record entirely', () => {
      expect(() =>
        incomingSecretResponseSchema.parse({ success: true })
      ).toThrow();
    });

    it('rejects response where receipt identifier is null', () => {
      const response = buildResponse({ receipt: { identifier: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where receipt key is null', () => {
      const response = buildResponse({ receipt: { key: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where secret identifier is null', () => {
      const response = buildResponse({ secret: { identifier: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where secret key is null', () => {
      const response = buildResponse({ secret: { key: null } });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });
  });

  describe('accepts fully-populated response', () => {
    it('accepts a complete valid response', () => {
      const response = buildResponse();
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('preserves required fields in parsed output', () => {
      const response = buildResponse();
      const parsed = incomingSecretResponseSchema.parse(response);
      expect(parsed.success).toBe(true);
      expect(parsed.record.receipt.identifier).toBe('veri:receipt-abc123def456');
      expect(parsed.record.secret.identifier).toBe('veri:secret-xyz789uvw012');
    });
  });
});

describe('incomingSecretPayloadSchema', () => {
  describe('memo field', () => {
    it('accepts payload without memo (optional field)', () => {
      const payload = { secret: 'my secret', recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).not.toThrow();
    });

    it('accepts payload with empty memo string', () => {
      const payload = { memo: '', secret: 'my secret', recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).not.toThrow();
    });

    it('accepts payload with a non-empty memo', () => {
      const payload = { memo: 'Password reset', secret: 'my secret', recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).not.toThrow();
    });

    it('defaults memo to empty string when omitted', () => {
      const payload = { secret: 'my secret', recipient: 'abc123hash' };
      const parsed = incomingSecretPayloadSchema.parse(payload);
      expect(parsed.memo).toBe('');
    });

    // XSS note: The schema intentionally passes through raw HTML/script content.
    // Escaping/sanitization is the renderer's responsibility, not the schema's.
    it('accepts memo containing HTML — schema does not sanitize (renderer responsibility)', () => {
      const payload = {
        memo: '<script>alert("xss")</script>',
        secret: 'my secret',
        recipient: 'abc123hash',
      };
      const parsed = incomingSecretPayloadSchema.parse(payload);
      expect(parsed.memo).toBe('<script>alert("xss")</script>');
    });
  });

  describe('secret field', () => {
    it('accepts a valid secret string', () => {
      const payload = { secret: 'actual secret content', recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).not.toThrow();
    });

    it('rejects payload with empty secret', () => {
      const payload = { secret: '', recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).toThrow();
    });

    it('rejects payload missing secret entirely', () => {
      const payload = { recipient: 'abc123hash' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).toThrow();
    });

    // XSS note: The schema intentionally passes through raw HTML/script content.
    // Escaping/sanitization is the renderer's responsibility, not the schema's.
    it('accepts secret containing HTML — schema does not sanitize (renderer responsibility)', () => {
      const payload = {
        secret: '<img src=x onerror=alert(1)>',
        recipient: 'abc123hash',
      };
      const parsed = incomingSecretPayloadSchema.parse(payload);
      expect(parsed.secret).toBe('<img src=x onerror=alert(1)>');
    });
  });

  describe('recipient field', () => {
    it('accepts a valid recipient hash', () => {
      const payload = { secret: 'my secret', recipient: 'abc123def456' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).not.toThrow();
    });

    it('rejects payload with empty recipient', () => {
      const payload = { secret: 'my secret', recipient: '' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).toThrow();
    });

    it('rejects payload missing recipient entirely', () => {
      const payload = { secret: 'my secret' };
      expect(() => incomingSecretPayloadSchema.parse(payload)).toThrow();
    });
  });

  describe('full payload validation', () => {
    it('accepts a complete valid payload', () => {
      const payload = {
        memo: 'Password reset creds',
        secret: 'hunter2',
        recipient: 'abc123def456789a',
      };
      const parsed = incomingSecretPayloadSchema.parse(payload);
      expect(parsed.memo).toBe('Password reset creds');
      expect(parsed.secret).toBe('hunter2');
      expect(parsed.recipient).toBe('abc123def456789a');
    });
  });
});

describe('incomingConfigSchema', () => {
  describe('enabled field', () => {
    it('accepts config with enabled: true', () => {
      const config = { enabled: true, memo_max_length: 50, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).not.toThrow();
    });

    it('accepts config with enabled: false', () => {
      const config = { enabled: false, memo_max_length: 50, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).not.toThrow();
    });

    it('rejects config with non-boolean enabled', () => {
      const config = { enabled: 'yes', memo_max_length: 50, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects config missing enabled', () => {
      const config = { memo_max_length: 50, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });
  });

  describe('memo_max_length field', () => {
    it('accepts a positive integer for memo_max_length', () => {
      const config = { enabled: true, memo_max_length: 100, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).not.toThrow();
    });

    it('defaults memo_max_length to 50 when omitted', () => {
      const config = { enabled: true, recipients: [] };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.memo_max_length).toBe(50);
    });

    it('rejects zero for memo_max_length', () => {
      const config = { enabled: true, memo_max_length: 0, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects negative values for memo_max_length', () => {
      const config = { enabled: true, memo_max_length: -1, recipients: [] };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });
  });

  describe('recipients array', () => {
    it('accepts an empty recipients array', () => {
      const config = { enabled: true, memo_max_length: 50, recipients: [] };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.recipients).toEqual([]);
    });

    it('defaults recipients to empty array when omitted', () => {
      const config = { enabled: true, memo_max_length: 50 };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.recipients).toEqual([]);
    });

    it('accepts recipients with hash and name', () => {
      const config = {
        enabled: true,
        memo_max_length: 50,
        recipients: [
          { hash: 'abc123def456', name: 'Alice' },
          { hash: 'xyz789uvw012', name: 'Bob' },
        ],
      };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.recipients).toHaveLength(2);
      expect(parsed.recipients[0].hash).toBe('abc123def456');
      expect(parsed.recipients[0].name).toBe('Alice');
    });

    it('rejects recipient with empty hash', () => {
      const config = {
        enabled: true,
        memo_max_length: 50,
        recipients: [{ hash: '', name: 'Alice' }],
      };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });

    it('rejects recipient missing hash', () => {
      const config = {
        enabled: true,
        memo_max_length: 50,
        recipients: [{ name: 'Alice' }],
      };
      expect(() => incomingConfigSchema.parse(config)).toThrow();
    });
  });

  describe('default_ttl field', () => {
    it('accepts config without default_ttl (optional)', () => {
      const config = { enabled: true, memo_max_length: 50, recipients: [] };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.default_ttl).toBeUndefined();
    });

    it('accepts config with default_ttl', () => {
      const config = { enabled: true, memo_max_length: 50, recipients: [], default_ttl: 604800 };
      const parsed = incomingConfigSchema.parse(config);
      expect(parsed.default_ttl).toBe(604800);
    });
  });
});
