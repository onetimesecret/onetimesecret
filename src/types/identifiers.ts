// src/types/identifiers.ts

/// <reference types="vite/client" />

/**
 * Opaque Identifier Pattern - Branded Types for ID Safety
 *
 * This module implements TypeScript branded types to enforce compile-time
 * separation between internal IDs (ObjId) and external IDs (ExtId).
 *
 * OWASP Alignment:
 * - ObjId = Direct Object Reference (internal database ID)
 * - ExtId = Indirect Object Reference (opaque, enumeration-resistant)
 *
 * Usage Rules:
 * - Use ObjId for: database ops, Vue :key, store lookups, internal comparisons
 * - Use ExtId for: URLs, API paths, route params, public references
 *
 * @see docs/IDENTIFIER-REVIEW-CHECKLIST.md
 */

import { z } from 'zod';

// =============================================================================
// Branded Type Definitions
// =============================================================================

/**
 * Brand symbols for type discrimination
 * Using unique symbols ensures types are truly incompatible at compile time
 */
declare const ObjIdBrand: unique symbol;
declare const ExtIdBrand: unique symbol;

/**
 * Internal Object ID - Direct Object Reference
 *
 * Used for:
 * - Database operations and internal lookups
 * - Vue component :key bindings
 * - In-memory comparisons and store operations
 * - Logging and debugging
 *
 * NEVER use in URL paths or API endpoints.
 */
export type ObjId = string & { readonly [ObjIdBrand]: never };

/**
 * External ID - Indirect Object Reference (Opaque Identifier)
 *
 * Used for:
 * - URL paths and route parameters
 * - API endpoint paths
 * - Public-facing references
 * - Cross-system identifiers
 *
 * Safe for exposure in browser address bar.
 */
export type ExtId = string & { readonly [ExtIdBrand]: never };

// =============================================================================
// Constructor Functions
// =============================================================================

/**
 * Create an ObjId from a raw string
 *
 * Use at data boundaries where internal IDs are received.
 * The string is cast to ObjId - no validation is performed.
 *
 * @example
 * const id = toObjId(apiResponse.id);
 * store.set(id, data);  // OK
 * router.push(`/entity/${id}`);  // TypeScript error!
 */
export function toObjId(raw: string): ObjId {
  return raw as ObjId;
}

/**
 * Create an ExtId from a raw string
 *
 * Use at data boundaries where external IDs are received (route params, API responses).
 * The string is cast to ExtId - no validation is performed.
 *
 * @example
 * const extid = toExtId(route.params.extid);
 * router.push(`/entity/${extid}`);  // OK
 * database.findById(extid);  // Should use different method
 */
export function toExtId(raw: string): ExtId {
  return raw as ExtId;
}

// =============================================================================
// Type Guards
// =============================================================================

/**
 * ExtId format patterns by entity type
 *
 * Backend Familia models use prefixed external identifiers:
 * - Organization: on%<id>s -> on8a7b9c
 * - CustomDomain: cd%<id>s -> cd4f2e1a
 * - Customer: ur%<id>s -> ur7d9c3b
 */
const EXTID_PREFIXES = {
  organization: 'on',
  domain: 'cd',
  customer: 'ur',
  secret: 'se',
  metadata: 'md',
} as const;

/**
 * Check if a string looks like a valid ExtId
 *
 * Note: This is a heuristic check, not authoritative validation.
 * The backend is the source of truth for ID validity.
 */
export function looksLikeExtId(value: string): boolean {
  if (!value || typeof value !== 'string') return false;

  // Check for known prefixes
  const prefixes = Object.values(EXTID_PREFIXES);
  return prefixes.some((prefix) => value.startsWith(prefix) && value.length > prefix.length);
}

/**
 * Check if a string looks like an internal ObjId (UUID or similar)
 *
 * Internal IDs are typically UUIDs or hex strings without prefixes.
 */
export function looksLikeObjId(value: string): boolean {
  if (!value || typeof value !== 'string') return false;

  // UUID pattern (with or without dashes)
  const uuidPattern = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;

  // Simple hex string (common for Redis-based IDs)
  const hexPattern = /^[0-9a-f]{16,32}$/i;

  return uuidPattern.test(value) || hexPattern.test(value);
}

// =============================================================================
// Path Builders (Compile-Time Safe)
// =============================================================================

/**
 * Supported entity types for path building
 */
type PathEntityType = 'org' | 'secret' | 'domain' | 'customer';

/**
 * Build an entity path for frontend routes
 *
 * Requires ExtId, preventing accidental use of internal IDs in URLs.
 *
 * @example
 * buildEntityPath('org', org.extid)  // '/org/on8a7b9c'
 * buildEntityPath('org', org.id)  // TypeScript error!
 */
