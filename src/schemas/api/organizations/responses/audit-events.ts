// src/schemas/api/organizations/responses/audit-events.ts

/**
 * Organization audit-events (Secret Activity) endpoint schemas (#3637).
 *
 * Shape verified against the live logic class
 * (apps/api/organizations/logic/organizations/list_audit_events.rb) and its
 * contract spec (list_audit_events_spec.rb): the envelope nests offset/limit
 * under `details` (NOT top-level) and carries an extra top-level `user_id`.
 */

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * The event kinds the trail writes today
 * (lib/onetime/models/organization/features/audit_trail.rb). The schema
 * deliberately validates `kind` as a plain string — an unknown future kind
 * must pass validation and render with a raw-kind fallback label, not knock
 * the whole page into the contract-mismatch state.
 */
export const AUDIT_EVENT_KINDS = [
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

export type AuditEventKind = (typeof AUDIT_EVENT_KINDS)[number];

/**
 * One org audit event. Base fields are kind/at/nonce plus receipt/secret
 * shortids (never full identifiers — those are capability tokens). Extra
 * fields vary by kind: fetch events may carry net_ip_partial / net_ip_hash /
 * net_ua_partial; revealed/burned carry actor (creator | authenticated_other
 * | anonymous) and an optional 8-char actor_id shortid. `looseObject` keeps
 * the schema tolerant of further per-kind fields the backend adds later.
 * `at` arrives as a Unix-second float and is transformed to Date.
 */
export const auditEventSchema = z.looseObject({
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
});

export type OrgAuditEvent = z.infer<typeof auditEventSchema>;

/**
 * Audit events list response
 * GET /api/organizations/:extid/audit-events
 *
 * `total` is the org-wide event count and saturates at the retention cap
 * (10,000 — AUDIT_EVENTS_MAX); `count` is the size of this page.
 */
export const auditEventsResponseSchema = z.object({
  user_id: z.string(),
  organization_id: z.string(),
  records: z.array(auditEventSchema),
  count: z.number().int().min(0),
  total: z.number().int().min(0),
  details: z.object({
    offset: z.number().int().min(0),
    limit: z.number().int().min(1),
  }),
});

export type AuditEventsResponse = z.infer<typeof auditEventsResponseSchema>;
