# Native Domain Validation Readiness

## Purpose

This document records how far Onetime Secret is from natively validating and
serving custom domains with Caddy on-demand TLS, without Approximated.

Assessment date: 2026-08-20

Code baseline: `0c8c762b778a972c2041f1366c48fbd85e175200` (`origin/main`)

This is a static code assessment and engineering estimate, not a delivery
commitment. It complements the policy decisions in ADR-015 through ADR-018 and
`domain-validation-policy.md`.

## Executive assessment

The native Caddy path is scaffolded but is not end-to-end usable today.
`CaddyOnDemandStrategy` does not validate ownership or routing. It marks
ownership valid without a DNS lookup and leaves routing unknown. The ACME
permission endpoint correctly requires `CustomDomain#ready?`, but a domain
processed by the Caddy strategy cannot naturally become ready because its
`resolving` field is never populated.

Estimated remaining effort for one engineer familiar with this codebase:

| Completion target | Estimated effort | Result |
|---|---:|---|
| Secure, usable native Caddy path | **3–5 engineer-weeks** | Native TXT and routing checks, successful Caddy issuance, ownership gating, truthful minimum UI, tests |
| Migration-ready replacement for Approximated | **4–6 engineer-weeks** | Above plus per-domain strategy selection, rollout controls, operator visibility, and Caddy `permission` configuration |
| Full ADR-015–018 implementation | **6–10 engineer-weeks** | Above plus adaptive revalidation, bounded failure states, TXT challenge lifetime, and complete serving-status observability |

Calendar time may be longer because the estimate excludes review queues,
staged rollout dwell time, production DNS propagation, and infrastructure work
outside this repository. Some workstreams can overlap, so the totals are not a
simple sum of every row below.

## Current implementation

### Available foundations

- `CustomDomain` generates a 128-bit random TXT challenge using
  `SecureRandom.hex(16)` and stores ownership and routing booleans as
  `verified` and `resolving`.
- `VerifyDomain#persist_changes` already persists authoritative ownership and
  routing results returned by a strategy.
- The internal ACME endpoint performs a fast indexed domain lookup and then
  reads persisted state through `ready?`. DNS is not queried in the TLS
  handshake path, which is the correct operational shape.
- Sender-domain validation already provides DNS caching, timeout retries,
  parallel record checking, TXT matching, CNAME lookup, and error isolation in
  `lib/onetime/domain_validation/sender_strategies/base_strategy.rb`.
- The domain API and operator surfaces already expose combinations of
  `verified`, `resolving`, `verification_state`, and `ready` that can support a
  native status UI after the state contract is clarified.

### Confirmed gaps

| Area | Current code | Consequence |
|---|---|---|
| Caddy ownership validation | `CaddyOnDemandStrategy#validate_ownership` always returns `validated: true` | No account-level proof of control is performed |
| Native routing validation | `CaddyOnDemandStrategy#check_status` returns `is_resolving: nil` | `VerifyDomain` never writes `resolving` for Caddy domains |
| Certificate permission | `Application.domain_allowed?` requires `custom_domain.ready?` | A normally processed Caddy domain remains not ready, so the endpoint returns 403 and issuance is blocked |
| DNS lookup coverage | Shared sender machinery supports TXT, CNAME, and MX, but not A or AAAA | Native display-domain routing validation cannot yet cover address records |
| Routing policy | No configuration defines accepted CNAME targets or A/AAAA addresses for native serving | The resolver has no deployment-specific definition of “points to OTS” |
| Link-creation gate | V1 and V2 enforce ownership only when global `features.domains.require_verified` is true; default is false | Caddy and passthrough domains can be selected without mandatory native ownership proof |
| State model | `verification_state` combines `verified` and `resolving`; Caddy certificate state is not stored | Ownership, routing, and serving/certificate health cannot be reported independently |
| Frontend status | `useDomainStatus.ts` derives status only from Approximated `vhost.status` | Native Caddy domains cannot display truthful state |
| Strategy selection | `Strategy.for_config(config)` reads only the install-level strategy; `CustomDomain` has no validation-strategy field | Incremental per-domain migration in ADR-015 is unavailable |
| Revalidation | `DomainRefreshJob` runs at one fixed interval and always selects `0..batch_size-1` without a cursor | It is not per-domain adaptive, has no terminal state, and domains outside the selected batch may never be checked |
| Challenge lifetime | TXT challenge is generated at domain creation with no expiry or rotation | Ownership challenges remain reusable indefinitely |
| Caddy configuration | The ACME app, README, config comments, and example Caddyfile still use deprecated `ask` | Native deployment depends on a Caddy interface marked for removal |
| ACME integration tests | Endpoint specs stub `ready?` to true or false | Tests do not cover strategy result → persisted state → permission response |

The `validation_strategy` field under `CustomDomain::SignupConfig` is unrelated
to custom-domain certificate validation and does not implement ADR-015.

## Suggested implementation breakdown

### 0. Define native routing policy — 1–3 days

Before implementing the resolver, define the deployment contract:

- accepted CNAME target or targets;
- accepted IPv4 and IPv6 addresses, or how they are discovered from config;
- whether CDN or load-balancer targets are valid;
- apex-domain behavior where CNAME is unavailable;
- treatment of multiple answers, CNAME chains, DNS timeouts, and partial
  A/AAAA matches;
- cache bypass behavior when a customer explicitly retries verification.

This is the largest design uncertainty in the core path. The lookup code is
otherwise bounded and has an in-repository model to reuse.

### 1. Native DNS validation and Caddy issuance — 1–2 weeks

- Extract or adapt the sender-domain DNS primitives for display domains rather
  than coupling display-domain validation directly to mailer configuration.
