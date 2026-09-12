// src/schemas/api/internal/responses/session-handle.ts
//
// The one definition of the colonel-facing session identifier, shared by the
// GLOBAL sessions console (colonel-sessions.ts) and the PER-CUSTOMER session
// panel (colonel-customer-sessions.ts). It lived on the per-customer contract
// until #4330 extended handles to the global console; both now import it here so
// a single regex guards every session identifier that reaches the admin UI.

import { z } from 'zod';

/**
 * The non-reversible session handle (F-01): the first 32 hex chars of an
 * HMAC-SHA256 over the raw sid (SessionMetadata.handle_for). Validating the
 * exact shape — not just z.string() — makes the schema a security tripwire:
 * a backend regression that leaks the raw 64+-char sid (or anything else)
 * under a *_handle key fails parsing here instead of flowing a replayable
 * bearer value into the admin UI.
 */
export const sessionHandleSchema = z
  .string()
  .regex(/^[0-9a-f]{32}$/, 'session_handle must be a 32-char lowercase hex handle');
