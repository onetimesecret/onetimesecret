# Auth::Config is a one-shot — by design of rodauth, not by choice

## Constraint

`Auth::Config < Rodauth::Auth` (apps/web/auth/config.rb:21) can be configured
exactly once per process. The `@configured` guard at lines 51-54 enforces
this (with the flag flipped at line 161); without the guard, re-running the
`configure do ... end` block would corrupt the class.

## Why it's structural — not a flag we can flip

`Rodauth::Auth.configure` (gems/rodauth-2.42.0/lib/rodauth.rb:394-396) calls
`@configuration.apply(&block)`. `apply` (line 340-343) unconditionally calls
`load_feature(:base)` followed by `instance_exec(&block)`. `load_feature`
(line 355-363) does:

```ruby
@auth.routes.concat(feature.routes)   # appends — no dedup
@auth.send(:include, feature)          # includes module into class
```

Calling `configure` twice on the same class:

1. Re-appends `:base` routes (duplicates in the routing table).
2. Re-includes feature modules (no-op for the module list — Ruby dedups
   `Module#include` — but auth_methods that wrap with `alias_method` get
   re-aliased to themselves, which is fine for `:base` but unsound for any
   feature whose configuration block defines new value-methods).
3. Worse, *any feature added in the second pass* gets `include`d into the same
   class that already has all the first-pass features. There is no public
   Ruby API to remove a module from a class's ancestor chain.

So "reset and re-configure with new feature flags" cannot be implemented by
toggling a guard. It requires recreating the class:

```ruby
Auth.send(:remove_const, :Config)
Auth::Config = Class.new(Rodauth::Auth)
# Re-require every features/*.rb file (they reopen Auth::Config::Features)
# Re-register rodauth-omniauth and rodauth-oauth plugin definitions
# Update every memoized reference: Auth::Router's rodauth(:main),
#   Auth::Application's @rodauth_class, etc.
```

That is invasive, has no upstream support, and is not warranted for the
problem at hand.

## Why `reset_configuration!` was removed

Earlier versions of `Auth::Config` exposed a `reset_configuration!` method
"for testing only" that flipped `@configured` back to `false`. It did
**not** undo:

- `@features` (the Set of enabled feature symbols)
- `@routes` (the Array of route handler method names)
- Included feature modules in the class's ancestor chain
- Instance methods grafted by `def_auth_method` / `def_auth_value_method`
- Hooks bound via `before_*` / `after_*`

Calling it and then `configure` again would trigger the double-include /
append problems above. With no production callers and no spec callers,
keeping it around was a footgun named "for testing only" that did not
actually deliver safe re-configuration. It was removed in favor of the
capture-and-restore ENV pattern documented under "Convention going forward"
below.

## What surfaces this constraint

ENV variables read at configure time (`Onetime.auth_config.oauth_enabled?`,
`sso_enabled?`, etc.) become immutable in-process. Any test that:

1. Sets `AUTH_*_ENABLED` before requiring the auth application.
2. Triggers `Auth::Config.configure`.
3. Unsets / changes the ENV.
4. Expects subsequent code paths to observe the new value.

…will see the *first* configure call's choices forever in that process.

The leak that landed in `5541ae845` (May 2026) was a unit spec setting
`AUTH_OAUTH_ENABLED`, `OAUTH_JWT_RSA_PRIVATE_KEY`, and
`OAUTH_SP_DEV_CLIENT_SECRET` via `||=` at file load. Sibling integration specs
expected those unset and got rodauth methods they hadn't asked for. The
fix bounded contamination by capture-and-restore in
`before(:all)/after(:all)`. It does not solve the class-immutability
problem — it only ensures that *which* feature flags were live during the
first configure call match the integration specs' expectations.

## Maintenance signal

If anyone tries to call `Auth::Config.configure` a second time without
resetting:

- The guard at lines 51-54 hits and the block returns immediately. Existing
  state is preserved. Nothing breaks. Nothing changes.

If anyone removes the guard:

- Routes for `:base` get appended again (extra entries in the routing table —
  whether this is harmful depends on rodauth-internal dedup in route
  dispatch).
- Any feature whose `configure` block was conditional on a flag that flipped
  between the two calls gets `include`d on top of the already-configured
  class. The feature's methods become available; the corresponding flag-off
  configure path cannot be undone.
- In short: the second `configure` can only *add* features, never remove
  them, and may re-alias methods unpredictably.

## What would need to change upstream

Rodauth would need to either:

1. Expose a class-reset entry point that detaches all included feature
   modules and clears `@features` / `@routes`. Ruby has no native module
   removal, so this would mean tracking feature insertions and rebuilding
   the class on reset.
2. Move feature gating from class-definition time to request time, so the
   class always includes every feature but each feature's handler checks
   the live config. This is a much larger change and would invert the
   "enable" convention rodauth has used since v1.

Neither is on the rodauth roadmap as of v2.42.

## Convention going forward

- Set `AUTH_*_ENABLED` env vars **before** any spec or boot path triggers
  `Auth::Config.configure`. The auth `spec_helper.rb` (apps/web/auth/spec/spec_helper.rb:114-115)
  reloads `auth_config` then requires `application.rb`, which is where
  configure runs.
- If a spec file needs different flag values than the rest of the suite,
  capture-and-restore ENV in `before(:all)/after(:all)` so the leak is
  bounded to that file (see `5541ae845`). The first-loaded spec wins on
  *which configure choices are baked*; later specs must work with whatever
  the first one selected.

## Links

- Tracking issue: #3238
- Spec workaround: commit `5541ae845`
- Boot-path fix (load order): commits `73b9b3ff3`, `88d675bb5`
- Rodauth feature/configure source: `gems/rodauth-2.42.0/lib/rodauth.rb`
  lines 340-396
