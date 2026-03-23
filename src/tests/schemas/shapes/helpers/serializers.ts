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
  ReceiptListCanonical,
  SecretBaseCanonical,
  SecretCanonical,
  SecretWithTimestampsCanonical,
  SecretDetailsCanonical,
} from '@/schemas/contracts';
import type {
  FeedbackCanonical,
  FeedbackDetailsCanonical,
} from '@/schemas/contracts/feedback';
import type { receiptBaseSchema, receiptSchema, receiptDetailsSchema } from '@/schemas/shapes/v2/receipt';
import type { receiptBaseSchema as v3ReceiptBaseSchema, receiptSchema as v3ReceiptSchema, receiptDetailsSchema as v3ReceiptDetailsSchema, receiptListSchema as v3ReceiptListSchema } from '@/schemas/shapes/v3/receipt';
import type { secretResponsesSchema, secretSchema, secretDetailsSchema } from '@/schemas/shapes/v2/secret';
import type { secretBaseSchema as v3SecretBaseSchema, secretSchema as v3SecretSchema, secretDetailsSchema as v3SecretDetailsSchema } from '@/schemas/shapes/v3/secret';
import type { feedbackSchema, feedbackDetailsSchema } from '@/schemas/shapes/v2/feedback';
import type { feedbackSchema as v3FeedbackSchema, feedbackDetailsSchema as v3FeedbackDetailsSchema } from '@/schemas/shapes/v3/feedback';
import type { customerSchema } from '@/schemas/shapes/v2/customer';
import type { CustomerCanonical } from '@/schemas/contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Wire format types (z.input extracts pre-transform types)
// ─────────────────────────────────────────────────────────────────────────────

export type V2WireReceiptBase = z.input<typeof receiptBaseSchema>;
export type V2WireReceipt = z.input<typeof receiptSchema>;
export type V2WireReceiptDetails = z.input<typeof receiptDetailsSchema>;

export type V3WireReceiptBase = z.input<typeof v3ReceiptBaseSchema>;
export type V3WireReceipt = z.input<typeof v3ReceiptSchema>;
export type V3WireReceiptDetails = z.input<typeof v3ReceiptDetailsSchema>;
export type V3WireReceiptList = z.input<typeof v3ReceiptListSchema>;

// Secret wire format types
export type V2WireSecretBase = z.input<typeof secretResponsesSchema>;
export type V2WireSecret = z.input<typeof secretSchema>;
export type V2WireSecretDetails = z.input<typeof secretDetailsSchema>;

export type V3WireSecretBase = z.input<typeof v3SecretBaseSchema>;
export type V3WireSecret = z.input<typeof v3SecretSchema>;
export type V3WireSecretDetails = z.input<typeof v3SecretDetailsSchema>;

// Feedback wire format types
export type V2WireFeedback = z.input<typeof feedbackSchema>;
export type V2WireFeedbackDetails = z.input<typeof feedbackDetailsSchema>;

export type V3WireFeedback = z.input<typeof v3FeedbackSchema>;
export type V3WireFeedbackDetails = z.input<typeof v3FeedbackDetailsSchema>;

// Customer wire format types
export type V2WireCustomer = z.input<typeof customerSchema>;
// V3 customer uses native types (numbers and booleans directly)
export type V3WireCustomer = {
  identifier: string;
  created: number;
  updated: number;
  objid: string;
  extid: string;
  role: 'customer' | 'colonel' | 'recipient' | 'user_deleted_self';
  email: string;
  verified: boolean;
  active: boolean;
  contributor?: boolean;
  secrets_created: number;
  secrets_burned: number;
  secrets_shared: number;
  emails_sent: number;
  last_login: number | null;
  locale: string | null;
  notify_on_reveal: boolean;
  feature_flags: Record<string, boolean | number | string>;
};

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
 * Converts canonical receipt list record to V3 wire format.
 * Extends base with show_recipients field required for list display.
 */
