---
id: "049"
status: accepted
title: "ADR-049: Operator-Managed Domain Authorization"
---

## Status

Accepted

## Date

2026-10-05

## Context

The existing `passthrough` strategy mixes three different questions: whether a
customer may use a registered domain, whether DNS and HTTPS currently work,
and who manages certificates. ADR-016 requires the same TXT-based ownership
axis for every strategy, while ADR-017 requires `passthrough` domains to prove
ownership through TXT before link creation. Those requirements do not fit a
deployment where the operator controls domain registration and delegates
certificate management to external infrastructure.

This mode is not permission to use an arbitrary hostname. Authorization comes
from the operator trusting the current registration of a domain to a customer.
DNS and HTTPS observations can describe whether that registration is usable,
but they cannot create or revoke the operator's authorization and cannot prove
ownership. The summary table in the
[operator-managed domains specification](../specs/domain-validation/operator-managed-domains.md)
contrasts the two concerns row by row.

The deployment context for this proposal reports no installed `passthrough`
user base to migrate. The strategy has not worked as a usable mode in project or
self-hosted deployments, so this proposal does not include a compatibility
rollout for active users. The existing names remain useful as accepted
configuration aliases.

## Decision

The canonical strategy name is `operator_managed`. `passthrough` and `external`
are input aliases and normalize immediately to `operator_managed`; persisted
and emitted strategy values use the canonical name.

These names and aliases apply to the custom-domain validation strategy only.
The `validation_strategy` field on `SignupConfig` selects an email-address
validation strategy and also accepts `passthrough`; it is unrelated to this
decision and is not renamed or normalized by it.

A trusted, current registration under operator control authorizes that domain
for its assigned customer without TXT proof. The registration must still exist,
remain assigned through the trusted operator path, and match the requested
hostname. An unregistered hostname is unauthorized. Operator policy is an
authorization basis, not evidence that the customer owns the hostname.

Domain state is separated into three concerns:

1. **Authorization** records the basis on which the current assignment may be
   used: eligible TXT proof, an explicit operator override, or
   `operator_managed` policy.
2. **Observed health** records DNS resolution and HTTPS reachability as current,
   stale, unknown, healthy, unhealthy, or not checked observations. Health does
   not grant authorization, and a health failure does not revoke authorization
   granted by `operator_managed` policy.
3. **Certificate management** records who is responsible for certificates. It
   is external under `operator_managed`. Operator-policy authorization must not
   authorize OTS's internal ACME path or be consumed as ACME ownership proof.

The strategy in effect for a domain is enforced at request time. Today that is
the install-level `features.domains.validation_strategy`. ADR-015 is accepted
but not implemented; if its per-domain override lands, it takes precedence as
that ADR specifies and the same request-time enforcement applies to it. A
switch from `operator_managed` to either TXT-enforced strategy immediately
stops operator-policy authorization from qualifying, including before any
scheduled refresh, worker pass, or cache update. The first request under the
new strategy is denied unless it can resolve eligible TXT or explicit-override
evidence for the current assignment.

Persisted `verified` and `resolving` flags are projections for compatibility
and display. Neither flag is ownership proof or an authorization credential,
and neither may satisfy the request-time cutover check by itself.

Eligible TXT and override evidence carries provenance that binds it to the
current assignment lineage. At minimum, authorization evaluation must be able
to distinguish its basis, the assignment lineage for which it was established,
and its source. Evidence from a prior or ended assignment lineage is ineligible,
even when a legacy boolean remains true. TXT evidence must originate from a
successful TXT check for that lineage; override evidence must identify an
explicit override applicable to that lineage. Workers and caches may carry
this evidence but may not infer it from `verified`, `resolving`, or observed
health.

No `passthrough` data migration, deprecation window, feature-flag transition,
or staged old/new client rollout is required. All consumers adopt the canonical
name and aliases as one change; retaining the aliases is vocabulary
compatibility, not evidence of an installed user base.

### Partial supersession

This ADR supersedes only these clauses of ADR-016:

- the Decision's statement that the ownership axis is universal and computed
  the same way regardless of strategy, insofar as it requires TXT ownership
  proof for `passthrough`; and
- the frontend requirement that an ownership badge have the same semantics for
  `passthrough` as for TXT-enforced strategies; and
- the certificate/serving-axis statement that `passthrough` has "no axis to
  render," insofar as it omits independently reported observed DNS and HTTPS
  health. Certificate management remains external.

ADR-016's separation of ownership from serving and certificate status, its
non-conflation rules, and its decisions for TXT-enforced strategies remain
intact.

This ADR supersedes only these clauses of ADR-017:

- the Decision's `passthrough` requirement for one-time TXT proof before use as
  a `share_domain`;
- the Decision's `approximated` clause insofar as it makes the link-creation
  gate optional through `require_verified`; strategy-aware authorization is
  mandatory for every protected consumer regardless of that setting;
- the rollout paragraph requiring a feature flag, deprecation window, and
  delayed default flip for existing `passthrough` deployments; and
- the `passthrough`-specific trade-off and risk statements that assume an
  installed user base must complete TXT proof.

ADR-017's requirement that `caddy_on_demand` be authorization-gated, its
separation of the gate from periodic re-validation, and its rule that
certificate issuance does not satisfy ownership authorization remain intact.

## Trade-offs

- **We lose:** A single TXT-shaped meaning for `verified` across all strategies.
  Authorization consumers must inspect the effective strategy and evidence
  provenance instead of trusting one boolean.
- **We gain:** A usable mode for operator-controlled registrations that reports
  operational failures without turning them into false ownership decisions or
  unintended revocation.
- **Risk:** A compromised or overly broad registration path can authorize the
  wrong customer without an independent TXT challenge. The mode is therefore
  safe only when registration is operator-controlled, current assignment
  lineage is enforced, and unregistered hosts fail closed.

## Related

- [ADR-015: Per-Domain Validation Strategy Override](adr-015-domain-validation-per-domain-strategy.md)
- [ADR-016: Decouple Ownership Verification from Certificate/Serving Status](adr-016-domain-validation-state-model.md)
- [ADR-017: Gate Domain-Dependent Functionality on Ownership Verification](adr-017-domain-validation-link-creation-gate.md)
