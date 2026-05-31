# ADR: Auth::Config is one-shot (not reconfigurable)

## Status

Accepted (May 2026)

## Context

`Auth::Config < Rodauth::Auth` can be configured exactly once per process.
A `@configured` class-level guard enforces this; without it, a second
`configure do ... end` block corrupts the class.

### Root cause

Rodauth's `Configuration#apply` mutates the auth class in two irreversible
ways:

1. **`routes.concat`** — appends route entries. A second apply duplicates
   every route with no dedup.
2. **`include`** — inserts feature modules into the ancestor chain. Ruby has
   no public API to remove an included module from a class.

Because both operations are additive and non-idempotent, "reset and
reconfigure with different feature flags" is not possible on an existing
class instance.

### Why `reset_configuration!` was a footgun

A previous implementation exposed:

```ruby
def self.reset_configuration!
  @configured = false
end
```

This flipped the guard without undoing any structural mutations (routes,
included modules, method definitions). Calling it then re-running
`configure` would:

- Double-register every route
- Re-include feature modules (no-op for ancestors, but triggers
  `included` hooks again)
- Re-execute hook blocks that assume single-run semantics

The method has been removed.

## Decision

### Production

Production reads ENV once at boot and never reconfigures. The guard is
dormant — it exists only as a safety net against accidental re-entry from
code reloading or registry discovery.

### Tests

Tests that need different feature flag combinations use one of two
patterns:

#### Pattern 1: Fresh Roda app per example (preferred)

`RodauthTestHelper.create_rodauth_app` builds an anonymous `Class.new(Roda)`
with the desired features. Each spec gets its own class — no shared state,
no contamination.

```ruby
let(:app) do
  create_rodauth_app(db: db, features: [:base, :login, :otp]) do
    otp_issuer 'Test'
  end
end
```

#### Pattern 2: ENV capture/restore (integration tests)

Integration tests that boot the full application capture AUTH_* env vars
before loading `Auth::Config` and restore them in `after(:all)`, preventing
feature-flag leakage between spec files:

```ruby
before(:all) do
  @saved_env = ENV.select { |k, _| k.start_with?('AUTH_') }
  # ... set test-specific env vars ...
  boot_onetime_app
end

after(:all) do
  ENV.reject! { |k, _| k.start_with?('AUTH_') }
  @saved_env.each { |k, v| ENV[k] = v }
end
```

#### Pattern 3: Recreate-class workaround (last resort)

If a test suite genuinely needs to reconfigure `Auth::Config` itself (not
just a fresh anonymous class), the class must be entirely reconstructed:

```ruby
Auth::ConfigRecreator.with_fresh_config(features: { mfa: true }) do
  # Auth::Config is a brand-new class here
  # All memoized references (Auth::Router, etc.) are stale
end
```

This is invasive because it requires:

1. Removing the old `Auth::Config` constant
2. Creating a new `Class.new(Rodauth::Auth)`
3. Re-requiring every `config/*.rb` file (they reopen the class namespace)
4. Re-registering with the Roda plugin system
5. Updating every memoized reference

Use Pattern 1 instead whenever possible.

## Consequences

- `Auth::Config` is immutable after first configuration
- No `reset_configuration!` method exists
- Tests that need feature variation use fresh anonymous classes
- The recreate-class pattern exists as documented escape hatch but carries
  high maintenance cost
- Upstream rodauth changes should be monitored on each version bump for
  a potential class-reset API

## Related

- Issue: #3238
- Parent: #3104 (OAuth/OIDC IdP feature)
- `apps/web/auth/config.rb` — the `@configured` guard
- `apps/web/auth/spec/spec_helper.rb` — ENV capture/restore helpers
- `apps/web/auth/spec/support/config_recreator.rb` — recreate-class utility
