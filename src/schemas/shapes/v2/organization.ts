// src/schemas/shapes/v2/organization.ts
//
// V2 wire-format shapes for organizations (core model fields).
// Uses createModelSchema to extend base with string-to-type transforms.
//
// Note: This provides core model fields matching the Ruby Organization model.
// For API response schemas with additional fields (members, limits, etc.),
// see shapes/organizations/organization.ts

/**
 * V2 organization core schema with string-to-type transformations.
 *
 * V2 API returns most values as strings (Redis serialization format).
 * This schema transforms wire-format strings to proper TypeScript types.
 *
 * This is the core model schema matching Ruby's Organization model fields.
 * For full API response schemas, see shapes/organizations/organization.ts.
 *
 * @module shapes/v2/organization
 * @category Shapes
 * @see {@link "contracts/organization"} - Canonical field contract
 * @see {@link "shapes/v3/organization"} - V3 wire format with native types
 * @see {@link "shapes/organizations/organization"} - Full API response schema
 */

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

import { createModelSchema } from './base';

/**
 * V2 organization core schema with unified transformations.
 *
 * Extends base model schema (identifier, created, updated) with
 * organization-specific fields. Applies string transforms for
 * boolean and nullable fields from Redis wire format.
 *
 * @example
 * ```typescript
 * const org = organizationCoreSchema.parse({
 *   identifier: 'org123',
 *   objid: '01234567-89ab-cdef-0123-456789abcdef',
 *   extid: 'on1a2b3c4d',
 *   display_name: 'Acme Corp',
 *   description: 'A great company',
 *   owner_id: 'cust123',
 *   contact_email: 'billing@acme.com',
 *   is_default: 'false',
 *   planid: 'pro',
 *   created: '1609459200',
 *   updated: '1609545600',
 * });
 *
 * console.log(org.is_default); // false (boolean)
 * console.log(org.created instanceof Date); // true
 * ```
 */
export const organizationCoreSchema = createModelSchema({
  // Core identity fields
  objid: z.string(),
  extid: z.string(),

  // Display fields
  display_name: z.string(),
  description: z.string().nullable().default(null),

  // Ownership and contact
  owner_id: z.string(),
  contact_email: z.string().nullable().default(null),

  // Status fields (V2 sends booleans as strings)
  is_default: transforms.fromString.boolean.default(false),
  planid: z.string().default('free'),
}).strict();

// Update the type to explicitly use Date for timestamps
export type OrganizationCore = Omit<
  z.infer<typeof organizationCoreSchema>,
  'created' | 'updated'
> & {
  created: Date;
  updated: Date;
};
