// src/schemas/api/internal/responses/colonel-organizations.ts

/**
 * Colonel (Admin) organizations — NEW entitlement-override ack schema (ticket #32).
 *
 * The organizations LIST and the billing-INVESTIGATE read sides already have
 * frozen schemas in `./colonel` (`colonelOrganizationSchema` /
 * `colonelOrganizationsDetailsSchema` and `investigateOrganizationResultSchema`),
 * wrapped in `../../internal/responses/colonel`
 * (`colonelOrganizationsResponseSchema` / `investigateOrganizationResponseSchema`).
 * The organizations screen REUSES those (CONTRACT 3 — reuse over duplication) and
 * does NOT redefine them here.
 *
 * This file adds ONLY the schema for the entitlement-override MUTATION endpoints,
 * which had no frontend contract until this screen surfaced them:
 *   POST   /api/colonel/organizations/:org_id/entitlements/grant
 *   POST   /api/colonel/organizations/:org_id/entitlements/revoke
 *   DELETE /api/colonel/organizations/:org_id/entitlements/overrides
 *
 * It describes the SHAPE `ColonelAPI::Logic::Colonel::ManageEntitlementOverride`
 * returns: the org's PUBLIC id, the affected entitlement (null on a full clear),
 * the past-tense action, and the recomputed override state
 * (effective = plan_entitlements + grants - revokes). Kept in a per-resource file
 * so the organizations screen never edits another screen's contract (CONTRACT 2 /
 * the Zod tripwire — new schemas only).
 */

import { createApiResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * The recomputed entitlement-override state after a grant / revoke / clear.
 *
 * `entitlement` is the single entitlement acted on for grant/revoke and is null
 * for a full clear (the endpoint sends `null`, and older acks may omit the key).
 * `action` is the past-tense verb the backend emits (`ACTION_PAST_TENSE`).
 * `effective_entitlements` is the materialised result the org now resolves to.
 */
export const colonelEntitlementOverrideRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  entitlement: z.string().nullable().optional(),
  action: z.enum(['granted', 'revoked', 'cleared']),
  effective_entitlements: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
});

export type ColonelEntitlementOverrideRecord = z.infer<
  typeof colonelEntitlementOverrideRecordSchema
>;

// Wrapped response schema for the NEW colonel entitlement-override endpoints
// (ticket #32). Internal-only; consumed by the Vue admin bundle. Per-resource
// file so the organizations screen typechecks independently of the shared
// registry (CONTRACT 3) and never touches another screen's contract. The
// Integrate step adds the matching `colonelEntitlementOverride` key to
// `registry.ts`.
//
// The organizations LIST (`colonelOrganizationsResponseSchema`) and the
// billing-INVESTIGATE (`investigateOrganizationResponseSchema`) read schemas are
// REUSED from `./colonel`, not redefined here (CONTRACT 3 — reuse over
// duplication).

/**
 * `POST /api/colonel/organizations/:org_id/entitlements/:action` and
 * `DELETE /api/colonel/organizations/:org_id/entitlements/overrides` →
 * `{ record }` ack. `ManageEntitlementOverride` returns only `record`;
 * `createApiResponseSchema` requires `record` and makes only `details`
 * optional, so the absent `details` parses fine.
 */
export const colonelEntitlementOverrideResponseSchema = createApiResponseSchema(
  colonelEntitlementOverrideRecordSchema
);

export type ColonelEntitlementOverrideResponse = z.infer<
  typeof colonelEntitlementOverrideResponseSchema
>;

/**
 * The recomputed MEMBERSHIP entitlement-override state after a grant / revoke
 * / clear (#3907) — the membership-scoped sibling of
 * `colonelEntitlementOverrideRecordSchema`, returned by
 * `ColonelAPI::Logic::Colonel::ManageMembershipEntitlementOverride`:
 *   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/grant
 *   POST   /api/colonel/organizations/:org_id/members/:member_id/entitlements/revoke
 *   DELETE /api/colonel/organizations/:org_id/members/:member_id/entitlements/overrides
 *
 * Same shape one scope down: `org_id` and `member_id` are both PUBLIC extids,
 * `entitlement` is null on a full clear, and `effective_entitlements` is the
 * membership's materialised result
 * ((org ∩ role template) + grants - revokes).
 */
