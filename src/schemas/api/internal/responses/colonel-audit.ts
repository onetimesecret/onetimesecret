// src/schemas/api/internal/responses/colonel-audit.ts
//
// Per-resource colonel/admin schemas for the Audit Log screen (observability).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). This is the read side of the
// ColonelAuditEvent flight recorder (every mutating admin op writes one):
//
//   - ListColonelAuditEvents → GET /api/colonel/audit (newest-first list + filters)
//
// Shape verified against the live logic class
// (apps/api/colonel/logic/colonel/list_colonel_audit_events.rb), a read-only slice of
// the capped `colonel_audit_event:events` sorted set. Reading the log never
// writes an audit event (CONTRACT 4).

import { createApiResponseSchema } from '@/schemas/api/base';
import { paginationSchema } from './colonel';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * One audit event (ListColonelAuditEvents `details.events[]`). `actor` is the acting
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

// Wrapped response schema for the colonel Audit Log screen (observability).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import this DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the registry key (`colonelAuditEvents`) links
// it to the ListColonelAuditEvents logic class for OpenAPI generation.

// GET /api/colonel/audit → ListColonelAuditEvents
export const colonelAuditEventsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelAuditEventsDetailsSchema
);

export type ColonelAuditEventsResponse = z.infer<typeof colonelAuditEventsResponseSchema>;

// GET /api/colonel/audit/export → ExportColonelAuditEvents
//
// NO schema here, deliberately. That endpoint answers with `text/csv` or
// `application/x-ndjson` plus a `Content-Disposition: attachment` header — it is
// a download, navigated to rather than fetched and parsed, so there is no JSON
// envelope for Zod to describe and nothing in the frontend ever validates it.
// Declaring one would register a wire contract that no code path exercises.
// (Same reasoning as the no-SCHEMA note on the ColonelAuditEvent model itself.)
//
// The export is still contract-bound where it matters: it serialises exactly
// the fields `colonelAuditEventSchema` above types, because both surfaces go
// through the one server-side allowlist (Onetime::ColonelAuditReader::FIELDS).
// Change the allowlist and BOTH the JSON list response and the download change
// together — so this schema stays the single description of an audit event's
// shape, whichever surface it arrives on.
