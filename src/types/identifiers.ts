// src/types/identifiers.ts

/**
 * Branded Types for Opaque Identifiers
 *
 * This module provides compile-time safety to prevent mixing internal IDs (ObjId)
 * with external IDs (ExtId). These branded types catch bugs at compile time where
 * internal database IDs might accidentally be used in URLs or vice versa.
 *
 * Background:
 * - ObjId: Internal database identifier (e.g., "customer:abc123def456")
 *   Used for internal lookups, Redis keys, and database operations.
 *
 * - ExtId: External URL-safe identifier (e.g., "on7k2mxvbs3")
 *   Used in URLs, API endpoints, and client-facing references.
 *
 * Usage:
 * ```typescript
 * // Type-safe function signatures
 * function fetchOrganization(extid: ExtId): Promise<Organization>
 * function lookupByInternalId(id: ObjId): Organization | undefined
 *
 * // Converting from raw strings (API responses, route params)
 * const extid = toExtId(route.params.extid as string);
 * const objid = toObjId(response.data.id);
 *
 * // Compile-time errors prevent misuse
 * fetchOrganization(org.id);     // Error: ObjId not assignable to ExtId
 * lookupByInternalId(org.extid); // Error: ExtId not assignable to ObjId
 * ```
 *
 * @see MIGRATION.md for adoption strategy
 */

import { z } from 'zod';

// ============================================================================
// Branded Type Declarations
// ============================================================================

/**
 * Brand symbols for compile-time type discrimination.
 * These are never used at runtime; they exist only for TypeScript's type system.
 */
declare const ObjIdBrand: unique symbol;
declare const ExtIdBrand: unique symbol;

/**
 * Internal database identifier (opaque).
 *
 * Format: Typically "prefix:identifier" (e.g., "customer:abc123def456")
 * Use: Redis keys, internal lookups, database operations
 * Never: URLs, API paths, client-facing references
 */
export type ObjId = string & { readonly [ObjIdBrand]: never };

/**
 * External URL-safe identifier (opaque).
 *
 * Format: URL-safe string, often base36 (e.g., "on7k2mxvbs3")
 * Use: URLs, API endpoints, route params, client references
 * Never: Direct database lookups
 */
export type ExtId = string & { readonly [ExtIdBrand]: never };

// ============================================================================
// Entity-Specific Branded Types (Optional Refinement)
// ============================================================================

/**
 * Entity-prefixed branded types for additional safety.
 * These can be used when even more granular type safety is needed.
 */
declare const OrganizationBrand: unique symbol;
declare const DomainBrand: unique symbol;
declare const SecretBrand: unique symbol;
declare const CustomerBrand: unique symbol;

/** Organization-specific external ID */
export type OrganizationExtId = ExtId & { readonly [OrganizationBrand]: never };

/** Domain-specific external ID */
export type DomainExtId = ExtId & { readonly [DomainBrand]: never };

/** Secret-specific external ID (the shortid used in URLs) */
export type SecretExtId = ExtId & { readonly [SecretBrand]: never };

/** Customer-specific external ID */
export type CustomerExtId = ExtId & { readonly [CustomerBrand]: never };

// ============================================================================
// Constructor Functions
// ============================================================================

/**
 * Convert a raw string to an ObjId.
 *
 * Use when receiving internal IDs from:
 * - API responses (id, objid fields)
 * - Redis operations
 * - Internal lookups
 *
 * @param raw - Raw string identifier
 * @returns Branded ObjId
 *
 * @example
 * const response = await api.get('/api/organizations/abc');
 * const objid = toObjId(response.data.record.id);
 */
export function toObjId(raw: string): ObjId {
  return raw as ObjId;
}

/**
 * Convert a raw string to an ExtId.
 *
 * Use when receiving external IDs from:
 * - Route parameters
 * - API responses (extid fields)
 * - User input
 *
 * @param raw - Raw string identifier
 * @returns Branded ExtId
 *
 * @example
 * const extid = toExtId(route.params.extid as string);
 */
export function toExtId(raw: string): ExtId {
  return raw as ExtId;
}

// ============================================================================
// Entity-Specific Constructors
// ============================================================================

/**
 * Create an organization-specific ExtId.
 * Provides additional type safety for organization operations.
 */
export function toOrganizationExtId(raw: string): OrganizationExtId {
  return raw as OrganizationExtId;
}

/**
 * Create a domain-specific ExtId.
 */
export function toDomainExtId(raw: string): DomainExtId {
  return raw as DomainExtId;
}

/**
 * Create a secret-specific ExtId (shortid).
 */
export function toSecretExtId(raw: string): SecretExtId {
  return raw as SecretExtId;
}

/**
 * Create a customer-specific ExtId.
 */
export function toCustomerExtId(raw: string): CustomerExtId {
  return raw as CustomerExtId;
}

// ============================================================================
// Validation Functions (Optional Runtime Checks)
// ============================================================================

/**
 * Validates and converts a string to ExtId with format checking.
 * Use when you need runtime validation (e.g., user input).
 *
 * ExtId format: alphanumeric, typically 8-12 chars, URL-safe
 *
 * @param raw - Raw string to validate
 * @returns Branded ExtId if valid
 * @throws Error if format is invalid
 */