export const colonelMembershipEntitlementOverrideRecordSchema = z.object({
  org_id: z.string(),
  member_id: z.string(),
  entitlement: z.string().nullable().optional(),
  action: z.enum(['granted', 'revoked', 'cleared']),
  effective_entitlements: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
});

export type ColonelMembershipEntitlementOverrideRecord = z.infer<
  typeof colonelMembershipEntitlementOverrideRecordSchema
>;

/**
 * Membership entitlement-override endpoints → `{ record }` ack.
 * `ManageMembershipEntitlementOverride` returns only `record`;
 * `createApiResponseSchema` requires `record` and makes only `details`
 * optional, so the absent `details` parses fine. Registered as
 * `colonelMembershipEntitlementOverride` in `registry.ts`.
 */
export const colonelMembershipEntitlementOverrideResponseSchema = createApiResponseSchema(
  colonelMembershipEntitlementOverrideRecordSchema
);

export type ColonelMembershipEntitlementOverrideResponse = z.infer<
  typeof colonelMembershipEntitlementOverrideResponseSchema
>;

// ============================================================================
// Organization DETAIL + reconcile schemas (colonel org audit remediation)
//
// The Organizations screen gained a first-class detail page. These describe the
// two NEW endpoints that page consumes:
//   GET  /api/colonel/organizations/:org_id            → colonelOrganizationDetail
//   POST /api/colonel/organizations/:org_id/reconcile  → reconcile ack
//
// Shapes mirror the VALIDATED live output of
// `ColonelAPI::Logic::Colonel::GetOrganizationDetail` /
// `ReconcileOrganization`. Timestamps arrive as epoch ints and are transformed
// to Date (matching the sibling colonel detail schemas). `null` where the
// backend can emit null; `display_name` stays nullable to agree with the LIST
// schema (`colonelOrganizationSchema`), which is corroborating evidence.
// ============================================================================

/**
 * The materialised entitlement breakdown for one org. The operator reads this
 * on load (no blind mutation): `materialized` = the effective set the org
 * resolves to = `expected` = (plan ∪ grants) − revokes. `drift` flags any
 * mismatch between materialized and expected (normally empty / in_sync).
 * `plan_stale` true = plan definition changed since last materialization
 * (offer reconcile); null = the plan could not be loaded.
 */
export const colonelOrganizationDetailEntitlementsSchema = z.object({
  plan: z.array(z.string()),
  grants: z.array(z.string()),
  revokes: z.array(z.string()),
  materialized: z.array(z.string()),
  expected: z.array(z.string()),
  materialized_flag: z.boolean(),
  materialized_at: transforms.fromNumber.toDateNullable,
  plan_stale: z.boolean().nullable(),
  drift: z.object({
    extra: z.array(z.string()),
    missing: z.array(z.string()),
    in_sync: z.boolean(),
  }),
});

/**
 * One entry of the literal entitlement catalog (billing.yaml), as emitted by
 * `GetOrganizationDetail#build_available_entitlements`. This is the SAME set
 * the server's validation predicate consults
 * (`Onetime::Operations::Org::EntitlementOverride.known_entitlement?` →
 * `::Billing::Config.load_entitlements.key?`), so the override picker's options
 * cannot drift from what the endpoint accepts.
 *
 * `description` / `category` are nullable: billing.yaml carries both today, but
 * an entry may omit either and the backend passes the absence through as null.
 */
export const colonelAvailableEntitlementSchema = z.object({
  name: z.string(),
  description: z.string().nullable(),
  category: z.string().nullable(),
});

export type ColonelAvailableEntitlement = z.infer<typeof colonelAvailableEntitlementSchema>;

/** One organization member row on the detail page. */
export const colonelOrganizationDetailMemberSchema = z.object({
  extid: z.string(),
  email: z.string().nullable(),
  role: z.string().nullable(),
  status: z.string().nullable(),
  is_owner: z.boolean(),
  joined_at: transforms.fromNumber.toDateNullable,
  created: transforms.fromNumber.toDateNullable,
});

