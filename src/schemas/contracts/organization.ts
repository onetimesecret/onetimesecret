// src/schemas/contracts/organization.ts
//
// Canonical organization record schema - field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Organization record contracts defining field names and output types.
 *
 * Organizations (workspaces) represent multi-user accounts that can own
 * secrets, domains, and receipts. These canonical schemas define the "what"
 * (field names and final types) without the "how" (wire-format transforms).
 *
 * Version-specific shapes in `shapes/v2/organization.ts` and `shapes/v3/organization.ts`
 * extend these with appropriate transforms for each API version.
 *
 * @module contracts/organization
 * @category Contracts
 * @see {@link "shapes/v2/organization"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/organization"} - V3 wire format with native types
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Organization canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical organization record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * Organization records track:
 * - Identity: identifier, objid (internal UUID), extid (user-facing ID)
 * - Display: display_name, description
 * - Ownership: owner_id (Customer objid)
 * - Contact: contact_email (primary billing/contact)
 * - Status: is_default (auto-created workspace flag), planid
 * - Timestamps: created, updated
 *
 * Note: Relationships (members, domains, receipts) are handled at runtime
 * via Familia v2 participates_in declarations, not stored in the schema.
 *
 * @category Contracts
 * @see {@link "shapes/v2/organization".organizationSchema} - V2 wire format
 * @see {@link "shapes/v3/organization".organizationRecord} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const organizationV3 = organizationCanonical.extend({
 *   created: transforms.fromNumber.toDate,
 *   updated: transforms.fromNumber.toDate,
 * });
 *
 * // Derive TypeScript type
 * type Organization = z.infer<typeof organizationCanonical>;
 * ```
 */
export const organizationCanonical = z.object({
  // ─────────────────────────────────────────────────────────────────────────
  // Identity fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Unique identifier (internal format, used in URLs). */
  identifier: z.string(),

  /** Object ID (internal UUID, primary key). */
  objid: z.string(),

  /** External ID (user-facing, format: on%<id>s). */
  extid: z.string(),

  // ─────────────────────────────────────────────────────────────────────────
  // Display fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Organization display name. */
  display_name: z.string(),

  /** Organization description (optional). */
  description: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────
  // Ownership and contact
  // ─────────────────────────────────────────────────────────────────────────

  /** Owner's Customer objid. */
  owner_id: z.string(),

  /** Primary billing/contact email (optional). */
  contact_email: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────
  // Status fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Whether this is an auto-created default workspace (prevents deletion). */
  is_default: z.boolean(),

  /** Subscription plan ID (defaults to 'free'). */
  planid: z.string(),

  // ─────────────────────────────────────────────────────────────────────────
  // Timestamps
  // ─────────────────────────────────────────────────────────────────────────

  /** Organization creation timestamp. */
  created: z.date(),

  /** Last update timestamp. */
  updated: z.date(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for organization record. */
export type OrganizationCanonical = z.infer<typeof organizationCanonical>;
