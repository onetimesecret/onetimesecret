// src/tests/schemas/api/v1/receipt-response.spec.ts
//
// Validates that the V1 receipt response Zod schema accepts payloads
// matching what the Ruby backend emits from receipt_hsh.
//
// Covers:
//   - v0.23-only payload (legacy clients, pre-#2617)
//   - v0.23 + v0.24 additive payload (post-#2617)
//   - State-dependent field omission (received state, new state)
//   - v1BurnSecretResponseSchema shape
//   - v1SecretRevealResponseSchema shape
//   - Rejection of structurally invalid payloads

import { describe, it, expect } from 'vitest';
import {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
} from '@/schemas/api/v1/responses/secrets';

// -- Fixtures ---------------------------------------------------------------

/** Minimal v0.23 fields only (before #2617 additive mapping). */
function makeV023OnlyPayload(overrides: Record<string, unknown> = {}) {
  return {
    custid: 'user@example.com',
    metadata_key: 'mkey_abc123',
    secret_key: 'skey_xyz789',
    ttl: 3600,
    metadata_ttl: 7000,
    secret_ttl: 3600,
    metadata_url: 'https://example.com/receipt/mkey_abc123',
    state: 'new',
    updated: 1700000000,
    created: 1699999000,
    recipient: ['user@example.com'],
    share_domain: 'example.com',
    // v0.24 additive fields -- required by schema
    identifier: 'mkey_abc123',
    secret_identifier: 'skey_xyz789',
    recipients: ['user@example.com'],
    receipt_ttl: 7000,
    receipt_url: 'https://example.com/receipt/mkey_abc123',
    ...overrides,
  };
}

/** Full v0.23 + v0.24 combined payload (post-#2617). */
function makeFullPayload(overrides: Record<string, unknown> = {}) {
  return {
    ...makeV023OnlyPayload(),
    passphrase_required: false,
    value: 'the secret',
    has_passphrase: false,
    secret_value: 'the secret',
    ...overrides,
  };
}

/** Payload for a receipt in 'received' state (secret_key and secret_ttl removed). */
function makeReceivedPayload(overrides: Record<string, unknown> = {}) {
  return {
    custid: 'user@example.com',
    metadata_key: 'mkey_abc123',
    ttl: 3600,
    metadata_ttl: 7000,
    metadata_url: 'https://example.com/receipt/mkey_abc123',
    state: 'received',
    updated: 1700000000,
    created: 1699999000,
    received: 1700000100,
    recipient: ['user@example.com'],
    share_domain: 'example.com',
    identifier: 'mkey_abc123',
    recipients: ['user@example.com'],
    receipt_ttl: 7000,
    receipt_url: 'https://example.com/receipt/mkey_abc123',
    ...overrides,
  };
}

// -- Tests ------------------------------------------------------------------

