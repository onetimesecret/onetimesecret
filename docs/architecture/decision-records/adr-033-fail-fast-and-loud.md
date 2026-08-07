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

Misconfiguration and missing dependencies rarely fail at the point where they
occur. A blank environment variable silently masks a YAML value; a rescue
block swallows an exception and returns nil; a fallback default lets the app
boot with a half-working feature. The failure surfaces later — at request
time, in production, for a user — far from its cause, and the diagnosis costs
hours instead of seconds.

Recent examples: blank `CUSTOM_MAIL_SES_*` variables masking `AWS_*`
fallbacks so SES auth failed only at send time; `TRUSTED_PROXY_ENABLED`
silently breaking host detection; billing config accepted at boot but
failing at checkout.

## Decision

When the system detects an invalid, contradictory, or incomplete state, it
fails at the earliest point of detection and says exactly what is wrong and
what is needed.

- **Boot over runtime.** Validate configuration at initializer/boot time, not
  first use. A required value that is missing or malformed raises at boot
  with the variable or key name in the message.
- **Raise over fallback.** Do not substitute a guessed default for a value
  the operator was supposed to provide. Degrading gracefully is reserved for
  genuinely optional features, and the degradation is logged.
- **Loud over quiet.** Never rescue-and-nil. Errors that are tolerated on
  purpose are logged with enough context (key, value shape, expected format)
  to fix them without a debugger.
- **Specific over generic.** "Missing key scope: `billing:write`" beats
  "configuration error".

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
