// src/schemas/shapes/v3/secret.ts
//
// V3 wire-format shapes for secrets.
// Derives from contracts, adding V3-specific timestamp transforms (number → Date).
//
// DEPRECATED FIELD EXCLUSIONS (V3 clean API decision):
// The backend sends deprecated boolean aliases (is_viewed, is_received) for V2
// backward compatibility, but V3 intentionally excludes them:
//
//   Backend sends    | V3 uses (canonical)
//   -----------------+---------------------
//   is_viewed        | is_previewed
//   is_received      | is_revealed
//
// V3 clients should use the canonical field names. The deprecated aliases
// exist only for V2 transition support.
// See: lib/onetime/models/secret/features/safe_dump_fields.rb

import {
  secretBaseCanonical,
  secretCanonical,
  secretDetailsCanonical,
} from '@/schemas/contracts';
import { receiptBaseRecord } from '@/schemas/shapes/v3/receipt';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 secret shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 secret base record.
 *
 * Derives from contract, adds V3 timestamp transforms (number → Date).
 */
export const secretBaseRecord = secretBaseCanonical.extend({
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
});

/**
 * V3 full secret record with TTL fields.
 */
export const secretRecord = secretCanonical.extend({
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
});

/**
 * V3 secret details.
 *
 * Uses contract directly — all fields are native JSON types in V3.
 */
export const secretDetails = secretDetailsCanonical;

/**
 * Combined receipt + secret returned by POST /api/v3/conceal and /api/v3/generate.
 */
export const concealDataRecord = z.object({
  receipt: receiptBaseRecord,
  secret: secretRecord,
  share_domain: z.string().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type SecretBaseRecord = z.infer<typeof secretBaseRecord>;
export type SecretRecord = z.infer<typeof secretRecord>;
export type SecretDetails = z.infer<typeof secretDetails>;
export type ConcealDataRecord = z.infer<typeof concealDataRecord>;
