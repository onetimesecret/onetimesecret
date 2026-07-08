// src/schemas/api/account/responses/colonel-audit.ts
//
// Per-resource colonel/admin schemas for the Audit Log screen (observability).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). This is the read side of the
// AdminAuditEvent flight recorder (every mutating admin op writes one):
//
//   - ListAuditEvents → GET /api/colonel/audit (newest-first list + filters)
//
// Shape verified against the live logic class
// (apps/api/colonel/logic/colonel/list_audit_events.rb), a read-only slice of
// the capped `admin_audit_event:events` sorted set. Reading the log never
// writes an audit event (CONTRACT 4).

import { paginationSchema } from '@/schemas/api/account/responses/colonel';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * One audit event (ListAuditEvents `details.events[]`). `actor` is the acting
 * colonel's PUBLIC identity (extid or email — never an internal objid), `verb`
 * the dotted action name (e.g. `customer.set_role`), `target` the affected
 * resource's public id. `detail` is the op's redacted context — free-form
 * (hash / string / null), so it stays `unknown` and is rendered as JSON.
 * `created` arrives as a Unix-second float and is transformed to Date.
 */
export const colonelAuditEventSchema = z.object({
  id: z.string(),
  actor: z.string(),
  verb: z.string(),
  target: z.string(),
  result: z.string(),
  detail: z.unknown(),
  created: transforms.fromNumber.toDate,
});

/**
 * The shared pagination envelope plus the audit filters the server echoes
 * back (`actor` substring, `verb` exact-or-category-prefix).
 */
export const colonelAuditPaginationSchema = paginationSchema.extend({
  actor: z.string().nullable().optional(),
  verb: z.string().nullable().optional(),
});

/** Audit list response details: rows + pagination-with-filter-echo. */
export const colonelAuditEventsDetailsSchema = z.object({
  events: z.array(colonelAuditEventSchema),
  pagination: colonelAuditPaginationSchema,
});

export type ColonelAuditEvent = z.infer<typeof colonelAuditEventSchema>;
export type ColonelAuditEventsDetails = z.infer<typeof colonelAuditEventsDetailsSchema>;
