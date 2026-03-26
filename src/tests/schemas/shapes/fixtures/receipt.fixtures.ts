// src/tests/schemas/shapes/fixtures/receipt.fixtures.ts
//
// Receipt test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.

import type {
  ReceiptBaseCanonical,
  ReceiptCanonical,
  ReceiptDetailsCanonical,
  ReceiptListCanonical,
  ReceiptState,
} from '@/schemas/contracts';
import {
  toV2WireReceiptBase,
  toV2WireReceipt,
  toV2WireReceiptDetails,
  toV3WireReceiptBase,
  toV3WireReceipt,
  toV3WireReceiptDetails,
  toV3WireReceiptListRecord,
  type V2WireReceiptBase,
  type V2WireReceipt,
  type V2WireReceiptDetails,
  type V3WireReceiptBase,
  type V3WireReceipt,
  type V3WireReceiptDetails,
  type V3WireReceiptListRecord,
} from '../helpers/serializers';

// ─────────────────────────────────────────────────────────────────────────────
// Constants for round-second timestamps
// ─────────────────────────────────────────────────────────────────────────────

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One hour after base */
const ONE_HOUR_LATER = new Date('2024-01-15T11:00:00.000Z');

/** Two hours after base */
const TWO_HOURS_LATER = new Date('2024-01-15T12:00:00.000Z');

/** One day after base */
const ONE_DAY_LATER = new Date('2024-01-16T10:00:00.000Z');

// ─────────────────────────────────────────────────────────────────────────────
// Canonical Factories
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a canonical receipt base with sensible defaults.
 * All timestamps are round seconds for epoch conversion safety.
 */
export function createCanonicalReceiptBase(
  overrides?: Partial<ReceiptBaseCanonical>
): ReceiptBaseCanonical {
  return {
    identifier: 'r7k9m2x4p1q8',
    key: 'r7k9m2x4p1q8',
    shortid: 'r7k9m2x4',
    state: 'new' as ReceiptState,

    // Ownership
    custid: 'user@example.com',
    owner_id: 'c4st0m3r12ab',

    // Timestamps (round seconds)
    created: BASE_TIMESTAMP,
    updated: BASE_TIMESTAMP,
    shared: null,
    received: null,
    viewed: null,
    previewed: null,
    revealed: null,
    burned: null,

    // TTL fields
    secret_ttl: 3600,
    receipt_ttl: 7200,
    lifespan: 86400,

    // Related secret
    secret_shortid: 's3cr3t12',
    secret_identifier: 's3cr3t123abc',

    // Recipients and sharing
    recipients: ['recipient@example.com'],
    share_domain: 'example.com',

    // Boolean status flags
    has_passphrase: false,
    is_viewed: false,
    is_received: false,
    is_previewed: false,
    is_revealed: false,
    is_burned: false,
    is_destroyed: false,
    is_expired: false,
    is_orphaned: false,

    // Optional metadata
    memo: null,
    kind: 'conceal',

    ...overrides,
  };
}

/**
 * Creates a canonical full receipt with URLs and expiration.
 */
export function createCanonicalReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  const base = createCanonicalReceiptBase(overrides);
  return {
    ...base,
    secret_state: 'new' as ReceiptState,
    natural_expiration: 'in 1 day',
    expiration: ONE_DAY_LATER,
    expiration_in_seconds: 86400,
    share_path: '/secret/abc123',
    burn_path: '/secret/abc123/burn',
    receipt_path: '/receipt/test123abc',
    share_url: 'https://example.com/secret/abc123',
    receipt_url: 'https://example.com/receipt/test123abc',
    burn_url: 'https://example.com/secret/abc123/burn',
    ...overrides,
  };
}

/**
 * Creates canonical receipt details for display metadata.
 */
export function createCanonicalReceiptDetails(
  overrides?: Partial<ReceiptDetailsCanonical>
): ReceiptDetailsCanonical {
  return {
    type: 'record' as const,
    display_lines: 5,
    no_cache: false,
    secret_realttl: 3600,
    view_count: 0,
    has_passphrase: false,
    can_decrypt: true,
    secret_value: null,
    show_secret: true,
    show_secret_link: true,
    show_receipt_link: true,
    show_receipt: true,
    show_recipients: true,
    is_orphaned: false,
    is_expired: false,
    ...overrides,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// State-Specific Factories
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a "shared" state receipt (secret link sent to recipient).
 */
export function createSharedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'shared' as ReceiptState,
    shared: ONE_HOUR_LATER,
    ...overrides,
  });
}

/**
 * Creates a "previewed" state receipt (recipient viewed the confirmation page).
 */
export function createPreviewedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'previewed' as ReceiptState,
    shared: ONE_HOUR_LATER,
    previewed: TWO_HOURS_LATER,
    is_previewed: true,
    // Legacy fields
    viewed: TWO_HOURS_LATER,
    is_viewed: true,
    ...overrides,
  });
}

/**
 * Creates a "revealed" state receipt (secret content was decrypted).
 */
export function createRevealedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'revealed' as ReceiptState,
    shared: ONE_HOUR_LATER,
    previewed: TWO_HOURS_LATER,
    revealed: TWO_HOURS_LATER,
    is_previewed: true,
    is_revealed: true,
    // Legacy fields
    viewed: TWO_HOURS_LATER,
    received: TWO_HOURS_LATER,
    is_viewed: true,
    is_received: true,
    secret_state: 'revealed' as ReceiptState,
    ...overrides,
  });
}

