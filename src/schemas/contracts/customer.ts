// src/schemas/contracts/customer.ts
// @see src/tests/contracts/customer-schema-contract.spec.ts - Contract tests
//
// Canonical customer record schema - field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Customer record contracts defining field names and output types.
 *
 * Customers represent authenticated users in the system. These canonical
 * schemas define the "what" (field names and final types) without the "how"
 * (wire-format transforms).
 *
 * Version-specific shapes in `shapes/v2/customer.ts` and `shapes/v3/customer.ts`
 * extend these with appropriate transforms for each API version.
 *
 * @module contracts/customer
 * @category Contracts
 * @see {@link "shapes/v2/customer"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/customer"} - V3 wire format with native types
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Role enum and values
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Customer role values as a const tuple.
 *
 * Roles determine authorization level and user status:
 * - `customer`: Standard authenticated user
 * - `colonel`: Administrative/privileged user
 * - `admin`: Administrative user (assignable via `bin/ots customers role`)
 * - `staff`: Staff user (assignable via `bin/ots customers role`)
 * - `recipient`: Read-only secret recipient
 * - `user_deleted_self`: Self-deleted account (soft delete)
 * - `anonymous`: Unauthenticated sentinel (`Customer#anonymous?` backend check)
 *
 * MUST be a superset of the backend's assignable roles —
 * `Auth::Operations::Customers::SetRole::VALID_ROLES` in
 * apps/web/auth/operations/customers/set_role.rb. A backend-writable role
 * missing here broke /account/settings/api for promoted accounts (#4298,
 * FRONTEND-19V): the strict enum failed the whole AccountResponse parse.
 * The sync is enforced by src/tests/contracts/customer-role-contract.spec.ts,
 * which reads VALID_ROLES from the Ruby source.
 *
 * @category Contracts
 * @example
 * ```typescript
 * // Use with Zod enum
 * const roleSchema = z.enum(customerRoleValues);
 *
 * // Type narrowing
 * if (customerRoleValues.includes(value as CustomerRole)) {
 *   // value is CustomerRole
 * }
 * ```
 */
export const customerRoleValues = [
  'customer',
  'colonel',
  'admin',
  'staff',
  'recipient',
  'user_deleted_self',
  'anonymous',
] as const;

export type CustomerRole = (typeof customerRoleValues)[number];

/**
 * Customer role enum object for runtime role checks.
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum()
 *
 * @category Contracts
 * @example
 * ```typescript
 * if (customer.role === CustomerRole.COLONEL) {
 *   // User has admin privileges
 * }
 *
 * // Use in switch statements
 * switch (customer.role) {
 *   case CustomerRole.CUSTOMER:
 *     return 'Standard User';
 *   case CustomerRole.COLONEL:
 *     return 'Administrator';
 *   case CustomerRole.RECIPIENT:
 *     return 'Recipient';
 *   case CustomerRole.USER_DELETED_SELF:
 *     return 'Deleted';
 * }
 * ```
 */
export const CustomerRole = {
  CUSTOMER: 'customer',
  COLONEL: 'colonel',
  ADMIN: 'admin',
  STAFF: 'staff',
  RECIPIENT: 'recipient',
  USER_DELETED_SELF: 'user_deleted_self',
  ANONYMOUS: 'anonymous',
} as const;

/**
 * Zod schema for validating customer role values.
 *
 * Strict — rejects anything outside the enum. Use for inputs the frontend
 * controls (forms, guards). For parsing backend records, use
 * {@link customerRoleResilientSchema} instead.
 *
 * @category Contracts
 */
export const customerRoleSchema = z.enum(customerRoleValues);

/**
 * Resilient role schema for parsing backend records.
 *
 * `.catch('customer')` over the bare enum: `role` is a display/UX field, and
 * an unrecognized value must degrade the role badge, never take down a whole
 * page. Before this, a role outside the enum failed the entire
 * AccountResponse parse and /account/settings/api rendered the error
 * boundary (#4298 / FRONTEND-19V — an account promoted to `admin` via the
 * CLI). The catch also absorbs legacy Redis hashes with a missing/null
 * `role`. Authorization is enforced server-side, so falling back to
 * 'customer' can only under-display, never over-grant.
 *
 * @category Contracts
 */
export const customerRoleResilientSchema = customerRoleSchema.catch('customer');

/**
 * Type guard for runtime customer role validation.
 *
 * @param role - String to validate
 * @returns True if role is a valid CustomerRole value
 *
 * @category Contracts
 * @example
 * ```typescript
 * const userInput = 'colonel';
 * if (isValidCustomerRole(userInput)) {
 *   // userInput is now typed as CustomerRole
 *   console.log(`Valid role: ${userInput}`);
 * }
 * ```
 */
export function isValidCustomerRole(role: string): role is CustomerRole {
  return customerRoleValues.includes(role as CustomerRole);
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature flags
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Feature flags schema for customer-specific feature toggles.
 *
 * Allows any key-value pairs of boolean flags for flexible feature control.
 *
 * @category Contracts
 * @example
 * ```typescript
 * const customer = customerCanonical.parse(apiResponse);
 * if (customer.feature_flags['beta_features']) {
 *   // Feature is enabled for this customer
 * }
 * ```
 */
export const featureFlagsSchema = z.record(z.string(), z.boolean());

export type FeatureFlags = z.infer<typeof featureFlagsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Customer canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical customer record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * Customer records track:
 * - Identity: objid (internal UUID), extid (external user-facing ID), email
 * - Status: role, verified, active
 * - Activity: secrets created/burned/shared, emails sent, last login
 * - Preferences: locale, notify_on_reveal
 * - Feature toggles: feature_flags
 *
 * @category Contracts
 * @see {@link "shapes/v2/customer".customerSchema} - V2 wire format
 * @see {@link "shapes/v3/customer".customerSchema} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const customerV3 = customerCanonical.extend({
 *   created: transforms.fromNumber.toDate,
 *   updated: transforms.fromNumber.toDate,
 * });
 *
 * // Derive TypeScript type
 * type Customer = z.infer<typeof customerCanonical>;
 * ```
 */
export const customerCanonical = z.object({
  // ─────────────────────────────────────────────────────────────────────────
  // Identity fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Object ID (internal UUID, primary key). */
  objid: z.string(),

  /** External ID (user-facing, used in public APIs). */
  extid: z.string(),

  /** Email address (unique per customer). */
  email: z.email(),

  // ─────────────────────────────────────────────────────────────────────────
  // Status fields
  // ─────────────────────────────────────────────────────────────────────────

  /** User role determining authorization level. Unknown values degrade to
   * 'customer' rather than failing the record parse — see
   * customerRoleResilientSchema. */
  role: customerRoleResilientSchema,

  /** Whether email address has been verified. */
  verified: z.boolean(),

  /** Whether account is active (verified + role === customer). */
  active: z.boolean(),

  /** Whether user is a contributor (optional). */
  contributor: z.boolean().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // Activity counters
  // ─────────────────────────────────────────────────────────────────────────

  /** Number of secrets created by this customer. */
  secrets_created: z.number(),

  /** Number of secrets burned (destroyed) by this customer. */
  secrets_burned: z.number(),

  /** Number of secrets shared by this customer. */
  secrets_shared: z.number(),

  /** Number of notification emails sent for this customer. */
  emails_sent: z.number(),

  // ─────────────────────────────────────────────────────────────────────────
  // Timestamps
  // ─────────────────────────────────────────────────────────────────────────

  /** Last login timestamp (null if never logged in). */
  last_login: z.date().nullable(),

  /** Account creation timestamp. */
  created: z.date(),

  /** Last update timestamp. */
  updated: z.date(),

  // ─────────────────────────────────────────────────────────────────────────
  // Preferences
  // ─────────────────────────────────────────────────────────────────────────

  /** User locale preference (e.g., 'en', 'de'). */
  locale: z.string().nullable(),

  /** Whether to notify when a secret is revealed. */
  notify_on_reveal: z.boolean(),

  // ─────────────────────────────────────────────────────────────────────────
  // Feature flags
  // ─────────────────────────────────────────────────────────────────────────

  /** Customer-specific feature toggles. */
  feature_flags: featureFlagsSchema,
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for customer record. */
export type CustomerCanonical = z.infer<typeof customerCanonical>;
