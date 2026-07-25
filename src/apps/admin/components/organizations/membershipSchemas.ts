// src/apps/admin/components/organizations/membershipSchemas.ts

/**
 * Contract for the colonel organization-membership ADD verb.
 *
 *   POST /api/colonel/organizations/:org_id/members
 *
 * Colocated with the organizations components rather than sitting in
 * `src/schemas/api/internal/responses/colonel-organizations.ts` (where the
 * sibling organization contracts live) purely because this change set could not
 * edit that file. It is a straight lift-and-shift when it moves — see the
 * handoff note in the PR description.
 *
 * Two things live here:
 *  - {@link MEMBERSHIP_ROLES}, mirrored from the backend's single source of
 *    truth for assignable roles.
 *  - {@link colonelAddMembershipResponseSchema}, the ack shape. Used as a
 *    TRIPWIRE (`gracefulParse`, never a gate) with ONE exception: `status` is
 *    load-bearing, because an idempotent `no_change` is a 200 that must NOT be
 *    reported to the operator as "added".
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
