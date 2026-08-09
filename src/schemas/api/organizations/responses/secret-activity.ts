// src/schemas/api/organizations/responses/secret-activity.ts

/**
 * Organization secret-activity endpoint schemas (#3637).
 *
 * Shape verified against the live logic class
 * (apps/api/organizations/logic/organizations/list_secret_activity.rb) and its
 * contract spec (list_secret_activity_spec.rb): the envelope nests offset/limit
 * under `details` (NOT top-level) and carries an extra top-level `user_id`.
 */

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * The event kinds the trail writes today
 * (lib/onetime/models/organization/features/secret_activity.rb). The schema
 * deliberately validates `kind` as a plain string — an unknown future kind
 * must pass validation and render with a raw-kind fallback label, not knock
 * the whole page into the contract-mismatch state.
 */
export const SECRET_ACTIVITY_KINDS = [
  'created',
  'status_get',
  'secret_get',
  'previewed',
  'creator_status_get',
  'receipt_viewed',
  'revealed',
  'burned',
  'expired',
  'orphaned',
  'reveal_failed_undecryptable',
] as const;

export type SecretActivityKind = (typeof SECRET_ACTIVITY_KINDS)[number];

/**
 * One org audit event. Base fields are kind/at/nonce plus receipt/secret
 * shortids (never full identifiers — those are capability tokens). Extra
 * fields vary by kind: fetch events may carry net_ip_partial / net_ip_hash /
 * net_ua_partial; every kind carries actor (creator | authenticated_other |
 * anonymous | system | unknown) and, for authenticated actors, actor_id — the FULL
 * customer objid (a customer objid grants no access, so the shortid
 * capability-token rationale does not apply; NIST AU-3(f)/PCI 10.2.2 require
 * a uniquely resolvable identity). Historical events may still hold legacy
 * 8-char values — render whatever arrives. 'system' and 'anonymous' never
 * carry actor_id. `looseObject` keeps the schema tolerant of further
 * per-kind fields the backend adds later. `at` arrives as a Unix-second
 * float and is transformed to Date. net_country is the Otto-derived country
 * code for the event's originating IP (#3989); it is a legally-sensitive
 * org-tier geo field pending counsel review, so the FRONTEND gates its
 * display behind isSecretActivityGeoCountryEnabled (default OFF) even
 * though the field may be present on the wire.
 */
export const secretActivityEventSchema = z.looseObject({
  kind: z.string(),
  at: transforms.fromNumber.toDate,
  nonce: z.string(),
  receipt: z.string().optional(),
  secret: z.string().optional(),
  actor: z.string().optional(),
  actor_id: z.string().optional(),
  net_ip_partial: z.string().optional(),
  net_ip_hash: z.string().optional(),
  net_ua_partial: z.string().optional(),
  net_country: z.string().optional(),
});

export type SecretActivityEvent = z.infer<typeof secretActivityEventSchema>;

/**
 * Audit events list response
 * GET /api/organizations/:extid/secret-activity
 *
 * `total` is the org-wide event count and saturates at the retention cap
 * (10,000 — SECRET_ACTIVITY_MAX_EVENTS); `count` is the size of this page.
 */
export const secretActivityResponseSchema = z.object({
  user_id: z.string(),
  organization_id: z.string(),
  records: z.array(secretActivityEventSchema),
  count: z.number().int().min(0),
  total: z.number().int().min(0),
  details: z.object({
    offset: z.number().int().min(0),
    limit: z.number().int().min(1),
    // Read-time identity resolution, keyed by full actor objid. Only current
    // active org members appear (resolved via an org-membership join at read
    // time — email never enters the append-only trail). An absent key means
    // unresolved (removed member / out-of-org actor) and the UI renders the
    // bare objid: unique-but-unresolved, CloudTrail deleted-principal
    // semantics. Optional so older backend responses still parse.
    actors: z
      .record(z.string(), z.object({ email: z.string(), extid: z.string() }))
      .optional(),
  }),
});

export type SecretActivityResponse = z.infer<typeof secretActivityResponseSchema>;

/** Read-time actor resolution map (details.actors), normalized to non-optional. */
export type SecretActivityActorsMap = NonNullable<SecretActivityResponse['details']['actors']>;