/** One organization domain row on the detail page. */
export const colonelOrganizationDetailDomainSchema = z.object({
  extid: z.string(),
  domain_id: z.string(),
  display_domain: z.string(),
  base_domain: z.string(),
  status: z.string().nullable(),
  verified: z.boolean(),
  resolving: z.boolean(),
  verification_state: z.string(),
  ready: z.boolean(),
  created: transforms.fromNumber.toDateNullable,
});

/** The organization record on the detail page (billing read-out + lifecycle). */
export const colonelOrganizationDetailRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  display_name: z.string().nullable(),
  description: z.string().nullable(),
  is_default: z.boolean(),
  archived: z.boolean(),
  archived_at: transforms.fromNumber.toDateNullable,
  archived_comment: z.string().nullable(),
  contact_email: z.string().nullable(),
  // Nullable to agree with the LIST schema (colonel.ts), which declares the
  // same field from the same Ruby expression as nullable. An org with no owner
  // is an expected state — the line below reads `owner&.email` for exactly that
  // reason — and a required string here would fail the parse for the WHOLE
  // detail response, blanking the page rather than dropping one field.
  owner_id: z.string().nullable(),
  owner_email: z.string().nullable(),
  billing_email: z.string().nullable(),
  member_count: z.number(),
  domain_count: z.number(),
  // Ruby emits `org.created&.to_i`, so nil IS reachable here — unlike the LIST
  // side, which uses `org.created.to_i` with no safe navigation and is
  // correctly non-nullable. Both sibling record schemas above (member, domain)
  // already use toDateNullable.
  created: transforms.fromNumber.toDateNullable,
  updated: transforms.fromNumber.toDateNullable,
  planid: z.string().nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
  billing_email_present: z.boolean(),
  sync_status: z.string(),
  sync_status_reason: z.string().nullable(),
});

/** The `details` envelope: entitlement breakdown + catalog + members + domains. */
export const colonelOrganizationDetailDetailsSchema = z.object({
  entitlements: colonelOrganizationDetailEntitlementsSchema,
  /**
   * The entitlement catalog the override picker offers. `.default([])` so a
   * backend that predates the field (or a fixture that omits it) degrades to
   * "catalog unavailable" instead of failing the whole detail parse and
   * bricking the page — and an empty catalog already carries the right
   * meaning: treat every typed name as known (fail open, like the server).
   */
  available_entitlements: z.array(colonelAvailableEntitlementSchema).default([]),
  members: z.array(colonelOrganizationDetailMemberSchema),
  domains: z.array(colonelOrganizationDetailDomainSchema),
});

/**
 * `GET /api/colonel/organizations/:org_id` → `{ record, details }`. `:org_id`
 * is the org's PUBLIC id (extid).
 */
export const colonelOrganizationDetailResponseSchema = createApiResponseSchema(
  colonelOrganizationDetailRecordSchema,
  colonelOrganizationDetailDetailsSchema
);

export type ColonelOrganizationDetailEntitlements = z.infer<
  typeof colonelOrganizationDetailEntitlementsSchema
>;
export type ColonelOrganizationDetailMember = z.infer<typeof colonelOrganizationDetailMemberSchema>;
export type ColonelOrganizationDetailDomain = z.infer<typeof colonelOrganizationDetailDomainSchema>;
export type ColonelOrganizationDetailRecord = z.infer<typeof colonelOrganizationDetailRecordSchema>;
export type ColonelOrganizationDetailResponse = z.infer<
  typeof colonelOrganizationDetailResponseSchema
>;

/**
 * Billing snapshot on either side of a reconcile. `materialized_count` is the
 * size of the effective entitlement set; the plan/subscription fields mirror
 * the (nullable) record fields.
 */
export const colonelReconcileSnapshotSchema = z.object({
  planid: z.string().nullable(),
  subscription_status: z.string().nullable(),
  subscription_period_end: z.string().nullable(),
  materialized_count: z.number(),
});