export function buildEntityPath(entity: PathEntityType, extid: ExtId): string {
  const basePaths: Record<PathEntityType, string> = {
    org: '/org',
    secret: '/secret',
    domain: '/domains',
    customer: '/customer',
  };

  return `${basePaths[entity]}/${extid}`;
}

/**
 * Build an API path for backend requests
 *
 * Requires ExtId, preventing accidental use of internal IDs in API calls.
 *
 * @example
 * buildApiPath('org', org.extid)  // '/api/organizations/on8a7b9c'
 * buildApiPath('domain', domain.extid)  // '/api/domains/cd4f2e1a'
 */
export function buildApiPath(entity: PathEntityType, extid: ExtId): string {
  const apiPaths: Record<PathEntityType, string> = {
    org: '/api/organizations',
    secret: '/api/secrets',
    domain: '/api/domains',
    customer: '/api/customers',
  };

  return `${apiPaths[entity]}/${extid}`;
}

/**
 * Build an API path with a subresource
 *
 * @example
 * buildApiPathWithAction('org', org.extid, 'members')  // '/api/organizations/on8a7b9c/members'
 * buildApiPathWithAction('domain', domain.extid, 'verify')  // '/api/domains/cd4f2e1a/verify'
 */
export function buildApiPathWithAction(
  entity: PathEntityType,
  extid: ExtId,
  action: string
): string {
  return `${buildApiPath(entity, extid)}/${action}`;
}

// =============================================================================
// Zod Schemas for API Boundaries
// =============================================================================

/**
 * Strict ObjId schema - validates format and brands output
 *
 * Use when you need to ensure the ID is actually an internal ID format.
 * Fails on strings that look like ExtIds.
 */
export const objIdSchema = z
  .string()
  .refine((val) => !looksLikeExtId(val), {
    message: 'Expected internal ID format, got external ID',
  })
  .transform((val) => toObjId(val));

/**
 * Strict ExtId schema - validates format and brands output
 *
 * Use when you need to ensure the ID is actually an external ID format.
 * Fails on strings that look like internal UUIDs.
 */
export const extIdSchema = z
  .string()
  .refine((val) => looksLikeExtId(val), {
    message: 'Expected external ID format (e.g., on8a7b9c)',
  })
  .transform((val) => toExtId(val));

/**
 * Lenient ObjId schema - accepts any string, brands output
 *
 * Use during migration phase when strict validation would break existing code.
 * Accepts any string but outputs branded ObjId type.
 *
 * @migration Phase 1 - will be replaced with strict schema in Phase 3
 */
export const lenientObjIdSchema = z.string().transform((val) => toObjId(val));

/**
 * Lenient ExtId schema - accepts any string, brands output
 *
 * Use during migration phase when strict validation would break existing code.
 * Accepts any string but outputs branded ExtId type.
 *
 * @migration Phase 1 - will be replaced with strict schema in Phase 3
 */
export const lenientExtIdSchema = z.string().transform((val) => toExtId(val));

// =============================================================================
// Type Inference Helpers
// =============================================================================

/**
 * Inferred types from Zod schemas
 */
export type ZodObjId = z.infer<typeof objIdSchema>;
export type ZodExtId = z.infer<typeof extIdSchema>;
export type ZodLenientObjId = z.infer<typeof lenientObjIdSchema>;
export type ZodLenientExtId = z.infer<typeof lenientExtIdSchema>;

// =============================================================================
// Assertion Functions (Development Only)
// =============================================================================

/**
 * Assert that a value is an ExtId at runtime
 *
 * Throws in development mode, use for debugging ID misuse.
 */
export function assertExtId(value: string, context?: string): asserts value is ExtId {
  if (!looksLikeExtId(value)) {
    // Only log/throw in development to avoid exposing ID values in production logs
    if (import.meta.env.DEV) {
      const msg = context
        ? `[${context}] Expected ExtId, got "${value}" which looks like an internal ID`
        : `Expected ExtId, got "${value}"`;
      console.warn(msg);
      throw new Error(msg);
    }
  }
}

/**
 * Assert that a value is NOT being used in a URL context
 *
 * Use to catch potential security issues during development.
 */
export function assertNotInUrl(value: string, urlPattern: string, context?: string): void {
  if (urlPattern.includes(value) && looksLikeObjId(value)) {
    // Only log/throw in development to avoid exposing ID values in production logs
    if (import.meta.env.DEV) {
      const msg = context
        ? `[${context}] Internal ID "${value}" found in URL pattern - use ExtId instead`
        : `Internal ID "${value}" found in URL pattern - use ExtId instead`;
      console.error(msg);
      throw new Error(msg);
    }
  }
}
