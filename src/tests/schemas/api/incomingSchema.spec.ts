// src/tests/schemas/api/incomingSchema.spec.ts
//
// Tests for incomingSecretResponseSchema covering realistic V3 API
// responses where Familia safe_dump returns null for unset fields.
// Bug #2500: "Invalid data received. Expected string but got null."

import { describe, expect, it } from 'vitest';

import {
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';

/**
 * Creates a fully-populated base response for deep-merge overrides.
 * Models what receipt.safe_dump and secret.safe_dump actually return
 * from the V3 API for a newly created incoming secret.
 */
function createRealisticResponse(overrides: Record<string, unknown> = {}) {
  const base = {
    success: true,
    message: null,
    shrimp: null,
    custid: null,
    record: {
      receipt: {
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
      },
      secret: {
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
      },
    },
    details: {
      memo: 'Test memo',
      recipient: 'abc123def45678',
    },
  };

  // Apply top-level overrides
  const result = { ...base, ...overrides };

  // Apply nested record overrides
  if (overrides.record && typeof overrides.record === 'object') {
    const recordOverrides = overrides.record as Record<string, unknown>;
    result.record = { ...base.record };

    if (recordOverrides.receipt && typeof recordOverrides.receipt === 'object') {
      result.record.receipt = {
        ...base.record.receipt,
        ...(recordOverrides.receipt as Record<string, unknown>),
      };
    }
    if (recordOverrides.secret && typeof recordOverrides.secret === 'object') {
      result.record.secret = {
        ...base.record.secret,
        ...(recordOverrides.secret as Record<string, unknown>),
      };
    }
  }

  // Apply nested details overrides (but allow null)
  if ('details' in overrides && overrides.details !== undefined) {
    if (overrides.details === null) {
      result.details = null as any;
    } else if (typeof overrides.details === 'object') {
      result.details = {
        ...base.details,
        ...(overrides.details as Record<string, unknown>),
      };
    }
  }

  return result;
}

describe('incomingSecretResponseSchema', () => {
  describe('Bug #2500: handles null values from safe_dump', () => {
    it('accepts response where receipt state is null', () => {
      const response = createRealisticResponse({
        record: { receipt: { state: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where secret state is null', () => {
      const response = createRealisticResponse({
        record: { secret: { state: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details memo is null', () => {
      const response = createRealisticResponse({
        details: { memo: null, recipient: 'abc123' },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details recipient is null', () => {
      const response = createRealisticResponse({
        details: { memo: 'test', recipient: null },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('accepts response where details is null', () => {
      // details is already .nullish() in schema — sanity check
      const response = createRealisticResponse({ details: null });
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
      const response = createRealisticResponse({
        record: { receipt: { identifier: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where receipt key is null', () => {
      const response = createRealisticResponse({
        record: { receipt: { key: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where secret identifier is null', () => {
      const response = createRealisticResponse({
        record: { secret: { identifier: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });

    it('rejects response where secret key is null', () => {
      const response = createRealisticResponse({
        record: { secret: { key: null } },
      });
      expect(() => incomingSecretResponseSchema.parse(response)).toThrow();
    });
  });

  describe('accepts fully-populated response', () => {
    it('accepts a complete valid response', () => {
      const response = createRealisticResponse();
      expect(() => incomingSecretResponseSchema.parse(response)).not.toThrow();
    });

    it('preserves required fields in parsed output', () => {
      const response = createRealisticResponse();
      const parsed = incomingSecretResponseSchema.parse(response);
      expect(parsed.success).toBe(true);
      expect(parsed.record.receipt.identifier).toBe('veri:receipt-abc123def456');
      expect(parsed.record.secret.identifier).toBe('veri:secret-xyz789uvw012');
    });
  });
});
