---
id: "044"
status: proposed
title: "ADR-044: Criteria for Adding Bespoke OmniAuth Strategies"
---

## Status

Proposed

## Date

2026-09-17

## Context

The generic OpenID Connect (OIDC) strategy already connects an install to an
IdP through issuer discovery. It carries a validated issuer into the identity
key, so it works on both the platform and tenant SSO surfaces. Adding a
provider-specific OmniAuth strategy is therefore not neutral: each strategy
adds a gem, configuration and documentation surface, provider-specific
maintenance, and another identity shape to understand and test.

In particular, a plain OAuth2 strategy has no issuer for the identity key. The
current issuerless-provider policy resolves its issuer to the empty-string
sentinel and refuses it on the tenant surface. It can serve platform SSO only;
adding another such provider adds another `(provider, '', uid)` collision
surface there without creating tenant eligibility.

Provider brand recognition alone is not a sufficient reason to duplicate an
OIDC integration. Google, Auth0, GitLab, Okta, and, at the protocol level,
Entra can use generic OIDC. Zoom and DigitalOcean are examples of the low-value
case: an issuerless, platform-only strategy would add provider-specific work
and the issuerless collision surface without extending tenant SSO.

Platform generic OIDC currently provides one install-level connection, while
tenant SSO can resolve a different OIDC configuration for each domain. Under
ADR-043, that difference does not create a requirement for platform parity.
Deciding not to implement multiple platform OIDC instances is therefore
consistent with the platform and domain scope boundary; it is not a reason to
add provider-specific adapters instead.

Some providers do have requirements that generic OIDC cannot faithfully cover.
GitHub has no OIDC login flow. Apple is OIDC-shaped but requires a per-request
ES256 client-secret JWT and `form_post` response handling. These are protocol
needs rather than branding preferences.

## Decision

The default is to integrate an IdP through generic OIDC and to document that
configuration. A proposal to add a bespoke OmniAuth strategy must first answer
whether the IdP can support login through OIDC at all. If it can, a provider
strategy is redundant unless it qualifies for the market-and-operator-experience
exception below.

A bespoke strategy is admissible only when at least one of these conditions is
true:

1. **OIDC is unavailable.** The IdP has no usable OIDC login flow, as with
   GitHub.
2. **OIDC needs provider-specific protocol behavior that the generic strategy
   cannot safely supply.** The proposal identifies the behavior, why it must
   occur in the adapter, and how it will be tested. Apple's per-request ES256
   client-secret minting and `form_post` callback are the reference example.
3. **A deliberate market-and-operator-experience exception applies.** The IdP
   has broad enough adoption and concrete provider quirks that a built-in path
   materially improves the clarity and reliability of operator setup. The
   proposal must explain the benefit beyond a friendlier button and retain
   documented generic-OIDC setup. Entra's `tid+oid` uid composition is an
   example of useful provider-specific behavior; Entra and Auth0 are examples
   of providers that may meet this exception despite OIDC being viable.
4. **The protocol is a distinct product feature.** A non-browser or
   non-OIDC authentication system may be evaluated on its own product merits,
   rather than being forced into the OmniAuth-adapter decision. LDAP directory
   bind is such a feature.

Every proposal must state whether the strategy produces a validated issuer. An
issuerless strategy is an exceptional, platform-only integration: the proposal
must explain why its value outweighs another `(provider, '', uid)` collision
surface and the absence of tenant eligibility. Convenience alone does not meet
that threshold.

Do not add a config-driven generic OAuth2 strategy. Configurable endpoints and
claims mapping make it possible to reach many providers, but this route is
issuerless by construction and moves identity correctness into an arbitrary
claims mapping. It has the issuerless limitations above without the predictable
contract of an individually reviewed adapter.

CAS is an illustrative market exception: it is niche, but can be valuable for
education customers. It must still be evaluated as a separate strategy
proposal, including its identity and tenant-surface behavior.

This ADR sets admission criteria for future strategies. It does not remove or
change the behavior of strategies already registered; doing so requires a
separate decision and migration plan.

## Trade-offs

- **We lose:** The apparent simplicity of answering every provider request by
  adding its gem and a new environment-variable set. Some operators will need
  to use and understand generic OIDC even when a branded strategy exists in
  the wider ecosystem.
- **We gain:** One issuer-aware integration path for the broad OIDC ecosystem,
  fewer dependency and configuration surfaces, and a high bar for creating
  platform-only identity routes.
- **Risk:** The market-and-operator-experience exception requires judgment. If
  it becomes a label rather than evidence, it can recreate the strategy sprawl
  this ADR prevents. Proposals must name the specific operator-experience need
  or provider behavior and preserve generic-OIDC documentation as the
  baseline.

## Consequences

New requests for Google, Auth0, GitLab, Okta, Entra, or similar OIDC-capable
IdPs begin with generic OIDC configuration, not a search for a matching
OmniAuth gem. A bespoke integration for a popular OIDC-capable provider is a
documented exception, not an implication of popularity.

The singleton platform OIDC configuration remains an intentional scope choice
under ADR-043. Requests for several platform-level OIDC connections must
justify that platform capability directly; they do not change the admission
criteria for bespoke adapters.

New issuerless strategies require an explicit platform-only decision. They
must not be presented as tenant SSO options or as an expandable generic OAuth2
catalog.

Implementation work remains governed by the provider-registration checklist,
including issuer classification, strategy configuration, tests, and operator
documentation. This ADR decides whether that work should begin; it does not
replace the checklist once a strategy is admitted.

## Related

- [ADR-043: Platform Functionality Does Not Require Domain-Level Parity](adr-043-platform-functionality-does-not-require-domain-parity.md)
- [Adding an SSO Provider](../authentication/adding-sso-providers.md) —
  provider-registration checklist and issuer classification
- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
- `lib/onetime/sso_provider/registry.rb` — provider definitions and
  issuer-capability contract
