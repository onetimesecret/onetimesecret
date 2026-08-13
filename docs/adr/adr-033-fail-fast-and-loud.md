---
id: '033'
status: accepted
title: 'ADR-033: Fail Fast and Loud'
---

## Status

Accepted

## Date

2026-08-06

## Context

Configuration and dependency errors tend to surface far from their cause.
Common patterns include a blank environment variable overriding a configured
value, a rescue block that swallows an exception and returns nil, and a
fallback default that lets the application boot with a partially working
feature. In each case the failure appears later — at request time, in
production — where diagnosis is expensive, rather than at the point the
invalid state was introduced.

The codebase has accumulated these patterns organically. This ADR records a
uniform policy for how invalid state is detected and reported.

## Decision

When the system detects an invalid, contradictory, or incomplete state, it
fails at the earliest point of detection and reports exactly what is wrong
and what is needed.

- **Boot over runtime.** Validate configuration at initializer/boot time,
  not at first use. A required value that is missing or malformed raises at
  boot with the variable or key name in the message.
- **Raise over fallback.** Do not substitute a guessed default for a value
  the operator was expected to provide. Absent optional config may fall back
  to a documented default; present-but-invalid config is always an error.
  Graceful degradation is reserved for genuinely optional features, and the
  degradation is logged.
- **Loud over quiet.** Never rescue-and-nil. Errors that are tolerated on
  purpose are logged with enough context (key, value shape, expected format)
  to fix them without a debugger.
- **Specific over generic.** "Missing key scope: `billing:write`" is
  actionable; "configuration error" is not. The operator should be able to
  fix the problem from the error message alone.
- **Local over remote.** Fail-fast applies to what we control: config
  presence, shape, contradictions, internal invariants. These are
  deterministic — surfacing them once at boot beats N times at runtime
  (Nygard, *Release It!*). It does not apply to third-party reachability.
  Boot must not make live calls to external APIs: doing so couples our
  availability to theirs, proves little (up at boot is not up at minute
  five), and turns restarts into crash-loops during exactly the incidents
  when third parties are least reliable. Instead, validate credential and
  identifier *format* at boot (presence, expected prefix, type), defer live
  verification to first use or a readiness check, and log remote failures
  with enough error discrimination to distinguish a bad identifier from a
  transient outage. Hard local dependencies (our own database) may block
  readiness with retry-and-backoff and loud logging rather than
  exit-once-and-die; cold-start ordering is normal.

## Consequences

- Deployments with bad config fail visibly at startup instead of limping
  into production. This is the intended behavior, not a regression.
- Optional-feature detection must be explicit (`enabled?` guards), since
  absence of config can no longer be silently treated as "off" for required
  subsystems.
- Boot-time validation code grows; it is cheap insurance and belongs in
  initializers next to the feature it guards.
- Tests exercise failure paths: a misconfiguration should have a spec
  asserting the raise and its message.
- Boot validation stays offline. A wrong-but-well-formed credential passes
  boot and surfaces at first use or in a readiness check — that gap is
  accepted in exchange for restarts that never depend on a third party.
