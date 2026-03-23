// src/schemas/shapes/organizations/organization.ts
//
// V2 API response shapes with runtime transforms.
//
// Contract definitions (wire formats) are in contracts/organization.ts.
// This file transforms wire format to runtime types (timestamps → Date).
//
// Architecture:
// - contracts/organization.ts: Wire format contracts + canonical schema
// - This file: Shapes with transforms for V2 API responses
// - shapes/v3/organization.ts: V3 wire format extending canonical contract

import {
  organizationInvitationContractSchema,
  organizationMemberContractSchema,
  organizationV2ContractSchema,
} from '@/schemas/contracts/organization';

// Re-export all contracts for backwards compatibility
export * from '@/schemas/contracts/organization';

/**
 * Organization schema
 *
 * Transforms V2 contract timestamps to Date objects.
 * Normalizes nullish is_default to false.
 */
export const organizationSchema = organizationV2ContractSchema.transform((data) => ({
  ...data,
  is_default: data.is_default ?? false,
  created: new Date(data.created * 1000),
  updated: new Date(data.updated * 1000),
}));

export type Organization = ReturnType<typeof organizationSchema.parse>;

/**
 * Organization invitation schema
 *
 * Currently no transforms - re-exports contract directly.
 * Kept as separate export for backwards compatibility.
 */
export const organizationInvitationSchema = organizationInvitationContractSchema;

export type OrganizationInvitation = ReturnType<typeof organizationInvitationSchema.parse>;

/**
 * Organization member schema
 *
 * Currently no transforms - re-exports contract directly.
 * Kept as separate export for backwards compatibility.
 */
export const organizationMemberSchema = organizationMemberContractSchema;

export type OrganizationMember = ReturnType<typeof organizationMemberSchema.parse>;
