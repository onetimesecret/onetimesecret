# Handoff: auth-strategy specs fail under Full · SQLite after spec re-tiering

**Status:** OPEN — needs decision/investigation
**Area:** Rodauth / auth test infrastructure (PR #3239, `feature/3104-idp`)
**Work branch:** `claude/happy-hopper-DjiFk`
**Owner of original task:** "Get the GA workflow passing in a responsible manner."

---

## TL;DR

Getting the GA workflow green uncovered three layered problems. Two are **fixed and
verified green**; the third is **open**:

| # | Problem | Status |
|---|---|---|
| A | `PostgreSQL Migrations & Triggers` red: `EXPECTED_SCHEMA_VERSION` hardcoded `7`, real schema is `10` (OAuth migrations 008–010) | ✅ Fixed — Migration Tests workflow green |
| B | `T2 · Ruby Unit Tests` aborted: 20 auth specs boot full-mode Rodauth via the shared spec_helper but ran in the simple-mode unit tier → nil `db` → whole run aborted | ✅ Fixed — unit tier green (relocated to `integration/full`) |
| C | **`T3 · Ruby Integration (Full, SQLite)` red: 27 failures in the 3 relocated auth-*strategy* specs — auth fails on SQLite, passes on PostgreSQL** | ❌ **OPEN (this ticket)** |

The first re-run after B also surfaced a pre-existing latent bug (a stayer spec stubbed
`Auth::Database` without requiring it) — fixed in commit `c4094ee9`.

---

## Commits on `claude/happy-hopper-DjiFk`

- `474a076c` — `fix(test): derive PG suite schema version from migration files` (Problem A)
- `86b5d1dc` — `test(auth): relocate full-mode auth specs into integration/full tier` (Problem B; 20 file moves)
- `c4094ee9` — `fix(test): require auth/database in set_customer_verification_spec` (latent stayer bug)

All three are verified green **except** the SQLite integration job below.

## CI evidence (workflow_dispatch on the work branch)

- Migration Tests run `27048119964` → **all green** (confirms A).
- CI run `27048326493` (HEAD `c4094ee9`):
  - `T2 · Ruby Unit Tests` → **success** (confirms B; 0 → 1637 examples actually executing)
  - `T3 · Ruby Integration (Full, PG, billing on/off)` → **success**
  - `T3 · Ruby Integration (Full, PG agnostic, billing on/off)` → **success**
  - `T3 · Ruby Integration (Simple/Disabled), Smoke` → **success**
  - `T3 · Ruby Integration (Full, SQLite, billing: on)` (job `79839125862`) → **failure**
  - `T3 · Ruby Integration (Full, SQLite, billing: off)` (job `79839125887`) → **failure**

`1637 examples, 27 failures, 18 pending` — **all 27 failures are in the three relocated
strategy specs.**

---

## The open issue (C)

### Symptom

Under **Full mode on SQLite only**, every example in these three relocated specs fails:

- `apps/web/auth/spec/integration/full/session_auth_strategy_spec.rb`
- `apps/web/auth/spec/integration/full/noauth_strategy_spec.rb`
- `apps/web/auth/spec/integration/full/basic_auth_strategy_spec.rb`

The strategy's `#authenticate` returns `Otto::Security::Authentication::AuthFailure`
instead of a `StrategyResult`, so assertions like:

```
expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
expect(result.authenticated?).to be true
# and: undefined method `session'/`user'/`metadata' for an instance of …AuthFailure
```

all fail. The **same specs pass on Full · PostgreSQL** (both billing variants).

### Why this is surprising / notable

The strategy auth path touches **no SQL** — it is Redis/Familia-based:

- `base_session_auth_strategy.rb#authenticate` →
  `cust = Onetime::Customer.load_by_extid_or_email(external_id)` (Redis), then
  `load_organization_context(...)`, then `success(...)`.
  Returns `failure('[CUSTOMER_NOT_FOUND] …')` if the customer can't be resolved.
- `strategy_test_context.rb` creates the test customer **in Valkey/Redis only**
  (`Onetime::Customer.new(email:).save`), and the session env carries
  `external_id => test_customer.extid`.
- `grep` across `lib/onetime/application/auth_strategies/` shows **no** `Auth::Database`,
  `Sequel`, or `rodauth` references.

So a failure that depends on the SQL backend (SQLite vs PG) for a Redis-only auth path
points at **test-suite/shared-state interaction**, not the strategy logic itself.

### Important framing: these specs never actually ran in CI before

Before commit `86b5d1dc`, these specs lived in `apps/web/auth/spec/unit/` and were
executed by the **simple-mode** unit tier, where the shared auth spec_helper's
unconditional `require '../application'` crashed at load (`db` nil). The whole unit run
aborted, so **these examples had never executed in CI in any mode**. Relocating them to
`integration/full` made them run for the first time; they pass on PG and fail on SQLite.
This is newly *surfaced* behavior, not a regression in product code.

(Author intent note: `router_error_shape_spec.rb` was explicitly written to need "no
full-mode boot," and `helpers_spec` / `omniauth_tenant_helpers_spec` are described as pure
unit tests — yet all three transitively require the app-booting spec_helper. The root
cause behind Problem B is that `apps/web/auth/spec/spec_helper.rb` *unconditionally* boots
full-mode Rodauth for every consumer. Relocation treated the symptom; see "Options" #3.)

---

## Hypotheses for C (most → least likely)

1. **SQLite `:memory:` connection-scoping / shared-suite state.** The `:full_auth_mode`
   suite (`spec/support/full_mode_suite_database.rb`) connects one in-memory SQLite DB,
   stubs `Auth::Database.connection`, and force-boots the app once for the whole suite.
   Adding 20 specs changed suite composition/ordering. On SQLite the shared in-memory DB
   + force-boot may leave Familia/Redis config, encryption keys, or `Onetime` boot state
   in a condition where `Onetime::Customer.load_by_extid_or_email` (or
   `load_organization_context`) can't resolve the just-saved customer → `AuthFailure`.
   PG uses a real shared server and doesn't hit the in-memory-per-connection pitfall.
2. **Ordering-dependent pollution** exposed only in the SQLite job's execution order
   (deterministic: 27/27, both billing variants).
3. **A genuine SQLite-specific bug** somewhere in `load_organization_context` / customer
   resolution that only this newly-running spec exercises.

### Confirm which, fast

Add a one-line diagnostic (temporarily) or inspect the failure message: the strategy
returns a *specific* `failure('[CUSTOMER_NOT_FOUND] …')` vs `[SESSION_NOT_AUTHENTICATED]`
vs an `additional_checks` failure. The exact failure tag tells you whether the Redis
customer lookup is empty (→ Familia/Redis/boot-state hypothesis #1) or something later.
The full job log (`get_job_logs job_id=79839125887 tail_lines=2500`) has the
`Failure/Error` blocks starting ~line 1683; pull the lines just above each to capture the
`failure(...)` tag and any `[CUSTOMER_NOT_FOUND]` log entries.

---

## Options to resolve C

1. **Investigate & fix the SQLite/shared-suite interaction (preferred if the goal is
   real coverage).** Likely in `spec/support/full_mode_suite_database.rb` (boot/stub
   lifecycle) or the strategy specs' `before` hook (`Onetime.boot! :test unless
   Onetime.ready?` racing the suite's force-boot). This keeps the strategy specs running
   in full mode (where they belong) on both backends.
2. **Re-tier the strategy specs to where they pass.** They are session/Redis strategy
   tests; if they don't need the SQL backend, they may belong in `integration/simple`
   (or a dedicated path), not `integration/full`. They pass on Full·PG, so this is a
   judgement call about intended coverage.
3. **Fix the root cause behind Problem B instead of relocating** — give the auth spec
   suite a lightweight helper (or gate `require '../application'`) so genuine unit specs
   (`helpers_spec`, `omniauth_tenant_helpers_spec`, `router_error_shape_spec`, and these
   strategy specs) can run as fast unit tests without booting full-mode Rodauth. This
   would let several of the 20 relocated specs move *back* to the fast tier and likely
   sidesteps C entirely. Larger change; revisits the relocation.
4. **Quarantine** the 3 strategy specs from the SQLite job (tag + exclude) as a stopgap
   to get GA green now, with a follow-up issue for #1/#3. Least satisfying.

A maintainer decision is needed here because it's in the Rodauth/OmniAuth/OAuth area and
trades off coverage vs. effort vs. correctness.

---

## How to reproduce locally

> Note: the dev container used for this work has Ruby 3.3.6 and no bundle, so the suite
> could not be run locally; everything was verified via CI `workflow_dispatch`. Repro
> below assumes a working Ruby ≥3.4.7 + `bundle install`.

```bash
# Fails (SQLite full mode) — mirrors the red CI job:
AUTH_DATABASE_URL='sqlite::memory:' bundle exec rake spec:integration:full

# Passes (PostgreSQL full mode):
AUTH_DATABASE_URL_PG='postgresql://onetime_user:testpass@localhost:5432/onetime_auth_test' \
  bundle exec rake spec:integration:full:postgres

# Narrow to one relocated spec:
AUTH_DATABASE_URL='sqlite::memory:' AUTHENTICATION_MODE=full RACK_ENV=test \
  bundle exec rspec apps/web/auth/spec/integration/full/session_auth_strategy_spec.rb
```

Run the spec **as part of the full suite** (not in isolation) to reproduce — the
hypothesis is that the failure depends on shared-suite state, so a lone-file run may pass.

---

## Files of interest

- Relocated specs (now failing on SQLite): `apps/web/auth/spec/integration/full/{session_auth_strategy,noauth_strategy,basic_auth_strategy}_spec.rb`
- Shared context: `apps/web/auth/spec/support/strategy_test_context.rb`
- Strategy code (Redis-based, no SQL): `lib/onetime/application/auth_strategies/{base_session_auth_strategy,basic_auth_strategy,no_auth_strategy}.rb`
- Full-mode suite setup (prime suspect): `spec/support/full_mode_suite_database.rb`
- The unconditional app-boot at the heart of Problem B: `apps/web/auth/spec/spec_helper.rb` (≈line 111, `require_relative '../application'`)
- Tiering rules: `lib/tasks/spec.rake` (`spec:fast` → `spec:apps:web_auth`; `spec:integration:full`)