- Add A and AAAA lookup support.
- Perform exact TXT challenge matching against `CustomDomain#validation_record`.
- Evaluate CNAME/A/AAAA answers against the routing policy.
- Return authoritative `validated` and `is_resolving` values from the Caddy
  strategy so `VerifyDomain` persists both axes.
- Keep all DNS and Caddy network work outside the ACME permission request.
- Add unit coverage for TXT matching, routing answers, timeouts, NXDOMAIN,
  cached results, multiple answers, and partial failures.
- Add an integration test covering Caddy strategy → `VerifyDomain` persistence
  → `CustomDomain#ready?` → ACME 200/403.

Exit condition: a correctly configured and owned domain reaches `ready?`, the
permission endpoint returns 200, and Caddy can issue a certificate. Incorrect
ownership or routing fails closed.

### 2. Safe customer-use gate — 1–1.5 weeks

- Make V1 and V2 link creation strategy-aware.
- Require native TXT ownership for `caddy_on_demand` and `passthrough`
  independently of the legacy global `require_verified` toggle.
- Preserve the existing configurable Approximated behavior unless a separate
  migration changes it.
- Add a rollout flag and compatibility window for existing passthrough
  installations, as required by ADR-017.
- Cover owner, organization member, public creation, canonical domain, and
  existing-domain migration cases.

Exit condition: no account can create links using a Caddy-managed domain until
that account has completed the native ownership proof.

### 3. Truthful state contract and UI — 0.5–1 week

- Expose ownership and routing as independent API/UI concepts.
- Stop using Approximated `vhost.status` as the universal source of truth.
- Render native ownership and routing guidance for Caddy domains.
- Keep Approximated-specific details and DNS widget behavior provider-specific.
- Represent externally managed certificate state explicitly for passthrough.

A minimum native UI can report ownership and routing before complete Caddy
certificate observability exists, provided it does not claim that routing means
a certificate was issued.

### 4. Migration and Caddy compatibility — 0.75–1.5 weeks

- Add nullable `CustomDomain#validation_strategy` and resolve it before the
  install-level default.
- Update every strategy factory call site to pass the domain where available.
- Show override and effective strategy in `domains doctor` or equivalent
  operator output.
- Provide a migration or administrative mechanism to set strategy by domain or
  regional batch.
- Update deployment documentation and examples from `ask` to Caddy
  `permission http`.
- Remove stale documentation claiming `check_verification=false` can bypass
  ownership verification; the HTTP handler intentionally ignores it.

Exit condition: operators can migrate domains incrementally, confirm effective
strategy, and use Caddy’s supported permission interface.

### 5. Adaptive revalidation and challenge lifetime — 2–4 weeks

- Add per-domain scheduling data such as `next_check_at`, consecutive failure
  count, and validation-window start.
- Schedule only due domains and advance each domain independently.
- Apply short intervals to new or recently changed domains and capped
  exponential backoff to repeated failures.
- Add an explicit, recoverable terminal state after the bounded retry window.
- Add a customer/operator action that restarts validation.
- Rotate or expire the TXT challenge with the same bounded lifecycle.
- Retire or migrate the fixed-slice `DomainRefreshJob` configuration.
- Add deterministic tests around time, backoff caps, terminal transitions,
  retries, and concurrent workers.

This is the largest implementation block because no per-domain scheduler state
or terminal lifecycle exists today.

### 6. Caddy certificate observability — 0.5–1.5 weeks

Choose a reliable certificate source of truth, then expose issuance success,
failure, and pending state independently of ownership and routing. Depending on
deployment architecture, this may require a Caddy API integration, event
receiver, or shared certificate-storage inspection. The uncertainty in that
choice accounts for the estimate range.

This is not required to make permission and issuance secure, but it is required
to claim complete implementation of ADR-016’s serving axis and to give users an
accurate end-to-end status.

## Milestones

### Milestone A: secure native MVP — 3–5 engineer-weeks

Includes routing policy, native DNS validation, successful Caddy permission,
strategy-aware ownership gating, a truthful minimum UI, and integration tests.
This is the minimum credible point for customer use without Approximated.

### Milestone B: migration-ready native service — 4–6 engineer-weeks

Adds per-domain strategy overrides, operator visibility, rollout controls, and
migration to Caddy `permission http`. This is the appropriate target for a
controlled regional cutover.

### Milestone C: complete policy implementation — 6–10 engineer-weeks

Adds adaptive revalidation, bounded terminal states, TXT challenge lifetime,
and complete certificate/serving observability. This satisfies the accepted
scope of ADR-015 through ADR-018 rather than only making Caddy issue
certificates.

## Estimate assumptions and risks

The estimates assume:

- one engineer with working knowledge of Ruby, Familia/Redis, Vue, DNS, and
  Caddy;
- existing test infrastructure is available;
- no new external service is required for DNS resolution;
- the native routing policy can be agreed in days rather than weeks;
- production Caddy topology and accepted targets are already known to
  operators;
- security and migration review occur during implementation.

Factors likely to increase the estimate:

- dynamic or region-specific target discovery;
- support for arbitrary CDN/proxy chains;
- a new durable scheduler or queue rather than adapting current job machinery;
- certificate state distributed across multiple Caddy nodes;
- migration requirements for a large population of existing passthrough
  domains;
- changes to the accepted ADR state model after implementation begins.

## Recommended order

Implement Milestone A first, but design the DNS result and persisted-state
contract so Milestone C can add scheduling metadata without changing the
meaning of ownership or routing. Do not begin with certificate observability or
the frontend alone: native TXT and routing validation are the dependency that
unblocks both secure issuance and truthful status.
