---
labels: admin-v2, rodauth, phase-1, backend, frontend
depends: rodauth-admin/00-scope, colonel-ui/11-admin-ui-kit, colonel-ui/12-resource-stores
status: Proposed
---

# Rodauth admin: aggregate visibility (stats + state-filtered lists)

## Context

Phase 1 of `rodauth-admin/00-scope.md`. Production runs
`AUTHENTICATION_MODE=full` with ~200k accounts in the authdb and **zero
sanctioned admin visibility** — the only existing surface is the dev-only,
unauthenticated stats stub in `apps/web/auth/routes/admin.rb`. This doc ships
the smallest change that gives operators real numbers: a read-only "Auth"
console section backed by indexed SQL queries.

Read-only throughout — **no mutations, so no AdminAuditEvent** (colonel-ui
CONTRACT 4: audit is for mutations). Recipe follows the uniform Phase-3
pattern from colonel-ui: **op → colonel route (BOTH auth layers) → screen on
the UI kit.**

## Scope

### Operations (`apps/web/auth/operations/accounts/`)

New namespace `Auth::Operations::Accounts`, mirroring the existing
`operations/customers/` pattern (single `#call`, stateless, immutable `Data`
result). Both ops read via `Auth::Database.connection` (restricted
`AUTH_DATABASE_URL` role — SELECTs only, never the migrations URL).

**`Accounts::Stats`** — one result object with:

| Metric | Query |
|---|---|
| `total_accounts` | `accounts.count` |
| `status_breakdown` | `accounts` grouped by `status_id` (1 Unverified / 2 Verified / 3 Closed) |
| `mfa_otp_accounts` | `account_otp_keys.count` |
| `mfa_webauthn_accounts` | `account_webauthn_keys` distinct `account_id` |
| `active_lockouts` | `account_lockouts` where `deadline > now` |
| `active_sessions` | `account_active_session_keys.count` |
| `unused_recovery_codes` | `account_recovery_codes` where `used_at IS NULL` (parity with dev stub) |
| `orphaned_accounts` | `accounts` where `external_id IS NULL` |
| `customer_count_delta` | `total_accounts` minus Familia customer count (drift signal — see risks) |

When `full` mode is off or the DB is unreachable, return
`{ available: false, reason: ... }` instead of raising — same
graceful-degradation contract as `GetUserDetails#fetch_stripe_billing`. The
detail page must never 500 because the authdb blinked.

**`Accounts::List`** — paginated, filter-driven:

- `filter: :locked` — join `accounts` × `account_lockouts` where
  `deadline > now`; columns: email, status, lockout deadline, failure count
  (`account_login_failures.number`), `external_id`.
- `filter: :orphaned` — `accounts` where `external_id IS NULL`; columns:
  email, status, created-ish signal if available.
- Rows carry `external_id` so the UI can link to
  `/colonel/customers/:extid` when present; orphan rows render inline only
  (no detail page exists for them — deliberate, see 00-scope open questions).

### Colonel API (`apps/api/colonel/`)

Two routes in `routes.txt`, both `auth=sessionauth role=colonel
scope=internal` (router layer) with `verify_one_of_roles!(colonel: true)` in
`raise_concerns` (logic layer):

```
GET /auth/stats     ColonelAPI::Logic::Colonel::GetAuthStats
GET /auth/accounts  ColonelAPI::Logic::Colonel::ListAuthAccounts   # ?filter=locked|orphaned&page=&per_page=
```

Logic classes are thin adapters over the ops, per `ListSessions` — param
coercion + role gate only.

### Frontend (`src/apps/admin/`)

- `AdminAuth.vue` view at `/colonel/auth`: stats grid on `StatCard`, the two
  filtered lists on `DataTable` behind a filter toggle, `full`-unavailable
  empty state when the op degrades.
- `sections.ts`: new entry `{ key: 'auth', group: 'identity' }` after
  `sessions`. Icon from the verified heroicons sprite set (`lock-closed` if
  present in `HeroiconsSprites.vue`, else add it).