/**
 * Membership-cascade counts from an applied reconcile (#3907 item 3):
 * `rematerialize_all_memberships!` totals, surfaced so a partial cascade is
 * operator-visible without log access. `failed_ids` are membership OBJIDs
 * (internal — the identifier `bin/ots memberships doctor` follow-up works in;
 * same posture as the record's `org_id`).
 */
export const colonelReconcileMembershipCascadeSchema = z.object({
  success: z.number(),
  failed: z.number(),
  total: z.number(),
  failed_ids: z.array(z.string()),
});

/**
 * `POST /api/colonel/organizations/:org_id/reconcile` → `{ record }`. MUTATING:
 * re-pulls Stripe and rewrites billing + re-materializes (`stripe_sync`), or
 * re-materializes entitlements from the current plan when there is no
 * subscription (`entitlements_only`). `before`/`after` drive the success diff.
 * `memberships` is null when the run did not cascade (skip statuses) or the
 * cascade raised server-side (logs carry that case).
 */
export const colonelReconcileOrganizationRecordSchema = z.object({
  org_id: z.string(),
  extid: z.string(),
  mode: z.enum(['stripe_sync', 'entitlements_only']),
  status: z.string(),
  reason: z.string().nullable(),
  before: colonelReconcileSnapshotSchema,
  // Nullable to match the op's Result contract: `after` is nil on dry runs
  // and Stripe errors. Today the colonel adapter pins dry_run:false and 4xxes
  // Stripe errors before responding, so null never reaches the wire — but the
  // D12 preview work (#3907 item 4) will change that, and a non-nullable
  // schema here would reject those responses with no compile-time signal.
  after: colonelReconcileSnapshotSchema.nullable(),
  memberships: colonelReconcileMembershipCascadeSchema.nullable(),
});

export const colonelReconcileOrganizationResponseSchema = createApiResponseSchema(
  colonelReconcileOrganizationRecordSchema
);

export type ColonelReconcileSnapshot = z.infer<typeof colonelReconcileSnapshotSchema>;
export type ColonelReconcileMembershipCascade = z.infer<
  typeof colonelReconcileMembershipCascadeSchema
>;
export type ColonelReconcileOrganizationRecord = z.infer<
  typeof colonelReconcileOrganizationRecordSchema
>;
export type ColonelReconcileOrganizationResponse = z.infer<
  typeof colonelReconcileOrganizationResponseSchema
>;

/**
 * `POST /api/colonel/organizations/:org_id/transfer-ownership` → `{ record }`
 * ack (#3907 — console peer of `bin/ots org transfer-ownership`). MUTATING:
 * promotes the new owner, pivots the legacy `owner_id` mirror, and demotes
 * every other owner membership. All ids are PUBLIC extids (mirroring
 * `TransferOrganizationOwnership#success_data`, which mirrors the CLI's --json
 * payload). `from_owner_id` is null when the previous `owner_id` pointed at no
 * live customer (`orphaned_owner: true` — the transfer repairs it). `status`
 * is the op's vocabulary verbatim (`success` | `no_change` — failure statuses
 * surface as 4xx form errors, never as a 200).
 */
export const colonelTransferOrganizationOwnershipRecordSchema = z.object({
  org_id: z.string(),
  status: z.string(),
  from_owner_id: z.string().nullable(),
  to_owner_id: z.string(),
  demoted: z.array(z.string()),
  demoted_to: z.string(),
  orphaned_owner: z.boolean(),
});

export const colonelTransferOrganizationOwnershipResponseSchema = createApiResponseSchema(
  colonelTransferOrganizationOwnershipRecordSchema
);

export type ColonelTransferOrganizationOwnershipRecord = z.infer<
  typeof colonelTransferOrganizationOwnershipRecordSchema
>;
export type ColonelTransferOrganizationOwnershipResponse = z.infer<
  typeof colonelTransferOrganizationOwnershipResponseSchema
>;

/**
 * One member of an organization that is about to be (or has just been) deleted.
 * PUBLIC extid + address, snapshotted server-side BEFORE the teardown — after
 * `destroy!` the membership records are gone and this list is unrecoverable.
 */