export function toV3WireReceiptListRecord(canonical: ReceiptListCanonical): V3WireReceiptListRecord {
  const base = toV3WireReceiptBase(canonical);
  return {
    ...base,
    show_recipients: canonical.show_recipients,
  } as V3WireReceiptListRecord;
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

// -----------------------------------------------------------------------------
// V2 Wire Format Serializers - Feedback
// -----------------------------------------------------------------------------

/**
 * Converts canonical feedback to V2 wire format.
 *
 * V2 encoding rules for feedback:
 *   - msg: string (1-1500 chars)
 *   - stamp: string (V2 schema expects plain string, no transform)
 *
 * Note: V2 feedbackSchema has stamp as z.string() with no transform,
 * so we serialize the Date to ISO string for the wire format.
 */
export function toV2WireFeedback(canonical: FeedbackCanonical): V2WireFeedback {
  return {
    msg: canonical.msg,
    // V2 expects stamp as string (ISO format)
    stamp: canonical.stamp instanceof Date
      ? canonical.stamp.toISOString()
      : canonical.stamp,
  } as V2WireFeedback;
}

/**
 * Converts canonical feedback details to V2 wire format.
 *
 * V2 encoding rules:
 *   - received: string ("true"/"false") via fromString.boolean.optional()
 */
export function toV2WireFeedbackDetails(canonical: FeedbackDetailsCanonical): V2WireFeedbackDetails {
  return {
    received: canonical.received !== undefined ? booleanToString(canonical.received) : undefined,
  } as V2WireFeedbackDetails;
}

// -----------------------------------------------------------------------------
// V3 Wire Format Serializers - Feedback
// -----------------------------------------------------------------------------

/**
 * Converts canonical feedback to V3 wire format.
 *
 * V3 encoding rules for feedback:
 *   - msg: string (1-1500 chars)
 *   - stamp: number (Unix epoch seconds) via transforms.fromNumber.toDate
 */
export function toV3WireFeedback(canonical: FeedbackCanonical): V3WireFeedback {
  return {
    msg: canonical.msg,
    // V3 expects stamp as Unix epoch seconds (number)
    stamp: canonical.stamp instanceof Date
      ? Math.floor(canonical.stamp.getTime() / 1000)
      : canonical.stamp,
  } as V3WireFeedback;
}

/**
 * Converts canonical feedback details to V3 wire format.
 *
 * V3 uses native boolean (may be null on wire, transforms to false).
 */
export function toV3WireFeedbackDetails(canonical: FeedbackDetailsCanonical): V3WireFeedbackDetails {
  return {
    received: canonical.received,
  } as V3WireFeedbackDetails;
}

// -----------------------------------------------------------------------------
// V2 Wire Format Serializers - Customer
// -----------------------------------------------------------------------------

/**
 * Converts canonical customer to V2 wire format.
 *
 * V2 encoding rules for customer:
 *   - created/updated: string (Unix timestamp) via fromString.date
 *   - last_login: string (Unix timestamp, nullable) via fromString.dateNullable
 *   - booleans: string ("true"/"false") via fromString.boolean
 *   - numbers: string via fromString.number
 *   - feature_flags: Record<string, boolean|number|string> (values transformed)
 */
export function toV2WireCustomer(canonical: CustomerCanonical): V2WireCustomer {
  return {
    identifier: canonical.identifier,
    objid: canonical.objid,
    extid: canonical.extid,
    role: canonical.role,
    email: canonical.email,

    // Timestamps: strings (Unix epoch seconds as string)
    created: numberToString(dateToEpochSeconds(canonical.created)!),
    updated: numberToString(dateToEpochSeconds(canonical.updated)!),
    last_login: canonical.last_login !== null
      ? numberToString(dateToEpochSeconds(canonical.last_login)!)
      : null,

    // Booleans: string
    verified: booleanToString(canonical.verified),
    active: booleanToString(canonical.active),
    contributor: canonical.contributor !== undefined
      ? booleanToString(canonical.contributor)
      : undefined,

    // Counter fields: string
    secrets_created: numberToString(canonical.secrets_created),
    secrets_burned: numberToString(canonical.secrets_burned),
    secrets_shared: numberToString(canonical.secrets_shared),
    emails_sent: numberToString(canonical.emails_sent),

    // Optional string
    locale: canonical.locale,

    // Notification preference: string
    notify_on_reveal: booleanToString(canonical.notify_on_reveal),

    // Feature flags: keep as-is (values may be boolean/number/string on wire)
    feature_flags: canonical.feature_flags,
  } as V2WireCustomer;
}

// -----------------------------------------------------------------------------
// V3 Wire Format Serializers - Customer
// -----------------------------------------------------------------------------

/**
 * Converts canonical customer to V3 wire format.
 *
 * V3 encoding rules for customer:
 *   - timestamps: number (Unix epoch seconds) via fromNumber.toDate
 *   - booleans: native boolean
 *   - numbers: native number
 *   - feature_flags: Record<string, boolean> (native)
 */
export function toV3WireCustomer(canonical: CustomerCanonical): V3WireCustomer {
  return {
    identifier: canonical.identifier,
    objid: canonical.objid,
    extid: canonical.extid,
    role: canonical.role,
    email: canonical.email,

    // Timestamps: numbers
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,
    last_login: dateToEpochSeconds(canonical.last_login),

    // Booleans: native
    verified: canonical.verified,
    active: canonical.active,
    contributor: canonical.contributor,

    // Counter fields: native numbers
    secrets_created: canonical.secrets_created,
    secrets_burned: canonical.secrets_burned,
    secrets_shared: canonical.secrets_shared,
    emails_sent: canonical.emails_sent,

    // Optional string
    locale: canonical.locale,

    // Notification preference: native boolean
    notify_on_reveal: canonical.notify_on_reveal,

    // Feature flags: native types
    feature_flags: canonical.feature_flags,
  } as V3WireCustomer;
}

// -----------------------------------------------------------------------------
// Organization Wire Format Types
// -----------------------------------------------------------------------------

import type { OrganizationCanonical } from '@/schemas/contracts';

/**
 * V2 wire format for Organization.
 *
 * V2 encoding rules:
 *   - created/updated: string (Unix timestamp as string)
 *   - booleans: string ("true"/"false")
 *   - nullable strings: null preserved
 */
export type V2WireOrganization = {
  identifier: string;
  objid: string;
  extid: string;
  display_name: string;
  description: string | null;
  owner_id: string;
  contact_email: string | null;
  is_default: string;
  planid: string;
  created: string;
  updated: string;
};

/**
 * V3 wire format for Organization.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds)
 *   - booleans: native boolean
 *   - nullable strings: null preserved
 */
export type V3WireOrganization = {
  identifier: string;
  objid: string;
  extid: string;
  display_name: string;
  description: string | null;
  owner_id: string;
  contact_email: string | null;
  is_default: boolean;
  planid: string;
  created: number;
  updated: number;
};

// -----------------------------------------------------------------------------
// V2 Wire Format Serializers - Organization
// -----------------------------------------------------------------------------

/**
 * Converts canonical organization to V2 wire format.
 *
 * V2 encoding rules:
 *   - created/updated: string (Unix timestamp) via fromString.date
 *   - booleans: string ("true"/"false") via fromString.boolean
 */
export function toV2WireOrganization(
  canonical: OrganizationCanonical
): V2WireOrganization {
  return {
    identifier: canonical.identifier,
    objid: canonical.objid,
    extid: canonical.extid,
    display_name: canonical.display_name,
    description: canonical.description,
    owner_id: canonical.owner_id,
    contact_email: canonical.contact_email,

    // Boolean: string
    is_default: booleanToString(canonical.is_default),

    // Plan
    planid: canonical.planid,

    // Timestamps: strings (Unix epoch seconds as string)
    created: numberToString(dateToEpochSeconds(canonical.created)!),
    updated: numberToString(dateToEpochSeconds(canonical.updated)!),
  };
}

// -----------------------------------------------------------------------------
// V3 Wire Format Serializers - Organization
// -----------------------------------------------------------------------------

/**
 * Converts canonical organization to V3 wire format.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds)
 *   - booleans: native boolean
 */
export function toV3WireOrganization(
  canonical: OrganizationCanonical
): V3WireOrganization {
  return {
    identifier: canonical.identifier,
    objid: canonical.objid,
    extid: canonical.extid,
    display_name: canonical.display_name,
    description: canonical.description,
    owner_id: canonical.owner_id,
    contact_email: canonical.contact_email,

    // Boolean: native
    is_default: canonical.is_default,

    // Plan
    planid: canonical.planid,

    // Timestamps: numbers
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,
  };
}

// -----------------------------------------------------------------------------
// OrganizationMembership Wire Format Types
// -----------------------------------------------------------------------------

import type { OrganizationMembershipCanonical } from '@/schemas/contracts/organization-membership';

/**
 * V2 wire format for OrganizationMembership.
 *
 * V2 encoding rules:
 *   - timestamps: string (Unix timestamp as ISO string or null)
 *   - booleans: string ("true"/"false")
 *   - numbers: string
 *   - nullable strings: null preserved
 */
export type V2WireOrganizationMembership = {
  id: string;
  organization_id: string | null;
  role: string;
  status: string;
  email: string | null;
  invited_by: string | null;
  invited_at: string | null;
  expires_at: string | null;
  expired: string;
  resend_count: string;
  token: string | null;
};

/**
 * V3 wire format for OrganizationMembership.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds) or null
 *   - booleans: native boolean
 *   - numbers: native number
 *   - nullable strings: null preserved
 */
export type V3WireOrganizationMembership = {
  id: string;
  organization_id: string | null;
  role: string;
  status: string;
  email: string | null;
  invited_by: string | null;
  invited_at: number | null;
  expires_at: number | null;
  expired: boolean;
  resend_count: number;
  token: string | null;
};

// -----------------------------------------------------------------------------
// V2 Wire Format Serializers - OrganizationMembership
// -----------------------------------------------------------------------------

/**
 * Converts canonical organization membership to V2 wire format.
 *
 * V2 encoding rules:
 *   - timestamps: string (ISO format) via dateToISOString
 *   - booleans: string ("true"/"false") via booleanToString
 *   - numbers: string via numberToString
 */
export function toV2WireOrganizationMembership(
  canonical: OrganizationMembershipCanonical
): V2WireOrganizationMembership {
  return {
    id: canonical.id,
    organization_id: canonical.organization_id,
    role: canonical.role,
    status: canonical.status,
    email: canonical.email,
    invited_by: canonical.invited_by,

    // Timestamps: strings (ISO format, nullable)
    invited_at: dateToISOString(canonical.invited_at),
    expires_at: dateToISOString(canonical.expires_at),

    // Boolean: string
    expired: booleanToString(canonical.expired),

    // Number: string
    resend_count: numberToString(canonical.resend_count),

    // Nullable string
    token: canonical.token,
  };
}

// -----------------------------------------------------------------------------
// V3 Wire Format Serializers - OrganizationMembership
// -----------------------------------------------------------------------------

/**
 * Converts canonical organization membership to V3 wire format.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds) via dateToEpochSeconds
 *   - booleans: native boolean
 *   - numbers: native number
 */
export function toV3WireOrganizationMembership(
  canonical: OrganizationMembershipCanonical
): V3WireOrganizationMembership {
  return {
    id: canonical.id,
    organization_id: canonical.organization_id,
    role: canonical.role,
    status: canonical.status,
    email: canonical.email,
    invited_by: canonical.invited_by,

    // Timestamps: numbers (Unix epoch seconds, nullable)
    invited_at: dateToEpochSeconds(canonical.invited_at),
    expires_at: dateToEpochSeconds(canonical.expires_at),

    // Boolean: native
    expired: canonical.expired,

    // Number: native
    resend_count: canonical.resend_count,

    // Nullable string
    token: canonical.token,
  };
}

// -----------------------------------------------------------------------------
// CustomDomain Wire Format Types
// -----------------------------------------------------------------------------

import type {
  CustomDomainCanonical,
  VHostCanonical,
  BrandSettingsCanonical,
} from '../fixtures/custom-domain.fixtures';

/**
 * V2 wire format for VHost nested object.
 * Booleans as strings, dates as strings.
 */
export type V2WireVHost = {
  target_address?: string;
  target_ports?: string;
  target_cname?: string;
  apx_hit?: string;
  has_ssl?: string;
  is_resolving?: string;
  status_message?: string;
  created_at?: string;
  last_monitored_unix?: string;
  ssl_active_from?: string | null;
  ssl_active_until?: string | null;
};

/**
 * V3 wire format for VHost nested object.
 * Native types, dates as numbers.
 */
export type V3WireVHost = {
  target_address?: string;
  target_ports?: string;
  target_cname?: string;
  apx_hit?: boolean;
  has_ssl?: boolean;
  is_resolving?: boolean;
  status_message?: string;
  created_at?: number;
  last_monitored_unix?: number;
  ssl_active_from?: number | null;
  ssl_active_until?: number | null;
};

/**
 * V2 wire format for BrandSettings nested object.
 * Booleans as strings, numbers as strings.
 */
export type V2WireBrandSettings = {
  primary_color?: string;
  colour?: string;
  instructions_pre_reveal?: string | null;
  instructions_reveal?: string | null;
  instructions_post_reveal?: string | null;
  description?: string;
  button_text_light?: string;
  allow_public_homepage?: string;
  allow_public_api?: string;
  font_family?: string;
  corner_style?: string;
  locale?: string;
  default_ttl?: string | null;
  passphrase_required?: string;
  notify_enabled?: string;
};

/**
 * V3 wire format for BrandSettings nested object.
 * Native types.
 */
export type V3WireBrandSettings = {
  primary_color?: string;
  colour?: string;
  instructions_pre_reveal?: string | null;
  instructions_reveal?: string | null;
  instructions_post_reveal?: string | null;
  description?: string;
  button_text_light?: boolean;
  allow_public_homepage?: boolean;
  allow_public_api?: boolean;
  font_family?: string;
  corner_style?: string;
  locale?: string;
  default_ttl?: number | null;
  passphrase_required?: boolean;
  notify_enabled?: boolean;
};

/**
 * V2 wire format for CustomDomain.
 *
 * V2 encoding rules:
 *   - created/updated: string (Unix timestamp as string)
 *   - booleans: string ("true"/"false")
 *   - nullable strings: null preserved
 *   - nested objects: V2 wire format
 */
export type V2WireCustomDomain = {
  identifier: string;
  created: string;
  updated: string;
  domainid: string;
  extid: string;
  custid: string | null;
  display_domain: string;
  base_domain: string;
  subdomain: string | null;
  trd: string | null;
  tld: string;
  sld: string;
  is_apex: string;
  verified: string;
  txt_validation_host: string;
  txt_validation_value: string;
  vhost: V2WireVHost | null;
  brand: V2WireBrandSettings | null;
};

/**
 * V3 wire format for CustomDomain.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds)
 *   - booleans: native boolean
 *   - nullable strings: null preserved
 *   - nested objects: V3 wire format
 */
export type V3WireCustomDomain = {
  identifier: string;
  created: number;
  updated: number;
  domainid: string;
  extid: string;
  custid: string | null;
  display_domain: string;
  base_domain: string;
  subdomain: string | null;
  trd: string | null;
  tld: string;
  sld: string;
  is_apex: boolean;
  verified: boolean;
  txt_validation_host: string;
  txt_validation_value: string;
  vhost: V3WireVHost | null;
  brand: V3WireBrandSettings | null;
};

// -----------------------------------------------------------------------------
// V2 Wire Format Serializers - CustomDomain
// -----------------------------------------------------------------------------

/**
 * Converts canonical VHost to V2 wire format.
 */
function toV2WireVHost(canonical: VHostCanonical): V2WireVHost {
  const result: V2WireVHost = {};

  if (canonical.target_address !== undefined) {
    result.target_address = canonical.target_address;
  }
  if (canonical.target_ports !== undefined) {
    result.target_ports = canonical.target_ports;
  }
  if (canonical.target_cname !== undefined) {
    result.target_cname = canonical.target_cname;
  }
  if (canonical.apx_hit !== undefined) {
    result.apx_hit = booleanToString(canonical.apx_hit);
  }
  if (canonical.has_ssl !== undefined) {
    result.has_ssl = booleanToString(canonical.has_ssl);
  }
  if (canonical.is_resolving !== undefined) {
    result.is_resolving = booleanToString(canonical.is_resolving);
  }
  if (canonical.status_message !== undefined) {
    result.status_message = canonical.status_message;
  }
  if (canonical.created_at !== undefined) {
    result.created_at = canonical.created_at.toISOString();
  }
  if (canonical.last_monitored_unix !== undefined) {
    // V2 schema uses fromNumber.secondsToDate — expects number, not string
    result.last_monitored_unix = dateToEpochSeconds(canonical.last_monitored_unix)!;
  }
  if (canonical.ssl_active_from !== undefined) {
    result.ssl_active_from = canonical.ssl_active_from !== null
      ? canonical.ssl_active_from.toISOString()
      : null;
  }
  if (canonical.ssl_active_until !== undefined) {
    result.ssl_active_until = canonical.ssl_active_until !== null
      ? canonical.ssl_active_until.toISOString()
      : null;
  }

  return result;
}

/**
 * Converts canonical BrandSettings to V2 wire format.
 */
function toV2WireBrandSettings(canonical: BrandSettingsCanonical): V2WireBrandSettings {
  const result: V2WireBrandSettings = {};

  if (canonical.primary_color !== undefined) {
    result.primary_color = canonical.primary_color;
  }
  if (canonical.colour !== undefined) {
    result.colour = canonical.colour;
  }
  if (canonical.instructions_pre_reveal !== undefined) {
    result.instructions_pre_reveal = canonical.instructions_pre_reveal;
  }
  if (canonical.instructions_reveal !== undefined) {
    result.instructions_reveal = canonical.instructions_reveal;
  }
  if (canonical.instructions_post_reveal !== undefined) {
    result.instructions_post_reveal = canonical.instructions_post_reveal;
  }
  if (canonical.description !== undefined) {
    result.description = canonical.description;
  }
  if (canonical.button_text_light !== undefined) {
    result.button_text_light = booleanToString(canonical.button_text_light);
  }
  if (canonical.allow_public_homepage !== undefined) {
    result.allow_public_homepage = booleanToString(canonical.allow_public_homepage);
  }
  if (canonical.allow_public_api !== undefined) {
    result.allow_public_api = booleanToString(canonical.allow_public_api);
  }
  if (canonical.font_family !== undefined) {
    result.font_family = canonical.font_family;
  }
  if (canonical.corner_style !== undefined) {
    result.corner_style = canonical.corner_style;
  }
  if (canonical.locale !== undefined) {
    result.locale = canonical.locale;
  }
  if (canonical.default_ttl !== undefined) {
    result.default_ttl = canonical.default_ttl !== null
      ? numberToString(canonical.default_ttl)
      : null;
  }
  if (canonical.passphrase_required !== undefined) {
    result.passphrase_required = booleanToString(canonical.passphrase_required);
  }
  if (canonical.notify_enabled !== undefined) {
    result.notify_enabled = booleanToString(canonical.notify_enabled);
  }

  return result;
}

/**
 * Converts canonical custom domain to V2 wire format.
 *
 * V2 encoding rules:
 *   - created/updated: string (Unix timestamp) via fromString.date
 *   - booleans: string ("true"/"false") via fromString.boolean
 *   - nested objects: V2 wire format
 */
export function toV2WireCustomDomain(
  canonical: CustomDomainCanonical
): V2WireCustomDomain {
  return {
    identifier: canonical.identifier,
    domainid: canonical.domainid,
    extid: canonical.extid,
    custid: canonical.custid,

    // Domain structure
    display_domain: canonical.display_domain,
    base_domain: canonical.base_domain,
    subdomain: canonical.subdomain,
    trd: canonical.trd,
    tld: canonical.tld,
    sld: canonical.sld,

    // Booleans: string
    is_apex: booleanToString(canonical.is_apex),
    verified: booleanToString(canonical.verified),

    // DNS validation
    txt_validation_host: canonical.txt_validation_host,
    txt_validation_value: canonical.txt_validation_value,

    // Nested objects
    vhost: canonical.vhost !== null ? toV2WireVHost(canonical.vhost) : null,
    brand: canonical.brand !== null ? toV2WireBrandSettings(canonical.brand) : null,

    // Timestamps: strings (Unix epoch seconds as string)
    created: numberToString(dateToEpochSeconds(canonical.created)!),
    updated: numberToString(dateToEpochSeconds(canonical.updated)!),
  };
}

// -----------------------------------------------------------------------------
// V3 Wire Format Serializers - CustomDomain
// -----------------------------------------------------------------------------

/**
 * Converts canonical VHost to V3 wire format.
 */
function toV3WireVHost(canonical: VHostCanonical): V3WireVHost {
  const result: V3WireVHost = {};

  if (canonical.target_address !== undefined) {
    result.target_address = canonical.target_address;
  }
  if (canonical.target_ports !== undefined) {
    result.target_ports = canonical.target_ports;
  }
  if (canonical.target_cname !== undefined) {
    result.target_cname = canonical.target_cname;
  }
  if (canonical.apx_hit !== undefined) {
    result.apx_hit = canonical.apx_hit;
  }
  if (canonical.has_ssl !== undefined) {
    result.has_ssl = canonical.has_ssl;
  }
  if (canonical.is_resolving !== undefined) {
    result.is_resolving = canonical.is_resolving;
  }
  if (canonical.status_message !== undefined) {
    result.status_message = canonical.status_message;
  }
  if (canonical.created_at !== undefined) {
    result.created_at = dateToEpochSeconds(canonical.created_at)!;
  }
  if (canonical.last_monitored_unix !== undefined) {
    result.last_monitored_unix = dateToEpochSeconds(canonical.last_monitored_unix)!;
  }
  if (canonical.ssl_active_from !== undefined) {
    result.ssl_active_from = dateToEpochSeconds(canonical.ssl_active_from);
  }
  if (canonical.ssl_active_until !== undefined) {
    result.ssl_active_until = dateToEpochSeconds(canonical.ssl_active_until);
  }

  return result;
}

/**
 * Converts canonical BrandSettings to V3 wire format.
 */
function toV3WireBrandSettings(canonical: BrandSettingsCanonical): V3WireBrandSettings {
  const result: V3WireBrandSettings = {};

  if (canonical.primary_color !== undefined) {
    result.primary_color = canonical.primary_color;
  }
  if (canonical.colour !== undefined) {
    result.colour = canonical.colour;
  }
  if (canonical.instructions_pre_reveal !== undefined) {
    result.instructions_pre_reveal = canonical.instructions_pre_reveal;
  }
  if (canonical.instructions_reveal !== undefined) {
    result.instructions_reveal = canonical.instructions_reveal;
  }
  if (canonical.instructions_post_reveal !== undefined) {
    result.instructions_post_reveal = canonical.instructions_post_reveal;
  }
  if (canonical.description !== undefined) {
    result.description = canonical.description;
  }
  if (canonical.button_text_light !== undefined) {
    result.button_text_light = canonical.button_text_light;
  }
  if (canonical.allow_public_homepage !== undefined) {
    result.allow_public_homepage = canonical.allow_public_homepage;
  }
  if (canonical.allow_public_api !== undefined) {
    result.allow_public_api = canonical.allow_public_api;
  }
  if (canonical.font_family !== undefined) {
    result.font_family = canonical.font_family;
  }
  if (canonical.corner_style !== undefined) {
    result.corner_style = canonical.corner_style;
  }
  if (canonical.locale !== undefined) {
    result.locale = canonical.locale;
  }
  if (canonical.default_ttl !== undefined) {
    result.default_ttl = canonical.default_ttl;
  }
  if (canonical.passphrase_required !== undefined) {
    result.passphrase_required = canonical.passphrase_required;
  }
  if (canonical.notify_enabled !== undefined) {
    result.notify_enabled = canonical.notify_enabled;
  }

  return result;
}

/**
 * Converts canonical custom domain to V3 wire format.
 *
 * V3 encoding rules:
 *   - timestamps: number (Unix epoch seconds)
 *   - booleans: native boolean
 *   - nested objects: V3 wire format
 */
export function toV3WireCustomDomain(
  canonical: CustomDomainCanonical
): V3WireCustomDomain {
  return {
    identifier: canonical.identifier,
    domainid: canonical.domainid,
    extid: canonical.extid,
    custid: canonical.custid,

    // Domain structure
    display_domain: canonical.display_domain,
    base_domain: canonical.base_domain,
    subdomain: canonical.subdomain,
    trd: canonical.trd,
    tld: canonical.tld,
    sld: canonical.sld,

    // Booleans: native
    is_apex: canonical.is_apex,
    verified: canonical.verified,

    // DNS validation
    txt_validation_host: canonical.txt_validation_host,
    txt_validation_value: canonical.txt_validation_value,

    // Nested objects
    vhost: canonical.vhost !== null ? toV3WireVHost(canonical.vhost) : null,
    brand: canonical.brand !== null ? toV3WireBrandSettings(canonical.brand) : null,

    // Timestamps: numbers
    created: dateToEpochSeconds(canonical.created)!,
    updated: dateToEpochSeconds(canonical.updated)!,
  };
}