/**
 * Creates a "burned" state receipt (secret was destroyed before reveal).
 */
export function createBurnedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'burned' as ReceiptState,
    burned: ONE_HOUR_LATER,
    is_burned: true,
    is_destroyed: true,
    secret_state: 'burned' as ReceiptState,
    ...overrides,
  });
}

/**
 * Creates an "expired" state receipt (TTL elapsed).
 */
export function createExpiredReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'expired' as ReceiptState,
    is_expired: true,
    is_destroyed: true,
    secret_state: 'expired' as ReceiptState,
    ...overrides,
  });
}

/**
 * Creates an "orphaned" state receipt (associated secret deleted).
 */
export function createOrphanedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    state: 'orphaned' as ReceiptState,
    is_orphaned: true,
    secret_identifier: null,
    secret_state: null,
    ...overrides,
  });
}

/**
 * Creates a receipt with passphrase protection.
 */
export function createPassphraseProtectedReceipt(
  overrides?: Partial<ReceiptCanonical>
): ReceiptCanonical {
  return createCanonicalReceipt({
    has_passphrase: true,
    ...overrides,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire Format Factories (use serializers)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates V2 wire format from canonical.
 */
export function createV2WireReceiptBase(
  canonical?: ReceiptBaseCanonical
): V2WireReceiptBase {
  return toV2WireReceiptBase(canonical ?? createCanonicalReceiptBase());
}

export function createV2WireReceipt(
  canonical?: ReceiptCanonical
): V2WireReceipt {
  return toV2WireReceipt(canonical ?? createCanonicalReceipt());
}

export function createV2WireReceiptDetails(
  canonical?: ReceiptDetailsCanonical
): V2WireReceiptDetails {
  return toV2WireReceiptDetails(canonical ?? createCanonicalReceiptDetails());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireReceiptBase(
  canonical?: ReceiptBaseCanonical
): V3WireReceiptBase {
  return toV3WireReceiptBase(canonical ?? createCanonicalReceiptBase());
}

export function createV3WireReceipt(
  canonical?: ReceiptCanonical
): V3WireReceipt {
  return toV3WireReceipt(canonical ?? createCanonicalReceipt());
}

export function createV3WireReceiptDetails(
  canonical?: ReceiptDetailsCanonical
): V3WireReceiptDetails {
  return toV3WireReceiptDetails(canonical ?? createCanonicalReceiptDetails());
}

/**
 * Creates a canonical receipt list record with show_recipients.
 * Extends base with show_recipients field required for list display.
 */
export function createCanonicalReceiptListRecord(
  overrides?: Partial<ReceiptListCanonical>
): ReceiptListCanonical {
  return {
    ...createCanonicalReceiptBase(overrides),
    show_recipients: true,
    ...overrides,
  };
}

/**
 * Creates V3 wire receipt list record from canonical.
 */
export function createV3WireReceiptListRecord(
  canonical?: ReceiptListCanonical
): V3WireReceiptListRecord {
  return toV3WireReceiptListRecord(canonical ?? createCanonicalReceiptListRecord());
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Harness (for reusable round-trip pattern)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compares two canonical receipt bases for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalReceiptBase(
  a: ReceiptBaseCanonical,
  b: ReceiptBaseCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String/primitive fields
  const primitiveFields = [
    'identifier', 'key', 'shortid', 'state', 'custid', 'owner_id',
    'secret_ttl', 'receipt_ttl', 'lifespan', 'secret_shortid',
    'secret_identifier', 'share_domain', 'has_passphrase',
    'is_viewed', 'is_received', 'is_previewed', 'is_revealed',
    'is_burned', 'is_destroyed', 'is_expired', 'is_orphaned',
    'memo', 'kind',
  ] as const;

  for (const field of primitiveFields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`);
    }
  }

  // Date fields (compare as timestamps)
  const dateFields = [
    'created', 'updated', 'shared', 'received', 'viewed',
    'previewed', 'revealed', 'burned',
  ] as const;

  for (const field of dateFields) {
    const aVal = a[field];
    const bVal = b[field];
    const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
    const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
    if (aTime !== bTime) {
      differences.push(`${field}: ${aTime} !== ${bTime}`);
    }
  }

  // Array fields
  if (JSON.stringify(a.recipients) !== JSON.stringify(b.recipients)) {
    differences.push(`recipients: ${JSON.stringify(a.recipients)} !== ${JSON.stringify(b.recipients)}`);
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

/**
 * Compares two canonical full receipts for equality.
 */
export function compareCanonicalReceipt(
  a: ReceiptCanonical,
  b: ReceiptCanonical
): { equal: boolean; differences: string[] } {
  const baseResult = compareCanonicalReceiptBase(a, b);
  const differences = [...baseResult.differences];

  // Additional full receipt fields
  const additionalFields = [
    'secret_state', 'natural_expiration', 'expiration_in_seconds',
    'share_path', 'burn_path', 'receipt_path',
    'share_url', 'receipt_url', 'burn_url',
  ] as const;

  for (const field of additionalFields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`);
    }
  }

  // Expiration date
  const aExp = a.expiration instanceof Date ? a.expiration.getTime() : a.expiration;
  const bExp = b.expiration instanceof Date ? b.expiration.getTime() : b.expiration;
  if (aExp !== bExp) {
    differences.push(`expiration: ${aExp} !== ${bExp}`);
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
