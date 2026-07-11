// src/tests/apps/admin/secretSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelSecretReceiptResponseSchema,
  colonelSecretDeleteResponseSchema,
} from '@/schemas/api/internal/responses/colonel-secrets';

/**
 * Zod tripwire (CONTRACT 3) for the two NEW Secrets-screen contracts. These
 * payloads are shaped exactly as the live logic classes emit them — verified
 * against apps/api/colonel/logic/colonel/get_secret_receipt.rb and delete_secret.rb
 * (timestamps as Unix-epoch numbers, obscured owner email, receipt-optional). If
 * a backend response drifts, these fail rather than the drawer silently breaking.
 */

// GetSecretReceipt `success_data`, on the wire (numbers for date fields).
function receiptPayload() {
  return {
    shrimp: '',
    record: {
      secret_id: 'sec_objid',
      shortid: 'sh1',
      state: 'received',
      lifespan: 3600,
      created: 1783378400.12,
      updated: 1783378401,
      expiration: 1783382000,
      age: 172800,
      owner_id: 'ext_owner',
      receipt_id: 'rec_objid',
      has_ciphertext: true,
      ciphertext_length: 512,
    },
    details: {
      metadata: {
        receipt_id: 'rec_objid',
        shortid: 'rh1',
        state: 'viewed',
        secret_ttl: 3600,
        recipients: ['alice@example.com'],
        has_passphrase: true,
        share_domain: 'example.com',
        created: 1783378400,
        secret_expired: false,
      },
      owner: { user_id: 'objid_owner', email: 'a***@e***.com', role: 'customer', verified: true },
    },
  };
}

describe('colonelSecretReceiptResponseSchema (GetSecretReceipt)', () => {
  it('parses the real receipt payload and transforms timestamps to Date', () => {
    const result = colonelSecretReceiptResponseSchema.safeParse(receiptPayload());
    expect(result.success).toBe(true);
    if (!result.success) return;

    expect(result.data.record.created).toBeInstanceOf(Date);
    expect(result.data.record.updated).toBeInstanceOf(Date);
    expect(result.data.record.expiration).toBeInstanceOf(Date);
    expect(result.data.details?.metadata?.created).toBeInstanceOf(Date);
    expect(result.data.details?.owner?.email).toBe('a***@e***.com');
  });

  it('accepts an anonymous secret: null owner, null receipt metadata, null expiration', () => {
    const payload = receiptPayload();
    payload.details.metadata = null as never;
    payload.details.owner = null as never;
    payload.record.owner_id = null as never;
    payload.record.expiration = null as never;
    payload.record.updated = null as never;

    const result = colonelSecretReceiptResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.metadata).toBeNull();
    expect(result.data.details?.owner).toBeNull();
    expect(result.data.record.expiration).toBeNull();
  });

  it('accepts recipients as a plain string (data-drift tolerance)', () => {
    const payload = receiptPayload();
    payload.details.metadata!.recipients = 'alice@example.com' as never;
    expect(colonelSecretReceiptResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('rejects a payload missing has_ciphertext (contract drift)', () => {
    const payload = receiptPayload() as unknown as { record: { has_ciphertext?: boolean } };
    delete payload.record.has_ciphertext;
    expect(colonelSecretReceiptResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('colonelSecretDeleteResponseSchema (DeleteSecret)', () => {
  it('validates the delete ack with an associated receipt', () => {
    const payload = {
      shrimp: '',
      record: {
        deleted: true,
        secret: { secret_id: 'sec_objid', shortid: 'sh1', state: 'received', owner_id: 'ext_owner' },
        metadata: { receipt_id: 'rec_objid', shortid: 'rh1' },
      },
      details: { message: 'Secret and associated receipt deleted successfully' },
    };
    expect(colonelSecretDeleteResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('validates the delete ack when the secret had no receipt (null metadata, anon owner)', () => {
    const payload = {
      shrimp: '',
      record: {
        deleted: true,
        secret: { secret_id: 'sec_objid', shortid: 'sh1', state: 'new', owner_id: null },
        metadata: null,
      },
      details: { message: 'Secret and associated receipt deleted successfully' },
    };
    const result = colonelSecretDeleteResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.deleted).toBe(true);
    expect(result.data.record.metadata).toBeNull();
  });

  it('rejects an ack missing details.message', () => {
    const payload = {
      record: {
        deleted: true,
        secret: { secret_id: 'x', shortid: 'y', state: 'new', owner_id: null },
        metadata: null,
      },
      details: {},
    };
    expect(colonelSecretDeleteResponseSchema.safeParse(payload).success).toBe(false);
  });
});
