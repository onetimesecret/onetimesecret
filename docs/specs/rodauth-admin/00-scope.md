---
labels: admin-v2, rodauth, scope
depends: colonel-ui/11-admin-ui-kit, colonel-ui/12-resource-stores, colonel-ui/21-admin-audit-log
status: Proposed
---

# Scope: web admin UI for the Rodauth (`full`-mode) authentication system

## The gap

The Colonel admin console (`src/apps/admin/`, epic `colonel-ui`) is comprehensive for
`Onetime::Customer` — the Familia/Redis model. It has **zero visibility into
Rodauth's SQL-backed account state**, which only exists when
`AUTHENTICATION_MODE=full`. The entire `colonel-ui` epic (00–61) never
references Rodauth or the `full`-mode schema — confirmed by grep across its 20
docs. The only "admin" surface for the SQL side today is
`apps/web/auth/routes/admin.rb#handle_admin_routes`: a dev-only (`if
Onetime.development?`) stats stub with **no role check**, unreachable in any
other environment.

**Deployment status**: production runs `full` mode with ~200k accounts in the
authdb (confirmed 2026-07-09). This is a **live operational gap**, not
forward-looking infrastructure: operators currently have no sanctioned way to
see account status, lockouts, MFA state, or active SQL sessions for any of
those accounts. Phase 1 below is remediation work.

## Non-goals

- No second admin app or API namespace. Per `colonel-ui` D2/D3: reuse the
  existing Page controller, fold new routes into `apps/api/colonel/`, new
  screens into the existing `identity` band in `src/apps/admin/sections.ts`.
- No replacement of the existing Familia-backed Customers screen. Rodauth
  account data is additive context on top of it, not a parallel resource.
- No rework of the two-layer authz model (`role=colonel` router gate +
  `verify_one_of_roles!` in Logic) — reuse it as-is.