export function validateExtId(raw: string): ExtId {
  // ExtIds are typically base36, alphanumeric, 8-12 chars
  const EXTID_PATTERN = /^[a-z0-9]{6,20}$/i;

  if (!EXTID_PATTERN.test(raw)) {
    throw new Error(`Invalid ExtId format: "${raw}". Expected alphanumeric, 6-20 characters.`);
  }

  return raw as ExtId;
}

/**
 * Safe version of validateExtId that returns null instead of throwing.
 */
export function parseExtId(raw: string): ExtId | null {
  try {
    return validateExtId(raw);
  } catch {
    return null;
  }
}

/**
 * Validates and converts a string to ObjId with format checking.
 *
 * ObjId format: typically "prefix:identifier" or just identifier
 *
 * @param raw - Raw string to validate
 * @returns Branded ObjId if valid
 * @throws Error if format is invalid
 */
export function validateObjId(raw: string): ObjId {
  // ObjIds must be non-empty strings
  if (!raw || typeof raw !== 'string' || raw.trim().length === 0) {
    throw new Error(`Invalid ObjId format: "${raw}". Expected non-empty string.`);
  }

  return raw as ObjId;
}

/**
 * Safe version of validateObjId that returns null instead of throwing.
 */
export function parseObjId(raw: string): ObjId | null {
  try {
    return validateObjId(raw);
  } catch {
    return null;
  }
}

// ============================================================================
// Zod Schemas for Runtime Validation
// ============================================================================

/**
 * Zod schema for ExtId validation.
 * Use in API response schemas to ensure type safety from the boundary.
 */
export const extIdSchema = z
  .string()
  .min(6)
  .max(20)
  .regex(/^[a-z0-9]+$/i)
  .transform((val) => val as ExtId);

/**
 * Zod schema for ObjId validation.
 * Use in API response schemas.
 */
export const objIdSchema = z
  .string()
  .min(1)
  .transform((val) => val as ObjId);

/**
 * Lenient ExtId schema for gradual migration.
 * Accepts any non-empty string but brands it as ExtId.
 */
export const lenientExtIdSchema = z.string().min(1).transform(toExtId);

/**
 * Lenient ObjId schema for gradual migration.
 * Accepts any non-empty string but brands it as ObjId.
 */
export const lenientObjIdSchema = z.string().min(1).transform(toObjId);

// ============================================================================
// Path Building Utilities
// ============================================================================

/**
 * Entity types that support path building.
 */
export type PathableEntity = 'org' | 'domain' | 'secret' | 'customer' | 'billing';

/**
 * Build a URL path segment for an entity.
 * This function enforces that only ExtIds are used in paths.
 *
 * @param entityType - Type of entity
 * @param extid - External ID (compile-time enforced)
 * @returns URL path segment
 *
 * @example
 * const path = buildEntityPath('org', org.extid); // "/org/abc123"
 * const path = buildEntityPath('org', org.id);    // Compile error!
 */
export function buildEntityPath(entityType: PathableEntity, extid: ExtId): string {
  switch (entityType) {
    case 'org':
      return `/org/${extid}`;
    case 'domain':
      return `/domains/${extid}`;
    case 'secret':
      return `/secret/${extid}`;
    case 'customer':
      return `/customer/${extid}`;
    case 'billing':
      return `/billing/${extid}`;
    default:
      // TypeScript exhaustiveness check
      const _exhaustive: never = entityType;
      throw new Error(`Unknown entity type: ${_exhaustive}`);
  }
}

/**
 * Build an API endpoint path for an entity.
 *
 * @param entityType - Type of entity
 * @param extid - External ID
 * @returns API endpoint path
 */
export function buildApiPath(entityType: PathableEntity, extid: ExtId): string {
  switch (entityType) {
    case 'org':
      return `/api/organizations/${extid}`;
    case 'domain':
      return `/api/domains/${extid}`;
    case 'secret':
      return `/api/secrets/${extid}`;
    case 'customer':
      return `/api/customers/${extid}`;
    case 'billing':
      return `/billing/api/${extid}`;
    default:
      const _exhaustive: never = entityType;
      throw new Error(`Unknown entity type: ${_exhaustive}`);
  }
}

// ============================================================================
// Type Guards
// ============================================================================

/**
 * Check if a value looks like an ExtId (runtime check).
 * Note: This is a runtime heuristic, not a brand check.
 */
export function looksLikeExtId(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  return /^[a-z0-9]{6,20}$/i.test(value);
}

/**
 * Check if a value looks like an ObjId (runtime check).
 * Typically internal IDs contain colons or are longer.
 */
export function looksLikeObjId(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  // ObjIds often have a prefix with colon
  return value.includes(':') || value.length > 20;
}

// ============================================================================
// Utility Types for Generic Code
// ============================================================================

/**
 * Any identifier type (for generic functions that accept either).
 */
export type AnyId = ObjId | ExtId;

/**
 * Extract the raw string type from a branded ID.
 */
export type UnwrapId<T extends AnyId> = T extends ObjId | ExtId ? string : never;

/**
 * Interface for entities that have both ID types.
 */
export interface Identifiable {
  id: ObjId;
  extid: ExtId;
}

/**
 * Partial identifiable - for when you may have one or both IDs.
 */
export interface PartialIdentifiable {
  id?: ObjId;
  extid?: ExtId;
}
