# Operator-managed domains

Status: Proposed; specification only, not implemented.

Tracking: [#4607](https://github.com/onetimesecret/onetimesecret/issues/4607).

## Summary

Operator-managed domains separate permission to use a registered domain from observations about whether that domain resolves or serves valid HTTPS. The canonical strategy is `operator_managed`, its display name is “Operator-managed domains,” and certificate management remains external. Operator policy authorizes only a trusted current registration; it never authorizes an arbitrary Host or SNI name and never permits internal certificate issuance.

This document defines proposed runtime behavior. Existing runtime booleans, strategy classes, APIs, caches, schedulers, and certificate gates do not yet satisfy this contract; configuration changes alone do not activate the behavior described here.

## Goals

- Operator-controlled deployments use trusted registered domains without TXT challenges.
- Authorization, ownership evidence, DNS health, HTTPS health, and certificate management remain separate concepts.
- Every protected consumer uses one request-time authorization decision.
- A switch to either TXT-enforced strategy rejects policy-only authorization on the first protected request.
- API, bootstrap, CLI, admin, and customer surfaces report canonical strategy names and typed outcomes.

## Non-goals

- Treating DNS resolution, expected-target matching, HTTPS success, or certificate issuance as ownership proof.
- Making unrestricted tenant domain registration safe by selecting `operator_managed`.
- Adding a new per-domain strategy-selection mechanism or customer-facing selector. This proposal uses ADR-015's operator-set per-domain override and install-level fallback.
- Prescribing a reverse proxy, DNS provider, certificate provider, CNAME shape, or deployment address.
- Probing private networks.
- Migrating or preserving behavior for an installed passthrough user base.

## Terminology

- **TXT-enforced strategy**: `approximated` or `caddy_on_demand`.
- **Current registration**: a live domain record whose canonical hostname lookup resolves to that record, whose organization exists, and whose active assignment lineage belongs to that organization.
- **Assignment lineage**: the identity of one uninterrupted assignment of one canonical hostname to one organization. It is distinct from the hostname and domain record identifier.
- **Trusted registration**: a current registration created, transferred, or adopted while operator-managed registration trust is explicitly enabled.
- **Protected consumer**: a runtime surface that serves, publishes, selects, or issues credentials for a custom-domain hostname.
- **Health observation**: a timestamped DNS, expected-target, or HTTPS result. It is not authorization evidence.
- **Effective strategy**: the canonical strategy selected for the exact current domain registration by applying ADR-015's per-domain override first and the install-level strategy second.

## Strategy configuration contract

### Names, aliases, and display

| Accepted input | Canonical strategy | Display name |
| --- | --- | --- |
| `operator_managed` | `operator_managed` | Operator-managed domains |
| `passthrough` | `operator_managed` | Operator-managed domains |
| `external` | `operator_managed` | Operator-managed domains |
| `approximated` | `approximated` | Approximated |
| `caddy_on_demand` | `caddy_on_demand` | Caddy on-demand TLS |
| `caddy` | `caddy_on_demand` | Caddy on-demand TLS |

Strategy input matching is case-insensitive and ignores surrounding whitespace. The existing `caddy` → `caddy_on_demand` normalization remains unchanged.

`operator_managed` is the default when the selected `validation_strategy` is absent, null, or blank. `passthrough` is not a canonical output value.

For every domain-specific operation, strategy resolution receives the exact current `CustomDomain` registration and selects its nonblank per-domain `validation_strategy` override before the install-level `features.domains.validation_strategy` value, as required by ADR-015. Normalization, strictness, defaulting, authorization, health reporting, and certificate behavior apply to that effective per-domain strategy. A protected consumer that cannot resolve the exact current registration and its effective strategy fails closed; it does not fall back to install-level authorization semantics. Changing either a per-domain override or the applicable install-level value creates a new strategy revision for affected domains.

### Unknown values

- With `strict_strategy: true`, a nonblank unknown strategy is a configuration error. Startup or configuration activation fails; no fallback strategy becomes active.
- With `strict_strategy: false`, a nonblank unknown strategy produces an operator-visible warning and resolves to the default `operator_managed` strategy.
- Unknown-value fallback does not bypass the trusted-registration requirement. Without trusted registration or another eligible basis, the resulting authorization basis is `none`.

### Canonical output

Every bootstrap, API, CLI, admin, and frontend capability payload emits the effective canonical strategy. Domain-specific payloads resolve and emit the per-domain override or install-level fallback that applies to that registration. For a selected unset value, `passthrough`, `external`, or a non-strict unknown value, both `validation_strategy` and any retained legacy strategy field such as `type` emit `operator_managed`. Raw aliases and unknown configured strings are never emitted as the effective strategy.

The canonical capability metadata for this mode contains:

```text
validation_strategy: operator_managed
display_name: Operator-managed domains
certificate_management: external
requires_txt_proof: false
```

Strict-mode rejection produces no effective-strategy payload because the configuration does not activate.

### Trusted-registration prerequisite

Operator-policy authorization is disabled unless the deployment explicitly enables operator-managed registration trust. Enabling it is an operator attestation that every principal permitted to create, transfer, or adopt custom-domain registrations is trusted to assign those hostnames.

The attestation applies prospectively. It marks a lineage trusted when that lineage is created, transferred, or adopted; it does not retroactively trust an existing lineage. A pre-existing registration becomes trusted only through an explicit operator adoption action, which ends the prior lineage and creates a new trusted lineage. Disabling the attestation immediately makes `operator_policy` ineligible but does not invalidate eligible TXT proof or an active explicit override.

Open signup, ordinary organization ownership, an entitlement, or self-hosted deployment status does not imply trusted registration. Deployments that permit untrusted users to register arbitrary domains do not enable this attestation.

## Authorization model

### Authorization bases

The authorization result is a typed value with exactly one effective basis:

| Basis | Meaning |
| --- | --- |
| `txt_proof` | Eligible TXT evidence proves control for the current assignment lineage. |
| `explicit_override` | An active operator override authorizes the current assignment lineage. |
| `operator_policy` | The effective strategy is `operator_managed` and the current registration is trusted. |
| `none` | No eligible basis authorizes the current registration. |

The authorization result contains at least `authorized`, `basis`, canonical `strategy`, current `assignment_lineage`, and a stable denial reason when `basis` is `none`.

### Request-time decision

Authorization is evaluated against the exact current registration and its effective per-domain strategy at every protected decision in this order:

1. A missing, orphaned, inconsistent, deleted, or non-current registration returns `none`.
2. An active explicit override bound to the current assignment lineage returns `explicit_override`.
3. Eligible TXT evidence bound to the current assignment lineage returns `txt_proof`.
4. A trusted current registration under `operator_managed` returns `operator_policy`.
5. Every other state returns `none`.

An unregistered Host or SNI name always returns `none`. A syntactically valid host, a host that reaches the deployment, and a host that resolves to deployment infrastructure remain unregistered until the current-registration conditions are satisfied.

Health observations do not participate in this decision. DNS failure, target mismatch, HTTPS failure, stale health, an inconclusive probe, or no scheduler never revokes `operator_policy`. Infrastructure failure can still make an authorized domain unreachable.

### Authorization truth table

`Y` in the override or TXT column means eligible evidence for the current lineage, not a legacy boolean.

| Current registration | Strategy | Trusted registration | Override | TXT proof | Authorized | Effective basis |
| --- | --- | --- | --- | --- | --- | --- |
| No | any | any | any | any | No | `none` |
| Yes | any | any | Y | any | Yes | `explicit_override` |
| Yes | any | any | N | Y | Yes | `txt_proof` |
| Yes | `operator_managed` | Y | N | N | Yes | `operator_policy` |
| Yes | `operator_managed` | N | N | N | No | `none` |
| Yes | `approximated` | any | N | N | No | `none` |
| Yes | `caddy_on_demand` | any | N | N | No | `none` |

An override remains the reported basis while active even when eligible TXT evidence also exists. A passing TXT check does not silently clear an explicit override.

## Evidence, provenance, and assignment lineage

### Evidence records

Eligible TXT evidence records all of the following:

- Canonical hostname.
- Assignment-lineage identifier.
- TXT challenge host and challenge-value identifier.
- Passing result and verification source.
- Strategy under which the check ran.
- Observation time.
- Invalidation state and, when invalidated, the reason and time.

Eligible override evidence records all of the following:

- Canonical hostname.
- Assignment-lineage identifier.
- Positive authorization decision.
- Operator identity or auditable operator principal.
- Creation time.
- Revocation state and, when revoked, the reason and time.

A legacy `verified`, `verified_by_override`, `resolving`, or `ready` boolean is not evidence. `verified_confirmed_at`, `verified_unconfirmed_since`, `updated`, or another timestamp without the complete provenance above is not evidence. Implementation does not synthesize TXT or override evidence from those fields.

### TXT evidence eligibility

Historical TXT proof remains eligible across strategy changes only while all of these conditions hold:

- The canonical hostname is unchanged.
- The assignment lineage is unchanged and current.
- The challenge identity and value are unchanged.
- No definitive later TXT failure invalidated the proof.
- No demotion ended the proof-bearing authorization lineage.
- Any existing confirmation-window requirement remains satisfied.

A health check, successful TLS handshake, certificate issuance, operator-policy authorization, process restart, or cache fill neither creates nor refreshes TXT evidence.

An indeterminate TXT check may retain eligible proof only through the existing bounded confirmation-window policy. The retained proof is still the prior proof record; the indeterminate attempt is not new evidence. A definitive missing or mismatched TXT result invalidates the proof immediately.

### Assignment lifecycle

| Event | Assignment lineage | TXT evidence | Override evidence | Operator policy |
| --- | --- | --- | --- | --- |
| Initial trusted registration | New lineage | None until a passing TXT check | None until explicitly created | Eligible under `operator_managed` |
| Strategy change only | Unchanged | Preserved if otherwise eligible | Preserved if active | Re-evaluated from target strategy |
| Transfer to another organization | New lineage | Prior evidence ineligible | Prior override ineligible | Eligible only if the new lineage is trusted |
| Orphaning | No current lineage | Ineligible | Ineligible | Ineligible |
| Orphan adoption | New lineage | Prior evidence ineligible | Prior override ineligible | Eligible only if the adopted lineage is trusted |
| Operator adoption of an existing untrusted registration | New trusted lineage | Prior evidence ineligible | Prior override ineligible | Eligible under `operator_managed` |
| Domain deletion | Lineage ended | Ineligible | Ineligible | Ineligible |
| Same hostname recreated | New lineage | Never inherited | Never inherited | Eligible only if the new lineage is trusted |
| Definitive TXT demotion | Lineage remains; proof-bearing authorization lineage ends | Invalidated | Active override remains active | May authorize only under `operator_managed` |
| Policy re-promotion after demotion | Lineage remains | Ended TXT proof remains ineligible | Active override remains active | Eligible under `operator_managed` when trusted |
| Later return to TXT enforcement | Lineage remains | Requires a new passing TXT check if prior proof ended | Active override remains eligible | Never eligible |

Transfer, orphan adoption, and operator adoption of an existing untrusted registration are authorization boundaries even when the domain record identifier or TXT fields are reused. Deletion and recreation are boundaries even when the hostname and challenge value happen to match.

## Immediate strategy-transition semantics

Effective-strategy activation is an authorization boundary, not a scheduler event. This includes activation caused by changing a per-domain override, changing the install-level fallback for a domain without an override, or removing an override so the install-level value applies. The first protected decision for each affected domain after activation uses that domain's target strategy and current-lineage evidence.

Authorization caches are valid only for the exact canonical strategy revision and assignment-lineage identifier that produced them. A revision or lineage mismatch is a cache miss and is evaluated fail-closed. A stale worker that cannot observe the active strategy revision does not serve a protected custom-domain request. Restarting a process does not recreate evidence from legacy fields.

Consequently, switching a domain from `operator_managed` to either TXT-enforced strategy immediately disqualifies `operator_policy`, whether the switch is per-domain or install-level. This applies before a scheduled job, manual verification, cache expiry, or restart. The scheduler can collect evidence and health; it is not the enforcement mechanism.

### Strategy-transition matrix

| From | To | Request-time authorization after activation | Certificate consequence |
| --- | --- | --- | --- |
| `passthrough` or `external` spelling | `operator_managed` spelling | No semantic transition; aliases normalize to the same strategy. | External management remains in effect. |
| `operator_managed` | `approximated` | `operator_policy` is ineligible immediately; current-lineage TXT proof or override is required. | Provider-managed operations are permitted only after eligible authorization. |
| `operator_managed` | `caddy_on_demand` | `operator_policy` is ineligible immediately; current-lineage TXT proof or override is required. | Internal ACME is denied until the basis is `txt_proof` or `explicit_override`. |
| `approximated` or `caddy_on_demand` | `operator_managed` | Existing eligible override or TXT proof remains the basis; otherwise a trusted current registration uses `operator_policy`. | Management becomes external; no internal request, renewal, replacement, or deletion occurs. |
| `approximated` | `caddy_on_demand` | Eligible current-lineage TXT proof or override remains valid. | Provider management stops; internal ACME follows the certificate matrix. |
| `caddy_on_demand` | `approximated` | Eligible current-lineage TXT proof or override remains valid. | Internal ACME stops; provider management follows the certificate matrix. |
| TXT-enforced | Same TXT-enforced strategy | Only eligible current-lineage TXT proof or override authorizes. | Existing strategy behavior continues. |
| Any | Strict unknown | Activation fails. | No target strategy becomes active. |
| Any | Non-strict unknown | Effective target is `operator_managed`; normal target-strategy rules apply. | Management is external. |

A strategy change is not operationally complete until the shared active revision is visible to every request-serving process. Runtime implementation provides an atomic activation barrier; direct datastore edits or a rolling configuration change that allows stale workers to keep granting `operator_policy` do not satisfy this specification.

## Protected-consumer contract

Every protected consumer resolves the exact current registration and authorization result. No consumer treats `verified`, `resolving`, `ready?`, provider status, certificate state, or health as an independent grant.

| Consumer | Required authorization | Health dependency | Behavior when unauthorized |
| --- | --- | --- | --- |
| Link creation and `share_domain` selection in every API version | Any authorized basis | None | Reject the custom domain; no branded link is created. |
| Incoming-secret link binding and other host-derived link creation | Any authorized basis | None | Reject before persisting a custom-domain link. |
| Auth-link host selection, email links, OAuth/OIDC redirect hosts, and WebAuthn tenant origin selection | Any authorized basis | None | Use the canonical allowlisted host; never emit the unauthorized custom host. |
| Tenant SSO initiation and callback | Any authorized basis for the same current lineage at both steps | None | Refuse tenant SSO; a lineage change during a flow invalidates the flow. |
| Tenant SAML SP entity ID and ACS URL publication | Any authorized basis | None | Withhold the identifiers. |
| Normal custom-domain page and API serving | Any authorized basis | None | Return the unrecognized-host response (`404`); do not render tenant data or silently serve canonical content on that Host. |
| Domain-context or custom-host selection in customer/admin APIs | Any authorized basis | None | Reject selection. |
| Domain management, health inspection, verification, adoption, transfer, override, and deletion surfaces | Organization/operator management authorization, not domain-use authorization | None | Remain available for remediation, but report the domain as unauthorized. |
| Bootstrap, customer domain APIs, admin APIs, and CLI status | None to report; authorization is data | None | Emit canonical strategy, typed authorization, evidence, health, and certificate-management fields. |
| Internal ACME permission endpoint | `txt_proof` or `explicit_override`, plus `caddy_on_demand` | None | Deny. `operator_policy` always denies. |

The protected-consumer authorization gate in this table is mandatory for every effective strategy. In particular, an `approximated` domain with `require_verified` absent or false still requires eligible current-lineage `txt_proof` or `explicit_override`; provider state and legacy verification booleans do not authorize it. When this proposal is accepted, this mandatory strategy-aware gate supersedes ADR-017's optional `require_verified` gate for `approximated`, as well as its `passthrough`-specific gate. `require_verified` may remain as compatibility configuration for behavior outside this protected-consumer contract, but it cannot weaken or bypass the authorization decision.

### Legacy output fields

The typed authorization and health fields are authoritative. If legacy fields remain in a response, they are derived as follows and are never consumed as evidence:

- `verified` is true only for an effective basis of `txt_proof` or `explicit_override`.
- `verified_by_override` is true only for an active current-lineage override.
- `resolving` is true for a fresh `resolved` DNS observation, false for a fresh `not_resolved` observation, and null for `unknown`, `stale`, or `unobserved` state.
- `ready` mirrors `authorization.authorized`; it does not imply healthy DNS or HTTPS.
- `verification_state` remains a presentation compatibility field and does not grant access.

Backend, frontend, CLI, and admin consumers move to the typed contract in one coordinated runtime change. There is no staged passthrough-client compatibility period.

## Health observation contract

Health checks run independently of authorization. A protected request neither waits for a probe nor requires a fresh successful observation.

A health run records each attempted outcome, its reason, `checked_at`, and the relevant addresses or certificate metadata. A current inconclusive attempt is reported as inconclusive; an older success may be shown only as historical context and is not presented as the current result.

### Freshness

The default health freshness interval is 3,600 seconds. A positive configured `features.domains.health.freshness_seconds` value replaces the default.

Each DNS, expected-target, and HTTPS observation has one freshness value:

| Freshness | Meaning |
| --- | --- |
| `fresh` | A result has `checked_at` no more than the configured interval ago. |
| `stale` | A result exists but is older than the configured interval. |
| `unobserved` | No attempt has produced a stored result. |

Freshness does not rewrite the typed outcome. A stale `resolved` result is reported as outcome `resolved`, freshness `stale`, not as currently healthy. Authorization never depends on freshness.

### DNS resolution outcomes

| Outcome | Meaning |
| --- | --- |
| `resolved` | At least one terminal A or AAAA address was observed, including when the other address family had an inconclusive result. |
| `not_resolved` | Authoritative NXDOMAIN, or complete NOERROR processing produced no terminal A or AAAA address. |
| `unknown` | No terminal address was observed and at least one lookup was inconclusive because of timeout, SERVFAIL, REFUSED, malformed response, CNAME loop, traversal limit, or another indeterminate condition. |

DNS resolution follows CNAMEs to terminal A/AAAA records, with a maximum of eight CNAME hops. A loop or exceeded limit is inconclusive for that lookup path. The observation reports the CNAME chain, each A and AAAA family outcome, the unique terminal IPv4 and IPv6 addresses, and whether the destination set is `complete` or `partial`. Resolution is independent of whether an address is public or expected.

A terminal address from either family makes the aggregate DNS outcome `resolved`. If the other family is inconclusive, the destination set is `partial` and the reason is `partial_family_failure`; for example, an A answer plus an AAAA timeout is DNS `resolved`, not `unknown`. A complete negative result for one family and terminal addresses from the other is a `complete` destination set, because both family outcomes are conclusive. If neither family yields an address, any inconclusive family or CNAME-path result makes the aggregate outcome `unknown`; only conclusive negative results for all lookup paths produce `not_resolved`.

### Optional expected-target outcomes

Expected-target checking is disabled by default. The optional `features.domains.health.expected_addresses` value is a list of exact, globally routable IPv4 or IPv6 literals. Blank entries, hostnames, CIDR ranges, wildcard values, and non-public addresses are invalid configuration. Address comparison uses normalized IP identity, including canonical IPv6 equivalence.

This deliberately conservative contract avoids recursively trusting another hostname and avoids broad CIDR matches. Deployments with dynamic CDN address pools leave the setting unconfigured unless they can maintain an explicit allowlist.

| Outcome | Meaning |
| --- | --- |
| `matched` | DNS is `resolved`, the destination set is `complete`, every observed terminal address is in the configured allowlist, and at least one address was observed. The configured list may contain additional addresses not observed in this run. |
| `mismatched` | DNS is `resolved` and at least one observed terminal address is absent from the configured allowlist, including when the destination set is `partial`. |
| `not_configured` | No expected-address list is configured. |
| `unknown` | Expected addresses are configured and no mismatch is observed, but DNS is `unknown` or `not_resolved`, or the resolved destination set is `partial`, so a complete destination set cannot be approved. |

Expected-target aggregation uses this precedence: `not_configured`; then `mismatched` when any observed address is outside the allowlist; then `unknown` for an incomplete or unavailable destination set; then `matched`. Thus an allowlisted A answer plus an AAAA timeout is `unknown`, while an unallowlisted A answer plus an AAAA timeout is `mismatched`. CNAME owner names and intermediate targets are not compared. Only terminal A/AAAA addresses participate. Target mismatch is an operational warning and never withdraws authorization.

### HTTPS outcomes

| Outcome | Meaning |
| --- | --- |
| `valid` | Every address in the complete public destination set completes a TLS handshake on port 443 with a trusted chain and hostname-valid certificate using the custom hostname as SNI. |
| `invalid` | At least one reachable TLS endpoint presents no certificate valid for the hostname or returns a definitive TLS failure. |
| `unreachable` | No address is `invalid`, and at least one public destination definitively refuses, resets, or closes the connection without completing TLS. |
| `not_checked` | DNS is not resolved, the destination set is partial, or the resolved address set is excluded by probe policy. |
| `unknown` | No address is `invalid` or `unreachable`, and at least one connection is inconclusive because of timeout, no route, probe-budget exhaustion, or internal probe failure. |

No HTTP request or application data is sent. Probes use bounded DNS, per-address connect and TLS budgets, and a bounded whole-run budget.

The complete resolved address set must be public before any connection occurs. A `partial` destination set is never dialed and reports HTTPS `not_checked` with reason `incomplete_address_set`; this includes an A answer plus an AAAA timeout. If the complete set contains any private, loopback, link-local, multicast, unspecified, reserved, or otherwise excluded address, no address in the set is dialed. A complete private-only result reports DNS `resolved` and HTTPS `not_checked` with reason `non_public_address`. A complete mixed public/private result reports DNS `resolved` and HTTPS `not_checked` with reason `mixed_public_private_addresses`. This whole-set rule preserves the public-network probe boundary and prevents partial probing or DNS-rebinding ambiguity.

When the complete set is public, every unique terminal IPv4 and IPv6 address is selected exactly once for the run, with IPv4 addresses first and each address family sorted by ascending unsigned network-byte value. DNS answer order does not affect selection or the aggregate result. Each selected address is assigned exactly one recorded outcome, and a connection attempt may begin at most once for that address. An attempted probe connects directly to the selected address on port 443 while using the custom hostname for SNI and certificate validation. If the whole-run budget expires before an address is attempted or before its attempt completes, that address receives outcome `unknown` with reason `probe_budget_exhausted`; no selected address is omitted from the observation.

The aggregate HTTPS outcome uses the following precedence across all per-address outcomes: `invalid`, then `unreachable`, then `unknown`, then `valid`. Therefore every address must be `valid` for the aggregate to be `valid`; one hostname-invalid certificate makes a mixed run `invalid`; otherwise one refusal or reset makes it `unreachable`; otherwise one timeout, internal error, budget-exhausted address, or other inconclusive result makes it `unknown`. Probing does not stop after the first failure except when the whole-run budget prevents further attempts, and all completed and uncompleted per-address outcomes remain reportable.

### Health triggers

Health observations may be collected by an authorized manual check or the configured scheduler. A newly registered domain starts with `unobserved` health. A disabled or delayed scheduler leaves health unobserved or stale; it does not manufacture success and does not affect authorization.

## Certificate-management contract

`operator_managed` means externally managed certificates. The application does not request, renew, replace, import, or delete a certificate or provider virtual host in this mode. External management does not imply that HTTPS is valid or reachable.

Automated provider orphan cleanup is subject to the current effective per-domain strategy at deletion time. It excludes every `operator_managed` domain, including an orphaned provider virtual host left by an `approximated` → `operator_managed` cutover. A cleanup task queued or initially checked under an earlier strategy must re-resolve the current registration, strategy revision, and effective strategy immediately before deletion; if the domain is now `operator_managed`, the task records a skipped `externally_managed` result and performs no provider deletion. This is not an exception to the no-deletion boundary.

The final effective-strategy check and provider `DELETE` are one linearized operation with respect to strategy activation. They run under a per-domain lock or lease held through the provider response, or an equivalent conditional strategy-revision fence that prevents activation from committing while the checked revision can authorize the deletion. Strategy activation uses the same fence. If `operator_managed` activation commits after an earlier cleanup check but before cleanup acquires the deletion fence, the final check observes the new revision and no `DELETE` is issued. If cleanup acquires the fence first, activation cannot become effective until the provider deletion reaches a terminal result. Revision mismatch, inability to establish a fence that spans the operation, or lease loss before dispatch aborts cleanup before issuing `DELETE`; lease loss after dispatch leaves activation blocked by an indeterminate-deletion marker until the provider result is reconciled.

Before activating an `approximated` → `operator_managed` cutover, the operator inventories provider certificates and virtual hosts and records an explicit disposition for each residual resource. Retention or deletion is performed directly in the external provider's control plane under the operator's change process, not by this application after activation. Residual resources remain visible in operator status until disposition is recorded; the application does not silently clean them up.

Operator policy never permits internal certificate issuance. Certificate success never creates authorization evidence.

### Certificate matrix

| Effective strategy | Authorization basis | Internal/provider certificate action | Management label |
| --- | --- | --- | --- |
| `operator_managed` | `operator_policy` | Denied; no internal action | `external` |
| `operator_managed` | `txt_proof` or `explicit_override` | Denied; no internal action | `external` |
| `operator_managed` | `none` | Denied | `external` |
| `caddy_on_demand` | `txt_proof` or `explicit_override` | Internal ACME permission may be granted | `caddy_on_demand` |
| `caddy_on_demand` | `none` | Denied | `caddy_on_demand` |
| `approximated` | `txt_proof` or `explicit_override` | Provider certificate/vhost action may proceed | `approximated` |
| `approximated` | `none` | Denied | `approximated` |

DNS, expected-target, and HTTPS health do not grant certificate permission. The certificate system or CA can still fail because infrastructure is unreachable or misconfigured.

## API and reporting contract

Customer, operator, API, bootstrap, and CLI surfaces distinguish all axes. A representative record is:

```text
Strategy: operator_managed
Authorization: authorized
Authorization basis: operator_policy
DNS: resolved (fresh)
Expected target: not_configured
HTTPS: unreachable (fresh)
Certificates: external
```

A domain response exposes:

- Canonical effective strategy and display name.
- `authorization.authorized`, `authorization.basis`, denial reason, and assignment-lineage identifier.
- Evidence summaries with type, eligibility, observation/creation time, lineage, and invalidation or revocation reason; secret challenge values are not exposed beyond existing authorized management surfaces.
- Typed DNS, expected-target, HTTPS, and freshness outcomes with reason and check time.
- Certificate-management mode.

An unknown or stale health result remains visibly unknown or stale. A prior successful value is not copied into the current outcome. Admin and management surfaces can distinguish a missing registration, untrusted lineage, absent evidence, invalidated evidence, and a strategy-cutover denial.

## Compatibility and rollout

- `passthrough` and `external` remain input aliases only.
- `caddy` remains an input alias for `caddy_on_demand`.
- Alias normalization does not create a strategy transition or data migration.
- There is no passthrough-user migration, deprecation window, feature-flag rollout, dual behavior, or staged old/new client period. The maintainer reports no installed passthrough user base requiring those mechanisms.
- Existing passthrough assumed-health behavior is removed rather than emulated. Initial health is `unobserved` and later results are observed values.
- Legacy booleans and timestamps are not upgraded into evidence. Affected TXT-enforced assignments require a new TXT pass or explicit override.
- Existing records do not become trusted lineages merely because the strategy defaults to `operator_managed`; operator adoption establishes prospective trust.

## Dependencies and constraints

- Trusted registration is a deployment and assignment prerequisite, not an inference from self-hosting.
- The active strategy revision and current assignment lineage are available to every protected request so stale workers and caches fail closed.
- Public-network egress protection applies to every HTTPS probe of a customer-controlled hostname.
- [ADR-015](../../adr/adr-015-domain-validation-per-domain-strategy.md) remains applicable. Its per-domain override and install-level fallback determine the effective strategy enforced on every protected request.
- [ADR-016](../../adr/adr-016-domain-validation-state-model.md) remains applicable to separation of proof and serving health. Its statement that passthrough has no health axis is replaced by this proposal when implemented.
- [ADR-017](../../adr/adr-017-domain-validation-link-creation-gate.md) remains applicable to the separation of authorization from certificate issuance. Its passthrough TXT requirement, staged passthrough rollout, and optional `require_verified` gate for `approximated` are replaced by the trusted `operator_managed` policy, no-migration decision, and mandatory protected-consumer authorization gate in this proposal when implemented.
- Until runtime implementation and explicit acceptance land, accepted ADRs and existing code remain the operative behavior.

## Acceptance criteria

### Strategy and output

1. With no configured strategy, bootstrap and domain APIs report `operator_managed` and “Operator-managed domains.”
2. Inputs `operator_managed`, `passthrough`, and `external`, in any case with surrounding whitespace, produce identical behavior and canonical output `operator_managed`.
3. Input `caddy` still produces canonical output `caddy_on_demand`.
4. A strict unknown value prevents configuration activation and produces no fallback payload.
5. A non-strict unknown value warns, activates `operator_managed`, emits only that canonical value, and does not authorize an untrusted registration.

### Registration and authorization

6. A trusted current registration under `operator_managed` is authorized as `operator_policy` without TXT evidence.
7. An unregistered hostname, orphaned record, missing organization, stale hostname index, or ended lineage is denied under `operator_managed`.
8. Enabling trusted registration does not retroactively authorize an existing lineage; explicit adoption creates a new trusted lineage.
9. Disabling trusted registration removes policy-only authorization on the first protected request while leaving eligible TXT proof and overrides usable.
10. DNS `not_resolved`, expected-target `mismatched`, HTTPS `invalid`, HTTPS `unreachable`, stale observations, and unobserved health each leave `operator_policy` authorization unchanged.
11. A successful DNS lookup, target match, HTTPS handshake, or certificate issuance creates no TXT evidence and no override.

### Evidence and lineage

12. A legacy record containing only `verified=true`, `resolving=true`, `ready=true`, `verified_by_override=true`, or confirmation timestamps has basis `none` under a TXT-enforced strategy.
13. A complete historical TXT evidence record remains eligible across a strategy-only change when hostname, challenge, assignment lineage, and confirmation-window requirements remain valid.
14. A definitive TXT mismatch invalidates prior TXT evidence immediately.
15. A policy re-promotion after TXT demotion does not make the ended TXT proof eligible again.
16. Transfer to another organization invalidates prior TXT proof and override, even when the domain record and challenge fields are reused.
17. Orphaning denies all use; later adoption creates a new lineage that inherits no proof or override.
18. Deleting and recreating the same hostname creates a new lineage that inherits no proof or override.
19. An active current-lineage override survives health failures and strategy changes until explicitly revoked or the lineage ends.
20. A passing TXT check does not silently revoke an active explicit override.

### Immediate cutover

21. After `operator_managed` → `caddy_on_demand`, the first protected request denies a policy-only assignment even when legacy booleans are true, health is healthy, the scheduler is disabled, and an old cache entry exists; the result is identical whether the effective-strategy change came from the domain override or the install-level fallback.
22. The same first-request denial applies to `operator_managed` → `approximated`, including a single domain whose override changes while other domains retain their prior effective strategies.
23. A stale worker unable to observe the active strategy revision fails closed rather than granting cached `operator_policy` authorization.
24. Restarting a worker does not reconstruct TXT or override evidence from legacy fields.
25. A current-lineage TXT pass or active override authorizes immediately under either TXT-enforced strategy without waiting for a health check.

### Protected consumers

26. Policy authorization permits link creation, custom-host serving, custom-domain API use, auth-link host selection, and tenant SSO under `operator_managed` regardless of health.
27. An unauthorized custom host returns the unrecognized-host `404` and does not render tenant or canonical content.
28. Auth links and OAuth/OIDC redirect hosts fall back to an allowlisted canonical host when custom-domain authorization is absent.
29. Tenant SSO initiation and callback both re-evaluate authorization and reject a flow whose assignment lineage changed between them.
30. SAML SP entity ID and ACS URL remain absent until the domain is authorized.
31. Domain management and health surfaces remain available to an authorized organization owner or operator when domain-use authorization is absent.
32. All API versions that create or bind custom-domain links enforce the same authorization result.
33. An `approximated` domain with `require_verified` absent or false and no eligible current-lineage TXT proof or override is denied by every protected consumer; setting a legacy `verified` boolean or observing provider success does not bypass the denial.

### Health

34. A CNAME chain ending in one or more A/AAAA records reports DNS `resolved` and includes the chain, per-family outcomes, destination-set completeness, and terminal addresses.
35. An A answer plus an AAAA timeout reports DNS `resolved` with a `partial` destination set and reason `partial_family_failure`; an allowlisted A answer yields expected-target `unknown`, and HTTPS is `not_checked` with reason `incomplete_address_set` without any connection attempt.
36. An unallowlisted A answer plus an AAAA timeout reports expected-target `mismatched`, while HTTPS remains `not_checked` with reason `incomplete_address_set` without any connection attempt.
37. NXDOMAIN and complete NOERROR with no terminal addresses report `not_resolved`; when no address is observed, timeout, SERVFAIL, REFUSED, a CNAME loop, or more than eight CNAME hops report `unknown`.
38. Without expected addresses, target status is `not_configured`, never `matched`.
39. With expected addresses, a complete multi-address result is `matched` only when every observed address is allowlisted; one additional observed address makes it `mismatched`.
40. Expected-target configuration rejects hostnames, CIDRs, wildcard entries, and non-public addresses.
41. Every unique address in a complete public multi-address set is selected exactly once in normalized order, independently of DNS answer order, and receives exactly one recorded outcome; each address is attempted at most once.
42. HTTPS aggregation follows `invalid` > `unreachable` > `unknown` > `valid`: mixed valid/invalid is `invalid`, mixed valid/refused is `unreachable`, mixed valid/timeout is `unknown`, and only all-valid addresses produce `valid`.
43. Whole-run budget exhaustion records each selected address that was unattempted or whose attempt did not complete as `unknown` with reason `probe_budget_exhausted` and makes the aggregate `unknown` unless a higher-precedence completed failure exists.
44. A complete private-only DNS result reports DNS `resolved` and HTTPS `not_checked` with `non_public_address`, without a connection attempt.
45. A complete mixed public/private result reports DNS `resolved` and HTTPS `not_checked` with `mixed_public_private_addresses`, without connecting to either address.
46. A result older than the configured freshness interval reports `stale`; a domain with no result reports `unobserved`; neither state changes authorization.
47. A fresh inconclusive attempt is reported as unknown rather than presenting an older success as current.

### Certificates

48. `operator_managed` performs no internal certificate or provider-vhost create, renew, replace, import, or delete action for any authorization basis.
49. A provider orphan-cleanup task queued before an `approximated` → `operator_managed` activation rechecks the effective strategy under the deletion fence, records skipped `externally_managed`, and does not delete the provider virtual host after activation.
50. When cleanup initially observes `approximated` and `operator_managed` activation races before the fenced final check, activation wins the strategy-revision fence, cleanup records skipped `externally_managed`, and no provider `DELETE` is issued. If cleanup acquires the fence first, activation cannot become effective until deletion reaches a terminal result.
51. An `approximated` → `operator_managed` cutover inventories each residual provider certificate and virtual host and records an operator disposition; any later retention or deletion occurs directly in the provider control plane, not through application cleanup.
52. Internal ACME denies `operator_policy` even when the domain is registered, authorized for normal use, resolving, and serving valid HTTPS.
53. Internal ACME permits only a current registration under `caddy_on_demand` with `txt_proof` or `explicit_override`.
54. `approximated` provider certificate actions require `txt_proof` or `explicit_override`; certificate success does not alter authorization evidence.
55. Failed or unknown HTTPS health does not trigger internal certificate management under `operator_managed`.

## Implementation status

All behavior in this document remains proposed until runtime implementation, coordinated schema and consumer updates, regression coverage, and explicit design acceptance are complete. The existing code still uses legacy strategy and boolean semantics in several protected paths; changing `validation_strategy` alone is not a supported cutover.
