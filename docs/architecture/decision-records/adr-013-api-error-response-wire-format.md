---
id: "013"
status: proposed
title: "ADR-013: API 4xx/5xx Error Response Wire Format"
---

## Status

Proposed

## Date

2026-05-26

## Context

Backend error responses for the JSON APIs (v2, v3, account, organizations, domains) had drifted into two incompatible shapes:

- Application errors (`RecordNotFound`, `FormError`, `Forbidden`, `LimitExceeded`, `EntitlementRequired`, `GuestRoutesDisabled`) emitted `{ error: <class-name>, message: <user-facing text> }`. Some variants omitted one field or used `code:` instead of a type.
- Otto router fallbacks for `not_found` and `server_error` emitted `{ message:, code: }` (in `base_json_api.rb`) or `{ error: <message> }` with no type (in V1/V2).

The frontend compensated with fallback chains (`details.message || details.error`) and ambiguous interfaces (`HttpErrorLike` accepting `data?: { message?: string }`). `error:` carrying a class name forced callers to guess whether the field was machine-readable or user-readable.

Rodauth, which OTS already runs on the auth surface, emits `{ error: <user-facing message>, "field-error": [...] }`. That convention is the de facto standard the rest of the stack was being measured against.

## Decision

**4xx and 5xx JSON responses emit `{ error: <user-facing message>, error_type: <class name> }`.**

- `error` is the field the frontend displays. It is always a sentence aimed at the end user.
- `error_type` is the field the frontend branches on. It is the Ruby class name (`RecordNotFound`, `FormError`, `Forbidden`, `LimitExceeded`, `EntitlementRequired`, `GuestRoutesDisabled`, `NotFound`, `ServerError`).
- Class-specific fields may accompany the pair without renaming it: `field` on `FormError`, `error_key` for i18n lookup, `retry_after`/`attempts`/`max_attempts` on `LimitExceeded`, `entitlement`/`current_plan`/`upgrade_to` on `EntitlementRequired`.
- `code` is reserved for per-operation discriminators that are not redundant with `error_type`. `GuestRoutesDisabled` uses it (`GUEST_CONCEAL_DISABLED`, `GUEST_REVEAL_DISABLED`, ...) because the class is one and the operations are many. New errors should justify a `code` before adding one; in most cases `error_type` is sufficient.
- `request_id` is a cross-cutting correlation field (not class-specific). The Otto error handlers (`Onetime::Application::OttoHooks`) echo the request's `x-request-id` into every typed error body so an API consumer who reports an error gives us an id that appears verbatim in the `RequestLogger` request-log line (which logs `request_id` plus, now, the `error_type`). It is informational only — the frontend does not branch on it. The static `router.not_found`/`router.server_error` fallbacks are request-independent and omit it from the body; for those the `x-request-id` response header still carries the id. This supersedes the Otto-minted `error_id`, which is development-only in the body and logged without the `request_id`.

This applies uniformly to application errors raised from logic classes and to Otto router fallback responses (`router.not_found`, `router.server_error`).

The frontend reads only `error` for display and `error_type` for type branching. Fallback chains (`message || error`) are removed. The `HttpErrorLike` shape is `data?: { error?: string; error_type?: string }`.

Aligning on this shape mirrors Rodauth, removes the field-meaning ambiguity that produced the fallback chains, and lets `error_type` evolve independently of human-readable copy.

## Trade-offs

- **We lose**: backward compatibility for any external consumer reading `message:` on error responses. `GuestRoutesDisabled` is the most likely external break (documented in PR #3221 as a wire-format change).
- **We gain**: a single, unambiguous error contract across all JSON APIs. Frontend error handling collapses to two field reads.
## Out of Scope

- **V1 API.** Frozen by policy (see V1 application docstring). Existing V1 error bodies stay as-is.
- **Success-confirmation payloads.** Endpoints in `apps/api/domains/logic/**` that return `{ success: true, message: ... }` are not error responses and are not governed by this ADR.

## Future Considerations

Outside the scope of #3221 but on the long-term trajectory of this contract:

- **Centralize exception handling in `apps/web/billing` and the Roda auth app.** Both still flatten exceptions per-action, dropping class-specific fields. `apps/api/*` already centralizes via Otto request hooks; the remaining layers should follow.

- **Eliminate the `json_error` helper.** Once controllers raise typed exceptions and centralized handlers render them, `json_error` is redundant. Where only a message-string path exists today, introduce a typed exception subclass instead.

- **Frontend branches on `error_type`.** The HTTP error classifier currently uses status plus presence-of-message heuristics. Once `error_type` is reliable across the surface, it can branch on that directly.

- **Schema-validated contract spec.** Generalize the existing error-response shape spec into a structural assertion: every registered error class's `to_h` must validate against an ADR-013 JSON Schema. Broken shapes fail CI rather than surfacing as frontend bugs.

- **Extend `request_id` correlation to the Roda auth surface** (tracked in #3520). The `request_id` correlation field is currently echoed only by the Otto error handlers (`OttoHooks#with_error_correlation`). Typed errors on the `/auth` surface are rendered through `Auth::ErrorTranslator` and still omit `request_id` from the body and stash no `error_type` for `RequestLogger`. Until that handler echoes the id too, `request_id`-in-body is an Otto-app guarantee, not a whole-API one — on `/auth` the `x-request-id` response header remains the correlation handle.

## Implementation Notes

Migration tracked in #3221.

### Related ADRs

- ADR-003 (API Parameter Naming): general API field-naming guidance.
- ADR-010 (Error Handling at Layer Boundaries): when to raise vs. return a default. This ADR governs the wire shape once an error reaches the boundary.
