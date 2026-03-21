// src/tests/schemas/shapes/helpers/serializers.ts
//
// Serialization helpers for round-trip testing.
// Converts canonical (post-parse) data back to wire formats.
//
// Wire format differences:
//   V2 Receipts: created/updated are numbers, other timestamps are strings, booleans/numbers are strings
//   V2 Secrets: created/updated are strings (Unix timestamp), booleans/numbers are strings
//   V3: All timestamps are numbers, types are native

import type { z } from 'zod';
import type {
  ReceiptBaseCanonical,
  ReceiptCanonical,
  ReceiptDetailsCanonical,
  SecretBaseCanonical,
  SecretCanonical,
  SecretWithTimestampsCanonical,
  SecretDetailsCanonical,
} from '@/schemas/contracts';
import type { receiptBaseSchema, receiptSchema, receiptDetailsSchema } from '@/schemas/shapes/v2/receipt';
import type { receiptBaseRecord, receiptRecord, receiptDetails } from '@/schemas/shapes/v3/receipt';
import type { secretResponsesSchema, secretSchema, secretDetailsSchema } from '@/schemas/shapes/v2/secret';
import type { secretBaseRecord, secretRecord, secretDetails } from '@/schemas/shapes/v3/secret';

// ─────────────────────────────────────────────────────────────────────────────
// Wire format types (z.input extracts pre-transform types)
// ─────────────────────────────────────────────────────────────────────────────

export type V2WireReceiptBase = z.input<typeof receiptBaseSchema>;
export type V2WireReceipt = z.input<typeof receiptSchema>;
export type V2WireReceiptDetails = z.input<typeof receiptDetailsSchema>;

export type V3WireReceiptBase = z.input<typeof receiptBaseRecord>;
export type V3WireReceipt = z.input<typeof receiptRecord>;
export type V3WireReceiptDetails = z.input<typeof receiptDetails>;

// Secret wire format types
export type V2WireSecretBase = z.input<typeof secretResponsesSchema>;
export type V2WireSecret = z.input<typeof secretSchema>;
export type V2WireSecretDetails = z.input<typeof secretDetailsSchema>;

export type V3WireSecretBase = z.input<typeof secretBaseRecord>;
export type V3WireSecret = z.input<typeof secretRecord>;
export type V3WireSecretDetails = z.input<typeof secretDetails>;

// ─────────────────────────────────────────────────────────────────────────────
// Utility functions
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts Date to Unix epoch seconds.
 * Returns null for null input.
 */
function dateToEpochSeconds(date: Date | null): number | null {
  if (date === null) return null;
  return Math.floor(date.getTime() / 1000);
}

/**
 * Converts Date to ISO string for V2 string-encoded timestamps.
 * Returns null for null input.
 */
function dateToISOString(date: Date | null): string | null {
  if (date === null) return null;
  return date.toISOString();
}

/**
 * Converts boolean to V2 string format ("true"/"false").
 */
function booleanToString(value: boolean): string {
  return String(value);
}

/**
 * Converts number to V2 string format.
 */