describe('v1ReceiptResponseSchema', () => {
  describe('structural validation', () => {
    it('accepts a full v0.23+v0.24 payload for a new receipt', () => {
      const result = v1ReceiptResponseSchema.safeParse(makeFullPayload());
      expect(result.success).toBe(true);
    });

    it('accepts a minimal payload without optional fields', () => {
      // No value, passphrase_required, secret_value, has_passphrase, secret_ttl,
      // secret_key, secret_identifier, received, metadata_url, receipt_url
      const payload = makeV023OnlyPayload({
        secret_key: undefined,
        secret_ttl: undefined,
        metadata_url: undefined,
        secret_identifier: undefined,
        receipt_url: undefined,
      });
      const result = v1ReceiptResponseSchema.safeParse(payload);
      expect(result.success).toBe(true);
    });

    it('accepts a received-state payload (no secret_key, no secret_ttl)', () => {
      const result = v1ReceiptResponseSchema.safeParse(makeReceivedPayload());
      expect(result.success).toBe(true);
    });
  });

  describe('v0.24 additive field consistency (#2617)', () => {
    it('identifier mirrors metadata_key', () => {
      const payload = makeFullPayload();
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.identifier).toBe(parsed.metadata_key);
    });

    it('secret_identifier mirrors secret_key', () => {
      const payload = makeFullPayload();
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.secret_identifier).toBe(parsed.secret_key);
    });

    it('has_passphrase mirrors passphrase_required', () => {
      const payload = makeFullPayload({ passphrase_required: true, has_passphrase: true });
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.has_passphrase).toBe(parsed.passphrase_required);
    });

    it('recipients mirrors recipient', () => {
      const payload = makeFullPayload({ recipient: ['a@b.com', 'c@d.com'], recipients: ['a@b.com', 'c@d.com'] });
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.recipients).toEqual(parsed.recipient);
    });

    it('receipt_ttl mirrors metadata_ttl', () => {
      const payload = makeFullPayload();
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.receipt_ttl).toBe(parsed.metadata_ttl);
    });

    it('receipt_url mirrors metadata_url', () => {
      const payload = makeFullPayload();
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.receipt_url).toBe(parsed.metadata_url);
    });

    it('secret_value mirrors value', () => {
      const payload = makeFullPayload();
      const parsed = v1ReceiptResponseSchema.parse(payload);
      expect(parsed.secret_value).toBe(parsed.value);
    });
  });

  describe('nullable fields', () => {
    it('accepts null ttl', () => {
      const result = v1ReceiptResponseSchema.safeParse(makeFullPayload({ ttl: null }));
      expect(result.success).toBe(true);
    });

    it('accepts null metadata_ttl and receipt_ttl', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ metadata_ttl: null, receipt_ttl: null })
      );
      expect(result.success).toBe(true);
    });

    it('accepts null secret_ttl', () => {
      const result = v1ReceiptResponseSchema.safeParse(makeFullPayload({ secret_ttl: null }));
      expect(result.success).toBe(true);
    });

    it('accepts null metadata_url and receipt_url', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ metadata_url: null, receipt_url: null })
      );
      expect(result.success).toBe(true);
    });

    it('accepts null updated and created', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ updated: null, created: null })
      );
      expect(result.success).toBe(true);
    });
  });

  describe('type enforcement', () => {
    it('rejects non-integer ttl', () => {
      const result = v1ReceiptResponseSchema.safeParse(makeFullPayload({ ttl: 3.5 }));
      expect(result.success).toBe(false);
    });

    it('rejects non-array recipient', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ recipient: 'user@example.com' })
      );
      expect(result.success).toBe(false);
    });

    it('rejects non-array recipients', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ recipients: 'user@example.com' })
      );
      expect(result.success).toBe(false);
    });

    it('rejects non-boolean passphrase_required', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ passphrase_required: 'true' })
      );
      expect(result.success).toBe(false);
    });

    it('rejects non-boolean has_passphrase', () => {
      const result = v1ReceiptResponseSchema.safeParse(
        makeFullPayload({ has_passphrase: 'false' })
      );
      expect(result.success).toBe(false);
    });

    it('rejects missing required field custid', () => {
      const { custid: _, ...payload } = makeFullPayload();
      const result = v1ReceiptResponseSchema.safeParse(payload);
      expect(result.success).toBe(false);
    });

    it('rejects missing required field metadata_key', () => {
      const { metadata_key: _, ...payload } = makeFullPayload();
      const result = v1ReceiptResponseSchema.safeParse(payload);
      expect(result.success).toBe(false);
    });

    it('rejects missing required field identifier', () => {
      const { identifier: _, ...payload } = makeFullPayload();
      const result = v1ReceiptResponseSchema.safeParse(payload);
      expect(result.success).toBe(false);
    });
  });

  describe('V1 state vocabulary', () => {
    const v1States = ['new', 'viewed', 'received', 'burned'];
    v1States.forEach((state) => {
      it(`accepts V1 state "${state}"`, () => {
        const result = v1ReceiptResponseSchema.safeParse(
          makeV023OnlyPayload({ state })
        );
        expect(result.success).toBe(true);
      });
    });
  });
});

describe('v1ReceiptListResponseSchema', () => {
  it('accepts an array of receipts', () => {
    const list = [makeFullPayload(), makeReceivedPayload()];
    const result = v1ReceiptListResponseSchema.safeParse(list);
    expect(result.success).toBe(true);
  });

  it('accepts an empty array', () => {
    const result = v1ReceiptListResponseSchema.safeParse([]);
    expect(result.success).toBe(true);
  });

  it('rejects a non-array', () => {
    const result = v1ReceiptListResponseSchema.safeParse(makeFullPayload());
    expect(result.success).toBe(false);
  });
});

describe('v1SecretRevealResponseSchema', () => {
  it('accepts a valid reveal payload', () => {
    const payload = { value: 'the secret', secret_key: 'skey_xyz', share_domain: 'example.com' };
    const result = v1SecretRevealResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
  });

  it('rejects missing value field', () => {
    const result = v1SecretRevealResponseSchema.safeParse({
      secret_key: 'skey_xyz',
      share_domain: 'example.com',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing secret_key field', () => {
    const result = v1SecretRevealResponseSchema.safeParse({
      value: 'the secret',
      share_domain: 'example.com',
    });
    expect(result.success).toBe(false);
  });
});

describe('v1BurnSecretResponseSchema', () => {
  it('accepts a valid burn response', () => {
    const payload = {
      state: makeFullPayload({ state: 'burned' }),
      secret_shortkey: 'skey_short',
    };
    const result = v1BurnSecretResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
  });

  it('rejects missing secret_shortkey', () => {
    const result = v1BurnSecretResponseSchema.safeParse({
      state: makeFullPayload({ state: 'burned' }),
    });
    expect(result.success).toBe(false);
  });

  it('rejects invalid inner state object', () => {
    const result = v1BurnSecretResponseSchema.safeParse({
      state: { custid: 'test' },
      secret_shortkey: 'skey_short',
    });
    expect(result.success).toBe(false);
  });
});
