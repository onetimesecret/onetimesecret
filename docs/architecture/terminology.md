# Common Framework Terminology

| This Codebase       | Common Term                  | Framework Examples                                     |
| ------------------- | ---------------------------- | ------------------------------------------------------ |
| Logic::Base         | Service Object / Interactor / Action | Rails service objects, Laravel Actions, Phoenix Contexts |
| OrganizationContext | Request Context / Current Attributes | Rails Current.organization, Laravel auth()->user()->organization |
| authorize_domain_sso! | Policy / Authorizer          | Pundit, CanCanCan, Laravel Policies, Phoenix authorize/3 |
| raise_concerns      | Before Action / Middleware   | Rails before_action, Laravel middleware, Phoenix plugs |
| Session org → Domain org | Tenant Resolution / Scope Binding | Multi-tenancy libraries (Apartment, acts_as_tenant)    |

## Deployment Topology Terminology

| Term | Meaning |
| ---- | ------- |
| **fleet** | The entire operated estate: every region/instance the Onetime Secret team runs, as opposed to third-party self-hosted installs (the ADR-030 sense: "not merely convenient for our fleet"). Never use "fleet" for the set of processes in one region — that coupling unit is a region/environment. "Fleet" is also fine for a managed population of like entities ("fleet of custom domains", "fleet of organizations" in colonel/domains tooling); that usage is correct. |
| **federation / federated** | The cross-region layer only: regional instances sharing identity/billing linkage via `FEDERATION_SECRET` (ADR-008: "shared per-federation-group", cross-region email hashing for billing federation). Correct wherever cross-region billing/identity is meant; a misuse is applying it to anything intra-region. |
| **region / jurisdiction** | One datastore-scoped operating unit: the app processes (web workers + background workers) sharing one Valkey/Redis and authdb. This is the decryption-coupling boundary — a secret encrypted in Region A never needs decrypting in Region B. Rollout constraints about mixed old/new code sharing a datastore are region-scoped (better: datastore-scoped), not fleet-scoped. |
| **environment** | A runtime mode such as `development`, `test`, or `production`, selected through `RACK_ENV`. It is independent of region/jurisdiction and must not be used as a synonym for a datastore or data-residency boundary. |
| **deployment / jurisdiction** | Interchangeable depending on context. "Jurisdiction" is the identifier/data-residency framing of a region (EU, US, NZ — see [regions.md](./regions.md), `JURISDICTION` env var); "deployment" is the install/rollout framing, including a self-hoster's single install. A self-hoster's deployment is its own single region. |

**Rollout invariants are datastore-scoped, not fleet-scoped.** Statements about code-version coupling through shared data (e.g. "deploy X everywhere before Y writes the new format") must be scoped to the datastore/region, not the fleet. Prefer the datastore-scoped phrasing — "no process may write the new format until every process reading that datastore is upgraded" — because it is also correct for self-hosters.

See [regions.md](./regions.md) for region/jurisdiction configuration, ADR-008 for federation, and ADR-030 for the fleet sense.

## Session Terminology

In `full` authentication mode a signed-in browser is backed by two records in two stores. Older code and prose call both "the session"; use these names instead. `lib/onetime/session/active_session_gate.rb` is the reference implementation of the distinction.

| Term | Meaning |
| ---- | ------- |
| **Rack session** | The per-request HTTP session at `env['rack.session']`, bound to the `onetime.session` cookie and stored by `Onetime::Session` as an encrypted blob at `session:<sid>` in Redis. Carries `authenticated`, `external_id`, `account_id` and the join key. Read by every per-request gate and by Rodauth alike. Say "session blob" only when the Redis storage primitive itself is the subject (the `del` behind `Operations::Sessions::Store`). |
| **active-session row** | A row in Rodauth's `account_active_session_keys` table in the authdb, primary key `(account_id, session_id)`, written by Rodauth's `active_sessions` feature at login. The account's sessions page, "sign out everywhere", Rodauth's inactivity/lifetime sweep and Rodauth Admin operate on these rows. Exists only in full mode. |
| **join key** | `active_session_id_hmac`: the HMAC of Rodauth's `active_session_id`, stamped into the Rack session at login by `apps/web/auth/config/features/active_sessions.rb`. Equal to the row's `session_id` column, the only form Rodauth persists. A Rack session without one (pre-stamp login, feature off) cannot be joined to a row and is skipped by the gate. |
| **revoke** | Remove an active-session row. Rodauth's verb. Since `Onetime::ActiveSessionGate`, revoking refuses the joined Rack session on its next request. Exception: the colonel console's per-customer "revoke" (`Operations::Sessions::RevokeForCustomer`) predates this distinction and is a destroy. |
| **destroy** | Delete a Rack session's blob from Redis. Logout does this; so do the colonel session operations. Ends the session regardless of the authdb. |
| **refuse** | Answer a request with 401 (Otto auth strategies) or `authenticated? == false` (`SessionHelpers`) while leaving the Rack session in Redis. The only thing `Onetime::ActiveSessionGate` does. A refused Rack session is replaced by the next login, or honoured again if it was refused only because its row could not be checked. |
| **gate verdict** | `:active` (row present), `:revoked` (row gone), `:unavailable` (authdb could not answer; refused, fail closed), `:skipped` (gate does not apply: not full mode, feature off, no join key). |
