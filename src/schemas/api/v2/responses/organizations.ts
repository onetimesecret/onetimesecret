// src/schemas/api/v2/responses/organizations.ts
//
// Response schemas for organization and member endpoints.

import { z } from 'zod';
import {
  organizationResponseSchema,
  organizationsResponseSchema,
  deleteResponseSchema as orgDeleteResponseSchema,
  membersResponseSchema,
  memberResponseSchema,
  memberDeleteResponseSchema,
} from '@/schemas/api/organizations/responses/organizations';

// Re-export — these are full response schemas defined in the organizations module
export {
  organizationResponseSchema,
  organizationsResponseSchema,
  orgDeleteResponseSchema,
  membersResponseSchema,
  memberResponseSchema,
  memberDeleteResponseSchema,
};

export type OrganizationResponse = z.infer<typeof organizationResponseSchema>;
export type OrganizationListResponse = z.infer<typeof organizationsResponseSchema>;
export type OrganizationDeleteResponse = z.infer<typeof orgDeleteResponseSchema>;
export type MemberListResponse = z.infer<typeof membersResponseSchema>;
export type MemberResponse = z.infer<typeof memberResponseSchema>;
export type MemberDeleteResponse = z.infer<typeof memberDeleteResponseSchema>;
