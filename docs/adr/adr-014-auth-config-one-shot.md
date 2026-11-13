---
id: 014
status: accepted
title: ADR-014: Auth::Config is One-Shot (Not Reconfigurable)
---

## Status
Accepted

## Date
2026-05

## Context

`Auth::Config < Rodauth::Auth` can be configured exactly once per process. A `@configured` class-level guard enforces this; without it, a second `configure do ... end` block corrupts the class.

Rodauth's `Configuration#apply` mutates the auth class in two irreversible ways:

1. **`routes.concat`** — appends route entries. A second apply duplicates every route with no dedup.
2. **`include`** — inserts feature modules into the ancestor chain. Ruby has no public API to remove an included module from a class.

Because both operations are additive and non-idempotent, "reset and reconfigure with different feature flags" is not possible on an existing class instance.

An earlier implementation exposed `reset_configuration!` that flipped `@configured` back to `false`. It did **not** undo routes, included modules, or method definitions. Calling it then re-running `configure` would double-register routes and re-execute hook blocks that assume single-run semantics. The method was removed.

## Decision

**Accept the one-shot constraint rather than fight it.**

### Production

Production reads ENV once at boot and never reconfigures. The guard is dormant — it exists only as a safety net against accidental re-entry from code reloading or registry discovery.

### Tests

Tests that need different feature flag combinations use one of two patterns:

**Pattern 1: Fresh Roda app per example (preferred)**

`RodauthTestHelper.create_rodauth_app` builds an anonymous `Class.new(Roda)` with the desired features. Each spec gets its own class — no shared state, no contamination.

```ruby
let(:app) do
  create_rodauth_app(db: db, features: [:base, :login, :otp]) do
    otp_issuer 'Test'
  end
end
```

**Pattern 2: ENV capture/restore (integration tests)**

Integration tests that boot the full application capture `AUTH_*` env vars before loading `Auth::Config` and restore them in `after(:all)`, preventing feature-flag leakage between spec files.

## Consequences

### Positive

- Clear mental model: configure once, run forever
- No subtle bugs from partial reconfiguration
- Tests use fresh anonymous classes — true isolation

### Negative

- Cannot toggle features at runtime without process restart
- Integration tests that boot the real app must coordinate ENV carefully

### Neutral

- Upstream rodauth changes should be monitored on each version bump for a potential class-reset API (none as of v2.42)

## Implementation Notes

### 2026-05: Initial acceptance

Guard implemented at `apps/web/auth/config.rb:51-54`. `reset_configuration!` removed. Test helpers documented in `apps/web/auth/spec/spec_helper.rb`.

Related: #3238, #3104
