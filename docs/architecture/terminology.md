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
| **region / environment** | Interchangeable. One datastore-scoped operating unit: the app processes (web workers + background workers) sharing one Valkey/Redis and authdb. This is the decryption-coupling boundary — a secret encrypted in Region A never needs decrypting in Region B. Rollout constraints about mixed old/new code sharing a datastore are region-scoped (better: datastore-scoped), not fleet-scoped. |
| **deployment / jurisdiction** | Interchangeable depending on context. "Jurisdiction" is the identifier/data-residency framing of a region (EU, US, NZ — see [regions.md](./regions.md), `JURISDICTION` env var); "deployment" is the install/rollout framing, including a self-hoster's single install. A self-hoster's deployment is its own single region. |

**Rollout invariants are datastore-scoped, not fleet-scoped.** Statements about code-version coupling through shared data (e.g. "deploy X everywhere before Y writes the new format") must be scoped to the datastore/region, not the fleet. Prefer the datastore-scoped phrasing — "no process may write the new format until every process reading that datastore is upgraded" — because it is also correct for self-hosters.

See [regions.md](./regions.md) for region/jurisdiction configuration, ADR-008 for federation, and ADR-030 for the fleet sense.