export const colonelDeleteOrganizationMemberSchema = z.object({
  extid: z.string(),
  email: z.string(),
});

/**
 * The delete plan / receipt: everything the operator confirms against, echoed
 * from `Onetime::Operations::Org::Delete::Result`.
 *
 * `dry_run` is the field that decides whether this is a PREVIEW or a RECEIPT —
 * the endpoint DEFAULTS `dry_run` to true, so an apply must send
 * `dry_run=false` explicitly and the caller must check this echo (plus
 * `record.deleted`) before reporting a deletion.
 *
 * `is_default` / `active_subscription` are the guardrail inputs, echoed so the
 * screen can explain WHY a delete is blocked and which override
 * (`force_default` / `force_subscription`) unlocks that one guard.
 * `default_org_cleared` names the customers whose `default_org_id` pointed at
 * this org and was (or would be) cleared — the repair a hand-run console
 * `destroy!` skips.
 */
export const colonelDeleteOrganizationDetailsSchema = z.object({
  dry_run: z.boolean(),
  planid: z.string(),
  members: z.array(colonelDeleteOrganizationMemberSchema),
  members_notified: z.number(),
  pending_invitations: z.number(),
  /**
   * The org's raw domain count — the guard's input. Deliberately not
   * `domains.length`: `destroy!` refuses on the count, while the name list
   * compacts away collection entries whose domain record is gone. Trust this
   * for "is it blocked", and the names for "which ones".
   */
  domain_count: z.number(),
  domains: z.array(z.string()),
  /**
   * Display domains that still reference this org through `CustomDomain.owners`
   * but are MISSING from its domains collection — the `drifted_domains`
   * refusal. Disjoint from `domains` (that is what "missing from the
   * collection" means) and NOT counted in `domain_count`, so the operator can
   * only learn which ones to repair from this list. Empty on the healthy path.
   * The remediation is operator-side (`bin/ots domains doctor --all --repair`); there
   * is no override.
   *
   * `.default([])` follows `available_entitlements`: a backend that predates
   * the field (or a fixture that omits it) degrades to "no drift reported"
   * instead of failing the whole parse and refusing to open the dialog. The
   * `status` remains the authoritative verdict either way.
   */
  drifted_domains: z.array(z.string()).default([]),
  is_default: z.boolean(),
  active_subscription: z.boolean(),
  owner_id: z.string().nullable(),
  owner_org_count: z.number(),
  default_org_cleared: z.array(z.string()),
});

/**
 * `DELETE /api/colonel/organizations/:org_id` → `{ record, details }` (#4204 —
 * console peer of `bin/ots org delete`). MUTATING when `dry_run=false`.
 *
 * `status` is the op's vocabulary verbatim: `planned` | `success` |
 * `has_domains` | `drifted_domains` | `is_default` | `active_subscription` |
 * `last_org`. A DRY RUN
 * answers 200 on ANY of them — the preview is the plan, and a 4xx would throw
 * away the payload the confirmation screen is built from. An APPLY answers 200
 * only on `success`; a refused apply is a 4xx form error naming the guard.
 *
 * `deleted` is therefore the one boolean to trust before reporting a deletion.
 * It is `z.boolean()` and not derived: it is true only on an applied
 * `success`.
 */
export const colonelDeleteOrganizationRecordSchema = z.object({
  deleted: z.boolean(),
  org_id: z.string(),
  display_name: z.string(),
  status: z.string(),
});

export const colonelDeleteOrganizationResponseSchema = createApiResponseSchema(
  colonelDeleteOrganizationRecordSchema,
  colonelDeleteOrganizationDetailsSchema
);

export type ColonelDeleteOrganizationMember = z.infer<typeof colonelDeleteOrganizationMemberSchema>;
export type ColonelDeleteOrganizationDetails = z.infer<
  typeof colonelDeleteOrganizationDetailsSchema
>;
export type ColonelDeleteOrganizationRecord = z.infer<typeof colonelDeleteOrganizationRecordSchema>;
export type ColonelDeleteOrganizationResponse = z.infer<
  typeof colonelDeleteOrganizationResponseSchema
>;