function numberToString(value: number): string {
  return String(value);
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 Wire Format Serializers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts canonical receipt base to V2 wire format.
 *
 * V2 encoding rules:
 *   - created/updated: number (Unix epoch seconds) via fromNumber.secondsToDate
 *   - other timestamps (shared, received, etc.): string (ISO) via fromString.dateNullable
 *   - booleans: string ("true"/"false") via fromString.boolean
 *   - numbers (ttl fields): string via fromString.number
 */
export function toV2WireReceiptBase(canonical: ReceiptBaseCanonical): V2WireReceiptBase {
  return {
    identifier: canonical.identifier,
    key: canonical.key,
    shortid: canonical.shortid,
    state: canonical.state,

    // Ownership
    custid: canonical.custid,
    owner_id: canonical.owner_id,

    // Timestamps: created/updated are NUMBERS, others are STRINGS
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,
    shared: dateToISOString(canonical.shared),
    received: dateToISOString(canonical.received),
    viewed: dateToISOString(canonical.viewed),
    previewed: dateToISOString(canonical.previewed),
    revealed: dateToISOString(canonical.revealed),
    burned: dateToISOString(canonical.burned),

    // TTL fields: string
    secret_ttl: numberToString(canonical.secret_ttl),
    receipt_ttl: numberToString(canonical.receipt_ttl),
    lifespan: numberToString(canonical.lifespan),

    // Related secret
    secret_shortid: canonical.secret_shortid,
    secret_identifier: canonical.secret_identifier,

    // Recipients and sharing
    recipients: canonical.recipients,
    share_domain: canonical.share_domain,

    // Boolean status flags: string
    has_passphrase: canonical.has_passphrase,
    is_viewed: booleanToString(canonical.is_viewed),
    is_received: booleanToString(canonical.is_received),
    is_previewed: canonical.is_previewed !== undefined ? booleanToString(canonical.is_previewed) : undefined,
    is_revealed: canonical.is_revealed !== undefined ? booleanToString(canonical.is_revealed) : undefined,
    is_burned: booleanToString(canonical.is_burned),
    is_destroyed: booleanToString(canonical.is_destroyed),
    is_expired: booleanToString(canonical.is_expired),
    is_orphaned: booleanToString(canonical.is_orphaned),

    // Optional metadata
    memo: canonical.memo,
    kind: canonical.kind,
  } as V2WireReceiptBase;
}

/**
 * Converts canonical full receipt to V2 wire format.
 */
export function toV2WireReceipt(canonical: ReceiptCanonical): V2WireReceipt {
  const base = toV2WireReceiptBase(canonical);
  return {
    ...base,
    secret_state: canonical.secret_state,
    natural_expiration: canonical.natural_expiration,
    expiration: dateToEpochSeconds(canonical.expiration)!,
    expiration_in_seconds: numberToString(canonical.expiration_in_seconds),
    share_path: canonical.share_path,
    burn_path: canonical.burn_path,
    receipt_path: canonical.receipt_path,
    share_url: canonical.share_url,
    receipt_url: canonical.receipt_url,
    burn_url: canonical.burn_url,
  } as V2WireReceipt;
}

/**
 * Converts canonical receipt details to V2 wire format.
 */
export function toV2WireReceiptDetails(canonical: ReceiptDetailsCanonical): V2WireReceiptDetails {
  return {
    type: canonical.type,
    display_lines: numberToString(canonical.display_lines),
    no_cache: booleanToString(canonical.no_cache),
    // secret_realttl is NOT transformed in V2 schema — keeps native number
    secret_realttl: canonical.secret_realttl,
    view_count: canonical.view_count !== null ? numberToString(canonical.view_count) : null,
    has_passphrase: canonical.has_passphrase !== null ? booleanToString(canonical.has_passphrase) : null,
    can_decrypt: canonical.can_decrypt !== null ? booleanToString(canonical.can_decrypt) : null,
    secret_value: canonical.secret_value,
    show_secret: booleanToString(canonical.show_secret),
    show_secret_link: booleanToString(canonical.show_secret_link),
    show_receipt_link: booleanToString(canonical.show_receipt_link),
    show_receipt: booleanToString(canonical.show_receipt),
    show_recipients: booleanToString(canonical.show_recipients),
    is_orphaned: canonical.is_orphaned !== undefined && canonical.is_orphaned !== null
      ? booleanToString(canonical.is_orphaned)
      : canonical.is_orphaned,
    is_expired: canonical.is_expired !== undefined && canonical.is_expired !== null
      ? booleanToString(canonical.is_expired)
      : canonical.is_expired,
  } as V2WireReceiptDetails;
}

// ─────────────────────────────────────────────────────────────────────────────
// V3 Wire Format Serializers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts canonical receipt base to V3 wire format.
 *
 * V3 encoding rules:
 *   - All timestamps: number (Unix epoch seconds) via fromNumber.toDate/toDateNullish
 *   - booleans: native boolean
 *   - numbers: native number
 */
export function toV3WireReceiptBase(canonical: ReceiptBaseCanonical): V3WireReceiptBase {
  return {
    identifier: canonical.identifier,
    key: canonical.key,
    shortid: canonical.shortid,
    state: canonical.state,

    // Ownership
    custid: canonical.custid,
    owner_id: canonical.owner_id,

    // Timestamps: ALL are numbers
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,
    shared: dateToEpochSeconds(canonical.shared),
    received: dateToEpochSeconds(canonical.received),
    viewed: dateToEpochSeconds(canonical.viewed),
    previewed: dateToEpochSeconds(canonical.previewed),
    revealed: dateToEpochSeconds(canonical.revealed),
    burned: dateToEpochSeconds(canonical.burned),

    // TTL fields: native numbers
    secret_ttl: canonical.secret_ttl,
    receipt_ttl: canonical.receipt_ttl,
    lifespan: canonical.lifespan,

    // Related secret
    secret_shortid: canonical.secret_shortid,
    secret_identifier: canonical.secret_identifier,

    // Recipients and sharing
    recipients: canonical.recipients,
    share_domain: canonical.share_domain,

    // Boolean status flags: native booleans
    has_passphrase: canonical.has_passphrase,
    is_viewed: canonical.is_viewed,
    is_received: canonical.is_received,
    is_previewed: canonical.is_previewed,
    is_revealed: canonical.is_revealed,
    is_burned: canonical.is_burned,
    is_destroyed: canonical.is_destroyed,
    is_expired: canonical.is_expired,
    is_orphaned: canonical.is_orphaned,

    // Optional metadata
    memo: canonical.memo,
    kind: canonical.kind,
  } as V3WireReceiptBase;
}

/**
 * Converts canonical full receipt to V3 wire format.
 */
export function toV3WireReceipt(canonical: ReceiptCanonical): V3WireReceipt {
  const base = toV3WireReceiptBase(canonical);
  return {
    ...base,
    secret_state: canonical.secret_state,
    natural_expiration: canonical.natural_expiration,
    expiration: dateToEpochSeconds(canonical.expiration)!,
    expiration_in_seconds: canonical.expiration_in_seconds,
    share_path: canonical.share_path,
    burn_path: canonical.burn_path,
    receipt_path: canonical.receipt_path,
    share_url: canonical.share_url,
    receipt_url: canonical.receipt_url,
    burn_url: canonical.burn_url,
  } as V3WireReceipt;
}

/**
 * Converts canonical receipt details to V3 wire format.
 */
export function toV3WireReceiptDetails(canonical: ReceiptDetailsCanonical): V3WireReceiptDetails {
  return {
    type: canonical.type,
    display_lines: canonical.display_lines,
    no_cache: canonical.no_cache,
    secret_realttl: canonical.secret_realttl,
    view_count: canonical.view_count,
    has_passphrase: canonical.has_passphrase,
    can_decrypt: canonical.can_decrypt,
    secret_value: canonical.secret_value,
    show_secret: canonical.show_secret,
    show_secret_link: canonical.show_secret_link,
    show_receipt_link: canonical.show_receipt_link,
    show_receipt: canonical.show_receipt,
    show_recipients: canonical.show_recipients,
    is_orphaned: canonical.is_orphaned,
    is_expired: canonical.is_expired,
  } as V3WireReceiptDetails;
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 Wire Format Serializers — Secrets
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts canonical secret base to V2 wire format.
 *
 * V2 encoding rules for secrets:
 *   - created/updated: string (Unix timestamp) via fromString.date
 *   - booleans: string ("true"/"false") via fromString.boolean
 *   - Note: V2 secret base includes deprecated is_viewed/is_received aliases
 */
export function toV2WireSecretBase(canonical: SecretBaseCanonical & { created: Date; updated: Date }): V2WireSecretBase {
  return {
    identifier: canonical.identifier,
    key: canonical.key,
    shortid: canonical.shortid,
    state: canonical.state,

    // Timestamps: strings (Unix epoch seconds as string)
    created: numberToString(dateToEpochSeconds(canonical.created)!),
    updated: numberToString(dateToEpochSeconds(canonical.updated)!),

    // Booleans: string
    has_passphrase: booleanToString(canonical.has_passphrase),
    verification: booleanToString(canonical.verification),
    is_previewed: booleanToString(canonical.is_previewed),
    is_revealed: booleanToString(canonical.is_revealed),

    // Deprecated boolean aliases for V2 backward compatibility
    is_viewed: booleanToString(canonical.is_previewed),
    is_received: booleanToString(canonical.is_revealed),

    // Optional
    secret_value: canonical.secret_value,
  } as V2WireSecretBase;
}

/**
 * Converts canonical full secret to V2 wire format.
 *
 * Extends base with TTL fields encoded as strings.
 */
export function toV2WireSecret(canonical: SecretCanonical & { created: Date; updated: Date }): V2WireSecret {
  return {
    identifier: canonical.identifier,
    key: canonical.key,
    shortid: canonical.shortid,
    state: canonical.state,

    // Timestamps: strings (Unix epoch seconds as string)
    created: numberToString(dateToEpochSeconds(canonical.created)!),
    updated: numberToString(dateToEpochSeconds(canonical.updated)!),

    // Booleans: string
    has_passphrase: booleanToString(canonical.has_passphrase),
    verification: booleanToString(canonical.verification),
    is_previewed: booleanToString(canonical.is_previewed),
    is_revealed: booleanToString(canonical.is_revealed),

    // Deprecated boolean aliases for V2 backward compatibility
    is_viewed: booleanToString(canonical.is_previewed),
    is_received: booleanToString(canonical.is_revealed),

    // TTL fields: string
    secret_ttl: numberToString(canonical.secret_ttl),
    lifespan: numberToString(canonical.lifespan),

    // Optional
    secret_value: canonical.secret_value,
  } as V2WireSecret;
}

/**
 * Converts canonical secret details to V2 wire format.
 *
 * V2 encoding rules:
 *   - booleans: string ("true"/"false")
 *   - numbers: string
 *   - one_liner: nullable boolean as string
 */
export function toV2WireSecretDetails(canonical: SecretDetailsCanonical): V2WireSecretDetails {
  return {
    continue: booleanToString(canonical.continue),
    is_owner: booleanToString(canonical.is_owner),
    show_secret: booleanToString(canonical.show_secret),
    correct_passphrase: booleanToString(canonical.correct_passphrase),
    display_lines: numberToString(canonical.display_lines),
    one_liner: canonical.one_liner !== null ? booleanToString(canonical.one_liner) : null,
  } as V2WireSecretDetails;
}

// ─────────────────────────────────────────────────────────────────────────────
// V3 Wire Format Serializers — Secrets
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts canonical secret base to V3 wire format.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds) via fromNumber.toDate
 *   - booleans: native boolean
 *   - numbers: native number
 */
export function toV3WireSecretBase(canonical: SecretWithTimestampsCanonical): V3WireSecretBase {
  return {
    identifier: canonical.identifier,
    key: canonical.key,
    shortid: canonical.shortid,
    state: canonical.state,

    // Timestamps: numbers
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,

    // Booleans: native
    has_passphrase: canonical.has_passphrase,
    verification: canonical.verification,
    is_previewed: canonical.is_previewed,
    is_revealed: canonical.is_revealed,

    // TTL fields: native numbers
    secret_ttl: canonical.secret_ttl,
    lifespan: canonical.lifespan,

    // Optional
    secret_value: canonical.secret_value,
  } as V3WireSecretBase;
}

/**
 * Converts canonical full secret to V3 wire format.
 *
 * Same as V3 base for secrets (they share the same structure).
 */
export function toV3WireSecret(canonical: SecretWithTimestampsCanonical): V3WireSecret {
  return toV3WireSecretBase(canonical) as V3WireSecret;
}

/**
 * Converts canonical secret details to V3 wire format.
 *
 * V3 uses native types — no transformation needed.
 */
export function toV3WireSecretDetails(canonical: SecretDetailsCanonical): V3WireSecretDetails {
  return {
    continue: canonical.continue,
    is_owner: canonical.is_owner,
    show_secret: canonical.show_secret,
    correct_passphrase: canonical.correct_passphrase,
    display_lines: canonical.display_lines,
    one_liner: canonical.one_liner,
  } as V3WireSecretDetails;
}