- Zod schema `src/schemas/api/internal/responses/colonel-auth.ts` (NB: the
  schema path in colonel-ui/40 is stale; `internal/responses/` is current).
- New i18n keys in `admin-colonel.json` as bare `{"text": ...}` — no
  hand-authored hashes; leave hash-less in the feature PR
  (`locales:hashes` churn stays out of feature diffs).

### Performance guardrails (200k rows)

- Stats are nine cheap queries but not free × every nav render: compute in
  one op call, cache briefly server-side (align with whatever
  `GetColonelStats` does today; if it has no cache, a 60s memo is enough),
  and fetch once per page visit — never poll.
- Lists are paginated, `per_page` capped at 100. `filter` is a strict
  whitelist — no caller-supplied SQL fragments, no ordering by arbitrary
  columns.
- `WHERE external_id IS NULL` at 200k rows is a seq scan; acceptable at this
  size, but if it grows, add a partial index — note it in the op, don't
  pre-build it.

## Grounding — files & pointers

- Seed queries: `apps/web/auth/routes/admin.rb` (dev stub — superseded, then
  deleted in Phase 5)
- Schema: `apps/web/auth/migrations/001_initial.rb` (tables + indexes; note
  `account_lockouts.deadline`, partial unique email index),
  `006_omniauth_identities.rb`
- DB access: `Auth::Database.connection` (lazy proxy, already used outside
  `apps/web/auth` — health controller, `apps/api/account`, CLI)
- Ops contract: `lib/onetime/operations/README.md`; pattern:
  `apps/web/auth/operations/customers/show.rb`
- Logic pattern: `apps/api/colonel/logic/colonel/list_sessions.rb` (thin
  adapter, both auth layers, read-only = no audit)
- Routes: `apps/api/colonel/routes.txt`
- Nav: `src/apps/admin/sections.ts`; kit: `StatCard`, `DataTable`,
  `FilterBar`; views: `src/apps/admin/views/`
- Schemas: `src/schemas/api/internal/responses/colonel-*.ts`; axios via
  `useApi()`

## Acceptance criteria

- [ ] `Auth::Operations::Accounts::Stats` and `::List` exist, stateless,
      returning immutable `Data`; degrade to `available: false` (no raise)
      when `full` mode is off or the authdb is unreachable.
- [ ] `GET /auth/stats` and `GET /auth/accounts` guarded by BOTH auth layers.
- [ ] `filter` param strictly whitelisted (`locked`, `orphaned`); lists
      paginated with capped `per_page`.
- [ ] `AdminAuth.vue` renders stats + both lists; locked/orphan rows with an
      `external_id` link to the customer detail page; orphan rows without
      one render inline.
- [ ] Simple-mode / degraded state renders an explanatory empty state, not
      an error.
- [ ] Zod schema `colonel-auth.ts`; nav entry in `identity` band.
- [ ] Ops covered by specs (tryouts or RSpec per neighboring ops);
      logic specs assert the role gate.
- [ ] Only the restricted `AUTH_DATABASE_URL` credential is used.

## Notes / risks

- **Lockout rows linger.** Rodauth doesn't eagerly delete expired
  `account_lockouts`; every "locked now" read must filter `deadline > now`
  or the count inflates over time.
- **`active_sessions` is approximate.** `account_active_session_keys` retains
  rows until Rodauth's inactivity cleanup runs; label the stat "active
  session keys," not "users online."
- **`customer_count_delta` is a drift signal, not an invariant.** The Familia
  side comes from the existing customer counter, which is itself
  reconciliation-based; render as informational, alert-worthy only when large
  or growing.
- **Email display policy.** The lists surface account emails to colonels.
  Match whatever `ListUsers` does today (obscured vs. plain) — do not invent
  a third policy; orphan rows need enough of the email to be actionable.
- **Status-id mapping is positional.** 1/2/3 come from `account_statuses`
  seed data in `001_initial.rb`; read the labels from the table in the op
  rather than hardcoding, so a future status addition doesn't mislabel.
