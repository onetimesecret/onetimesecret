# Handoff — auth integration:full spec failures

## Context
- **Repo:** onetimesecret · **Branch:** `fix/ent-refinements`
- **Dir:** `/Users/d/Projects/dev/onetimesecret/onetimesecret`
- **Scope:** Fixing real failures in the `spec:integration:full` batch (issue #3126 area + a CreateCustomer bug)

## Goal
Make `spec:integration:full` green. The batch (`lib/tasks/spec.rake:134`) runs `apps/*/*/spec/integration/full` + `spec/integration/full` + `spec/integration/all` in ONE process under `AUTHENTICATION_MODE=full`.

## Current state (2026-05-29)
- **Results:** 349 examples, 2 failures, 3 pending
- **Done (committed + pushed):**
  - `1defb82df` fix(auth): CreateCustomer matches email index
  - `443ec7dc0` test(auth): repair pending_plan_intent spec (CSRF/path, real accessor check, skip-when-billing-disabled)
- **Uncommitted:**
  - `apps/web/auth/config/hooks/account.rb` — fix: gate `after_verify_account` hook on `verify_account_enabled?` instead of `Onetime.env?('testing')`. The old guard failed when verify_account feature is disabled (test env via auth.yaml), causing undefined method error.

## Fix applied this session
The boot error `undefined method 'after_verify_account' for Rodauth::Configuration` happened because:
1. `verify_account` feature is conditionally enabled based on `Onetime.auth_config.verify_account_enabled?`
2. The `after_verify_account` hook was guarded by `unless Onetime.env?('testing')` — wrong check
3. When `verify_account` feature isn't enabled, the DSL method doesn't exist

Fix: Changed guard from `unless Onetime.env?('testing')` to `if Onetime.auth_config.verify_account_enabled?`

## Remaining 2 failures
Both in `omniauth_csrf_spec.rb` — pre-existing test configuration issue:
- `omniauth_csrf_spec.rb:134` — expects redirect to IdP, gets `sso_not_configured`
- `omniauth_csrf_spec.rb:150` — expects state parameter in redirect, gets `sso_not_configured`

Root cause: OmniAuth tenant config isn't set up for the test host. The `omniauth_tenant.rb` hook checks for tenant config and redirects with `sso_not_configured` when not found. These tests need tenant setup or should be skipped when no tenant is configured.

## Key decisions (and why)
- **Prior #4/#5 diagnoses were wrong.** "Auth::Config create_account undefined" and "auth app not mounted" were garbled-output artifacts — they never reproduced. Disregard entirely.
- **No cross-spec pollution.** The 5 real failures reproduce standalone, identical counts in-suite (2+3). Unit specs (e.g. `billing_spec.rb`) run in a separate process from integration specs, so they can't pollute.
- **CreateCustomer bug:** `find_or_create_customer` used `Customer.exists?(email)`, but Familia `exists?(identifier)` checks the **objid**, never the email index → existing customers fell through to `create!` and raised `RecordExistsError`. Fixed to `email_exists?`/`find_by_email` + normalize once (mirrors `create!`).
- **pending_plan_intent HTTP 403:** raw `post '/login'` hit the CSRF-protected main app. rodauth mounts at `/auth` (`apps/web/auth/application.rb:19`). Fixed: POST `/auth/login` with a CSRF shrimp token (GET `/auth` → `X-CSRF-Token` header → post with `shrimp:`).
- **Billing gate is correct, do not change it.** `add_billing_redirect_to_response` (the `after_login` hook) is registered only when `billing.enabled == 'true'` (`apps/web/auth/config.rb:145`). Everything in `Billing.configure` is checkout-redirect logic. The reusable `pending_plan_intent` lifecycle (capture/clear) already lives ungated in `account.rb` (capture L226-249, surface+clear L287-346, with `rescue LoadError`). The 2 login-fallback HTTP tests assert billing-gated behavior, so they were **skipped when billing disabled** — not "fixed."
- **after_verify_account guard:** Changed from env check to feature check because the Rodauth feature's DSL method only exists when the feature is loaded.

## Next steps
1. **Commit the account.rb fix** — it's necessary and correct.
2. **Fix omniauth_csrf_spec.rb tests** — either:
   - Set up tenant config for test host in the spec's `before` block
   - Add skip condition when tenant config not available (similar to the 404 skip already there)
3. Open PR for `fix/ent-refinements`, or continue if other ent-refinement work pends.
4. (Deferred) Billing-enabled harness for the 2 pending login-fallback tests, if real coverage is wanted.

## Commands
```bash
# Full authoritative batch (rake sets RACK_ENV=test automatically)
bundle exec rake spec:integration:full

# The two target files (explicitly set RACK_ENV=test)
RACK_ENV=test AUTHENTICATION_MODE=full \
  bundle exec rspec \
  apps/web/auth/spec/integration/full/omniauth_account_creation_spec.rb \
  apps/web/auth/spec/integration/full/pending_plan_intent_flow_spec.rb
```

## Key files
- `apps/web/auth/config/hooks/account.rb:263` — the fix (uncommitted)
- `apps/web/auth/operations/create_customer.rb` — the prior fix
- `apps/web/auth/spec/integration/full/pending_plan_intent_flow_spec.rb` — spec repairs + skip guard
- `apps/web/auth/config/hooks/billing.rb` — billing-gated hook (read-only; do not ungate)
- `apps/web/auth/config/hooks/account.rb` — ungated pending_plan_intent lifecycle
- `apps/web/auth/config.rb:145` — the billing gate
- `apps/web/auth/config/features/account_management.rb:16` — verify_account feature enable
- `lib/tasks/spec.rake:134` — batch definition
- `spec/integration/full/rodauth_hooks_spec.rb:38-60` — the CSRF-token pattern to copy
