// src/tests/schemas/api/incomingSchema.spec.ts

import { describe, expect, it } from 'vitest';

import { incomingSecretResponseSchema } from '@/schemas/api/incoming';

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
