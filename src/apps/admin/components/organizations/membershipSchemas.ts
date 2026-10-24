// src/apps/admin/components/organizations/membershipSchemas.ts

/**
 * Contracts for the colonel organization-membership verbs.
 *
 *   POST   /api/colonel/organizations/:org_id/members
 *   POST   /api/colonel/organizations/:org_id/members/:member_id/role
 *   DELETE /api/colonel/organizations/:org_id/members/:member_id
 *
 * Colocated with the organizations components rather than sitting in
 * `src/schemas/api/internal/responses/colonel-organizations.ts` (where the
 * sibling organization contracts live) purely because this change set could not
 * edit that file. It is a straight lift-and-shift when it moves — see the
 * handoff note in the PR description.
 *
 * What lives here:
 *  - {@link MEMBERSHIP_ROLES}, mirrored from the backend's single source of
 *    truth for assignable roles, and {@link CHANGEABLE_MEMBERSHIP_ROLES}, the
 *    subset a role CHANGE offers.
 *  - The three ack shapes. Each is used as a TRIPWIRE (`gracefulParse`, never
 *    a gate) with ONE exception: `status` is load-bearing on add and set-role,
 *    because an idempotent `no_change` is a 200 that must NOT be reported to
 *    the operator as a change.
 */

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

/**
 * The membership roles `POST /organizations/:org_id/members` accepts.
 *
 * Mirrors `Onetime::Operations::Memberships::Add::VALID_ROLES`, which is itself
 * `Onetime::OrganizationMembership::ROLE_ENTITLEMENTS.keys`
 * (lib/onetime/models/organization_membership.rb). Anything outside this list
 * comes back as a 4xx form error on the `role` field, so do NOT extend it here
 * without changing that constant first.
 *
 * Ordered least- to most-privileged so the select defaults to the safe choice.
 */
export const MEMBERSHIP_ROLES = ['member', 'admin', 'owner'] as const;

export type MembershipRole = (typeof MEMBERSHIP_ROLES)[number];

/** Payload the add-member modal hands back to its parent on submit. */
export interface AddMembershipRequest {
  /**
   * The customer's PUBLIC id (extid) — never an email address. The picker has
   * already resolved the operator's address to exactly one account, and an
   * extid survives the adapter's identifier sanitizing unambiguously where an
   * address does not.
   */
  customer: string;
  role: MembershipRole;
}

/**
 * `AddMembership#success_data`. The three membership adapters return `record`
 * ONLY (no `details` key) — `createApiResponseSchema` already makes `details`
 * optional, so nothing extra is needed here.
 *
 * `status` is `success` (a real add, audited server-side as `membership.add`)
 * or `no_change` (the customer was already a member; the op deliberately left
 * their role untouched and audited nothing). Kept as a plain string rather than
 * an enum so a future status does not turn a successful mutation into a parse
 * failure. `role` echoes the member's role AFTER the call — for `no_change`
 * that is their CURRENT role, not the requested one.
 */
export const colonelAddMembershipRecordSchema = z.object({
  org_id: z.string(),
  member_id: z.string(),
  status: z.string(),
  role: z.string().nullable(),
});

export const colonelAddMembershipResponseSchema = createApiResponseSchema(
  colonelAddMembershipRecordSchema
);

export type ColonelAddMembershipRecord = z.infer<typeof colonelAddMembershipRecordSchema>;
export type ColonelAddMembershipResponse = z.infer<typeof colonelAddMembershipResponseSchema>;

/**
 * Roles the console offers when CHANGING an existing member's role
 * (`POST /organizations/:org_id/members/:member_id/role`).
 *
 * `owner` is deliberately absent even though `SetRole::VALID_ROLES` accepts it.
 * A bare set-role to `owner` leaves a second `owner` membership beside the
 * current one and does not move the organization's `owner_id`; promoting,
 * pivoting `owner_id` and demoting the previous owner together is what
 * `Onetime::Operations::Org::TransferOwnership` exists for. Ownership moves
 * through that transfer, never through this control.
 */
export const CHANGEABLE_MEMBERSHIP_ROLES = [
  'member',
  'admin',
] as const satisfies readonly MembershipRole[];

export type ChangeableMembershipRole = (typeof CHANGEABLE_MEMBERSHIP_ROLES)[number];

/**
 * `SetMembershipRole#success_data`: `{ record }` only. `status` is `success`
 * (a real change) or `no_change` (already at the target role — an idempotent
 * 200 that must not be reported as a change). `from` / `to` are role names.
 * Loose on purpose, like {@link colonelAddMembershipRecordSchema}: the ack is a
 * tripwire, and the roster is redrawn from a refreshed detail GET.
 */
export const colonelSetMembershipRoleRecordSchema = z.object({
  org_id: z.string(),
  member_id: z.string(),
  status: z.string(),
  from: z.string().nullable(),
  to: z.string().nullable(),
});

export const colonelSetMembershipRoleResponseSchema = createApiResponseSchema(
  colonelSetMembershipRoleRecordSchema
);

export type ColonelSetMembershipRoleRecord = z.infer<typeof colonelSetMembershipRoleRecordSchema>;
export type ColonelSetMembershipRoleResponse = z.infer<
  typeof colonelSetMembershipRoleResponseSchema
>;

/**
 * `RemoveMembership#success_data`: `{ record, details }`. Refusals
 * (`not_found`, `last_owner`) arrive as 4xx, so a 200 is always a completed
 * removal; `role` is the role the membership held.
 */
export const colonelRemoveMembershipRecordSchema = z.object({
  org_id: z.string(),
  member_id: z.string(),
  status: z.string(),
  role: z.string().nullable(),
});

/**
 * `default_org_cleanup` is the removal's default_org_id cleanup outcome
 * (`cleared`, `unchanged` or `failed`). A `failed` cleanup does not undo the
 * removal: the member's default organization may still point to this org.
 */
export const colonelRemoveMembershipDetailsSchema = z.object({
  default_org_cleanup: z.string().nullable(),
});

export const colonelRemoveMembershipResponseSchema = createApiResponseSchema(
  colonelRemoveMembershipRecordSchema,
  colonelRemoveMembershipDetailsSchema
);

export type ColonelRemoveMembershipRecord = z.infer<typeof colonelRemoveMembershipRecordSchema>;
export type ColonelRemoveMembershipDetails = z.infer<typeof colonelRemoveMembershipDetailsSchema>;
export type ColonelRemoveMembershipResponse = z.infer<typeof colonelRemoveMembershipResponseSchema>;
