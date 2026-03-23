// src/schemas/contracts/customer.ts
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
 * - `recipient`: Read-only secret recipient
 * - `user_deleted_self`: Self-deleted account (soft delete)
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
  'recipient',
  'user_deleted_self',
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
  RECIPIENT: 'recipient',
  USER_DELETED_SELF: 'user_deleted_self',
} as const;

/**
 * Zod schema for validating customer role values.
 *
 * @category Contracts
 */
export const customerRoleSchema = z.enum(customerRoleValues);

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
 * if (customer.feature_flags['allow_public_homepage']) {
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

  /** Unique identifier (internal format, used in URLs). */
  identifier: z.string(),

  /** Object ID (internal UUID, primary key). */
  objid: z.string(),

  /** External ID (user-facing, used in public APIs). */
  extid: z.string(),

  /** Email address (unique per customer). */
  email: z.email(),

  // ─────────────────────────────────────────────────────────────────────────
  // Status fields
  // ─────────────────────────────────────────────────────────────────────────

  /** User role determining authorization level. */
  role: customerRoleSchema,

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
