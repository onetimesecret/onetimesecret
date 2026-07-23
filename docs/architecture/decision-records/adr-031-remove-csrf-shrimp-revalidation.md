---
id: "031"
status: accepted
title: "ADR-031: Remove Client-Side CSRF Shrimp Revalidation"
---

## Status

Accepted

## Date

2026-07-22

## Context

The web client's CSRF store (`src/shared/stores/csrfStore.ts`) carried a
periodic-poll and Page-Visibility revalidation path: `startPeriodicCheck()`
ran a `setInterval` every 15 minutes and `initVisibilityCheck()` re-checked on
tab focus, both calling `checkShrimpValidity()`, which POSTed to
`/api/v3/validate-shrimp`.

This code was inert. Both entry points in `init()` were commented out, so
nothing invoked them in production. More importantly, the endpoint they targeted
never existed: `POST /api/v3/validate-shrimp` has no handler anywhere in the
backend. The Otto route table (`apps/api/v3/routes.txt`) defines 23 routes and
none is validate-shrimp; Otto matches exactly, so the call resolves to 404. The
handler was never migrated when the API moved to v3. The store was shipping a
validity probe against a non-existent endpoint, plus its schema, interval
constant, `isValid`/`intervalChecker` state, and four functions — all dead.

## Decision

Remove the periodic and Page-Visibility CSRF revalidation entirely (Option B).
Delete `checkShrimpValidity`, `initVisibilityCheck`, `startPeriodicCheck`,
`stopPeriodicCheck`, the `csrfResponseSchema`, `DEFAULT_PERIODIC_INTERVAL_MS`,
the `isValid` and `intervalChecker` state, and their now-unused imports. Do NOT
re-implement the endpoint or the polling. Keep the token-mirroring core: the
`shrimp` ref, `updateShrimp`, `init`, `$reset`, and the two watchers
(logout → `$reset`, bootstrap-refresh → sync `shrimp`).

## Trade-offs

A dedicated token-validity endpoint is an anti-pattern for this SPA. CSRF tokens
self-validate on use: the backend `InstrumentedAuthenticityToken` middleware
(`lib/onetime/middleware/security.rb`) checks the shrimp inline on every
state-changing request via the `X-CSRF-Token` header or `shrimp` form param. The
axios response interceptor rotates the token on every response, and a
refresh-before-submit path covers critical POSTs. Proactive polling therefore
adds background traffic and a TOCTOU window (a token validated by a probe can be
rotated or expired before the next real request) while providing no safety the
inline check does not already give. Removing it also deletes a live 404 caller.

One gap is acknowledged: revalidating a stale token when a backgrounded tab
returns to the foreground. This was the notional purpose of the visibility
check. It is not worth a validity endpoint. If it ever proves necessary, address
it narrowly by re-reading the token from the existing bootstrap refresh on
visibility change — NOT by reintroducing `/api/v3/validate-shrimp` or a polling
loop.

## Consequences

- No backend change: the endpoint never existed, so nothing to remove server
  side. The real CSRF middleware is untouched.
- `src/tests/stores/csrfStore.spec.ts` loses the 8 tests covering the removed
  API and its fake-timer / axios-mock setup; the init, watcher, and updateShrimp
  tests remain (the last with its `isValid` assertions stripped).
- Store surface shrinks to token mirroring only; the exported `CsrfStore` type
  is trimmed. No external consumer read the removed members.

## Related

- Issue #3839
- `src/shared/stores/csrfStore.ts`, `lib/onetime/middleware/security.rb`,
  `apps/api/v3/routes.txt`.