- No change to `apps/web/auth/routes/admin.rb` itself as part of this scope
  beyond deleting it once superseded (it's dead-end code, not a foundation).

## Design: graft per-account state onto Customer detail; one aggregate surface

Verified: `accounts.external_id` (nullable, unique) is populated by
`sync_auth_accounts_command.rb` with `customer.extid`, and is kept in step
going forward per that command's comment ("linking them via external_id for
future synchronization"). So `accounts.external_id == Customer.extid` is a
real, existing join key, not a fact to be introduced.

**Decision: graft Rodauth account panels onto the existing Customer detail
page** (`AdminCustomerDetail` / `GetUserDetails`), gated on
`Onetime.auth_config.full_enabled?` and presence of `Customer.extid` in
`accounts.external_id`. Do not build a parallel per-account detail resource —
Rodauth state is one more tab/panel on a page an admin already reaches by
searching a customer.

At 200k production accounts, per-account grafting alone is not enough:
aggregate questions ("which accounts are locked out right now", "how big is
the unverified backlog", "how many SQL accounts have no matching Redis
customer") can only be answered by a surface you reach *without* already
knowing the customer. So one new read-only nav entry is in scope after all:

**An "Auth" section in the `identity` band** (per D3 — cross-cutting, central)
covering:

- Aggregate stats: total accounts, status breakdown
  (Unverified/Verified/Closed), MFA adoption (OTP + WebAuthn), active
  lockouts, active SQL sessions — the same numbers the dev stub already
  computes, now behind real authz.
- Sync coverage / drift: `accounts` rows with `external_id IS NULL` (orphans),
  and the accounts-vs-customers count delta. With dual persistence at this
  scale, drift is an operational metric, not an edge case.
- Operational lists reachable by *state*, not by customer: currently locked
  accounts, orphan accounts. These are indexed SQL `WHERE` queries — cheap at
  200k rows, and impossible to express against the Familia customer list
  (whose SCANs already cap at 10k).

## Capability surface

Enumerated from `apps/web/auth/migrations/001_initial.rb` +
`apps/web/auth/migrations/006_omniauth_identities.rb` cross-referenced against
enabled features in `apps/web/auth/config.rb` / `config/features/*.rb` — only
listing tables backing an **enabled** feature:

| Table(s) | Feature | Admin capability |
|---|---|---|
| `accounts`, `account_statuses` | `create_account`, `verify_account` | status (Unverified/Verified/Closed), created/updated |
| `account_login_failures`, `account_lockouts` | `lockout` (conditional: `lockout_enabled?`) | failure count; view/clear lockout |
| `account_otp_keys`, `account_recovery_codes`, `account_otp_unlocks` | `otp`, `recovery_codes` (conditional: `mfa_enabled?`) | MFA status; disable MFA; regenerate recovery codes |
| `account_webauthn_keys`, `account_webauthn_user_ids` | `webauthn` (conditional: `webauthn_enabled?`) | list/remove passkeys |
| `account_active_session_keys` | `active_sessions` (conditional: `active_sessions_enabled?`) | view/revoke SQL-backed sessions — see dual-authority note below |
| `account_jwt_refresh_keys` | JWT (base) | view/revoke API refresh tokens |
| `account_password_reset_keys`, `account_verification_keys`, `account_login_change_keys` | `reset_password`, `verify_account` | pending tokens; resend/expire |
| `account_email_auth_keys` | `email_auth` (conditional: `email_auth_enabled?`) | pending magic-link tokens |
| `account_identities` | `omniauth` (conditional: `omniauth_enabled?`/`orgs_sso_enabled?`) | linked SSO providers; unlink |
| `account_password_change_times`, `account_previous_password_hashes` | `change_password` | password age; reuse-history count (not the hashes themselves) |
| `account_authentication_audit_logs` | `audit_logging` | read-only per-account auth event timeline — see below |

Every mutation here needs a new `Auth::Operations::*` (or extends existing
`Auth::Operations::Customers::*`) verb, a colonel route with both auth layers,
and an `AdminAuditEvent` entry, per the existing `colonel-ui` mutation
contract (D4).

## Two subtleties

**Two audit trails, not one.** `account_authentication_audit_logs` is
Rodauth's own record of auth *events* (login, password change, MFA setup) per
account — read-only, rendered as a timeline. `AdminAuditEvent` is Colonel's
record of *admin actions* (an operator revoking a session, clearing a
lockout). Every mutation added here writes the latter; the former is display
data. Don't conflate them in the UI or the data model.

**Session-store dual authority.** The existing Sessions console
(`src/apps/admin/views/AdminSessions.vue`, `ListSessions` /
`GetSessionDetail`) reads the Familia session store — the `simple`-mode
authority. In `full` mode, `account_active_session_keys` (SQL) is the
authoritative session store instead; Familia sessions may not exist for
Rodauth-authenticated users at all. Make the existing console
**mode-aware** — same screen, authoritative backing store swapped per
`Onetime.auth_config.mode` — rather than shipping a second near-duplicate
sessions screen. This is the one place parity work and new work intersect;
sequence it accordingly (see phasing below).

## Where this lives (concrete)

- Ops: new `apps/web/auth/operations/accounts/*` (mirrors the existing
  `apps/web/auth/operations/customers/*` pattern), reusing
  `Auth::Database.connection` — already a global, lazily-connected proxy
  reachable from `apps/api/colonel` today (used elsewhere outside
  `apps/web/auth`, e.g. `apps/api/account`, CLI). No new plumbing needed to
  reach the DB from the colonel API layer.
- Routes: new `apps/api/colonel/logic/colonel/*` adapters, thin per the
  existing pattern, guarded by both auth layers.
- Frontend: one new "Auth" section (`src/apps/admin/sections.ts`, `identity`
  band) for the aggregate surface, plus new conditionally-rendered panel(s) on
  the existing customer detail view. Orphan-account rows in the aggregate
  lists link
  nowhere initially (no customer page to link to) — display email + status
  inline; a dedicated orphan-account detail view is deferred until Phase 1's
  coverage numbers show whether orphans are a population or a handful.
- Scale notes (200k rows): aggregate counts and `WHERE`-filtered lists are
  fine on indexed columns, but don't recompute five `COUNT(*)`s on every
  request — cache the stats read-out briefly (same pattern as the Overview
  dashboards) and paginate every list. `account_active_session_keys` and
  `account_authentication_audit_logs` are the growth tables; audit-log
  display must be per-account + paginated, never table-wide.

## Phasing (sequence, not full sub-specs yet)

1. **Aggregate visibility** (the immediate ask): the "Auth" section —
   aggregate stats, sync-coverage/orphan metrics, locked-accounts list.
   Read-only, no mutations, no joins to build; smallest change that gives
   operators real numbers for the 200k accounts. Its coverage query also
   answers the orphan open question below.
   **Spec: `10-aggregate-visibility.md`.**
2. **Per-account read-only panels**: account status/MFA/session/SSO panels on
   the customer detail page via the `extid`/`external_id` join,
   `full_enabled?`-gated. Establishes the join and the display shape.
3. **Session console mode-awareness**: swap in SQL-backed
   `account_active_session_keys` as the `full`-mode session authority in the
   existing Sessions console + customer detail "sessions" panel. In `full`
   mode the current console is showing operators the wrong store.
4. **Mutating operations**: lockout clear, MFA disable/reset, session/JWT
   revoke, SSO unlink — each with typed-confirmation dialog + AdminAuditEvent,
   following the `colonel-ui` D4 contract exactly.
5. **Cleanup**: delete `apps/web/auth/routes/admin.rb`'s dev stub once its
   stats are subsumed by Phase 1.

## Open questions

- ~~Confirm whether any environment runs `full` mode~~ — resolved 2026-07-09:
  production, ~200k accounts. Phase 1 is remediation.
- Orphan accounts (no matching `Customer.extid`): Phase 1's coverage query
  produces the actual count; decide on a dedicated orphan detail view (vs.
  inline-only display in the aggregate lists) from that number, not
  speculation.
- Whether `account_previous_password_hashes` count should be shown at all
  (it's history-count only, never hash material, but confirm no PII-adjacent
  concern from security review before shipping).
- Which colonel DB credential reads the authdb: the restricted
  `AUTH_DATABASE_URL` role is sufficient for everything here (Phase 1–3 are
  SELECTs; Phase 4 mutations are DELETE/UPDATE on token tables) — confirm no
  one reaches for the elevated migrations URL out of convenience.
