// src/schemas/api/account/responses/permissions.ts

import { z } from 'zod';

/**
 * Resource permissions object returned for orgs and domains
 */
export const resourcePermissionsSchema = z.object({
  can_view: z.boolean(),
  can_edit: z.boolean(),
  can_delete: z.boolean(),
  can_manage_settings: z.boolean(),
});

export type ResourcePermissions = z.infer<typeof resourcePermissionsSchema>;

/**
 * Membership details within a permissions response
 */
export const membershipDetailsSchema = z.object({
  role: z.enum(['owner', 'admin', 'member']),
  status: z.string(),
  provisioning_source: z.string().nullable(),
  invited_at: z.union([z.string(), z.number()]).nullable(),
  joined_at: z.union([z.string(), z.number()]).nullable(),
  entitlements: z.array(z.string()),
});

export type MembershipDetails = z.infer<typeof membershipDetailsSchema>;

/**
 * Domain with permissions (nested in bulk response)
 */
export const domainPermissionsSchema = z.object({
  extid: z.string(),
  display_domain: z.string(),
  permissions: resourcePermissionsSchema,
});

export type DomainPermissions = z.infer<typeof domainPermissionsSchema>;

/**
 * Organization with membership and permissions (bulk response)
 */
export const organizationPermissionsSchema = z.object({
  extid: z.string(),
  display_name: z.string(),
  is_default: z.boolean(),
  membership: membershipDetailsSchema,
  permissions: resourcePermissionsSchema,
  domains: z.array(domainPermissionsSchema),
});

export type OrganizationPermissions = z.infer<typeof organizationPermissionsSchema>;

/**
 * Bulk mode response: GET /api/account/permissions
 */
export const bulkPermissionsResponseSchema = z.object({
  organizations: z.array(organizationPermissionsSchema),
});

export type BulkPermissionsResponse = z.infer<typeof bulkPermissionsResponseSchema>;

/**
 * Organization brief (single-resource response)
 */
export const organizationBriefSchema = z.object({
  extid: z.string(),
  display_name: z.string(),
});

export type OrganizationBrief = z.infer<typeof organizationBriefSchema>;

/**
 * Single-resource mode response: GET /api/account/permissions?resource_type=...&resource_id=...
 */
export const singleResourcePermissionsResponseSchema = z.object({
  resource_type: z.enum(['domain', 'organization']),
  resource_id: z.string(),
  organization: organizationBriefSchema,
  membership: membershipDetailsSchema,
  permissions: resourcePermissionsSchema,
});

export type SingleResourcePermissionsResponse = z.infer<typeof singleResourcePermissionsResponseSchema>;
