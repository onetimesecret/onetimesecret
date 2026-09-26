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
ES256 client-secret JWT and `form_post` response handling. An IdP that speaks
only SAML 2.0 has no OIDC login flow at all. These are protocol needs rather
than branding preferences.

## Decision

The default is to integrate an IdP through generic OIDC and to document that
configuration. A proposal to add a bespoke OmniAuth strategy must first answer
whether the IdP can support login through OIDC at all. If it can, a provider
strategy is redundant unless it qualifies for the market-and-operator-experience
exception below.

A bespoke strategy is admissible only when at least one of these conditions is
true:

1. **OIDC is unavailable.** The IdP has no usable OIDC login flow, as with
   GitHub, or as with an IdP that offers only SAML 2.0. SAML (#4450) is the
   reference case for this criterion; see Consequences.
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

SAML 2.0 (#4450) is the first strategy admitted under criterion 1 and is the
reference for what admission costs. The IdPs it reaches have no OIDC flow, so
generic OIDC is not an alternative. It is issuer-capable only through this
application's subclass, `OmniAuth::Strategies::RequestBoundSAML`, together
with a required `idp_entity_id`: the stock `omniauth-saml` strategy produces
no validated issuer (it would resolve to the `''` sentinel), ruby-saml skips
issuer validation when no EntityID is configured, and the strategy accepts
unsolicited responses, so as shipped it would not have qualified. The
validated IdP EntityID reaches the identity key through its own
`resolve_issuer` branch, decided by strategy class, that raises rather than
falling back to any other issuer source. Admission carried preconditions a
future proposal should expect to meet: an exactly pinned verifier gem with its
advisory history recorded in the `Gemfile` and a `bundler-audit` job on every
pull request; a subclass that owns every protocol-specific gate (request
binding read from the signed assertion, issuer byte-equality, stable uid,
single-use assertions with a bounded lifetime, a scrubbed auth hash); tenant eligibility through `SsoConfig::PROVIDER_ROUTE_MAP` with
the same hardened options as the platform definition; and operator
documentation of what is deliberately unsupported (IdP-initiated sign-in,
single logout). One departure from the proposal: missing or invalid platform
configuration skips the provider rather than failing boot, because provider
registration is designed never to take the other sign-in methods down with
it.

Implementation work remains governed by the provider-registration checklist,
including issuer classification, strategy configuration, tests, and operator
documentation. This ADR decides whether that work should begin; it does not
replace the checklist once a strategy is admitted.

## Applied examples

The following provider requests illustrate the default outcome under this
ADR: generic OIDC configuration rather than a bespoke strategy.

**Clever.** Clever's Instant Login is OIDC-shaped. No provider-specific
protocol behavior is identified that generic OIDC cannot faithfully cover,
and the K-12 market case does not name a concrete quirk that meets the
market-experience threshold. Rostering is a separate product surface,
outside the SSO-login decision.

**AWS Cognito.** Cognito is a conforming OIDC provider with issuer
discovery. No protocol quirk requires an adapter. Broad adoption alone
does not meet the market-experience bar, which this ADR sets against
strategy sprawl.

**A second generic OIDC gem (e.g. `omniauth_oidc`).** A second generic
OIDC strategy is config-surface duplication without provider specificity.
It carries the same hazards as the config-driven generic OAuth2 route
this ADR rejects: arbitrary claims mapping and no reviewable provider
contract. Generic OIDC is already the default; the way to improve it is
to harden the single strategy, not to add another.

**Keycloak.** Keycloak realms expose a validated OIDC issuer with
discovery, and generic OIDC has been the standard integration route for
years. Operator setup — realm URL in, discovery does the rest — is
straightforward. No provider-specific protocol behavior is named that
generic OIDC cannot supply, and self-hosted-IdP adoption alone does not
clear the market-experience threshold.

## Related

- [ADR-043: On Parity for Platform Level and Domain Level Functionality](adr-043-on-parity-for-platform-level-and-domain-level-functionality.md)
- [Adding an SSO Provider](../authentication/adding-sso-providers.md) —
  provider-registration checklist and issuer classification
- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
- `lib/onetime/sso_provider/registry.rb` — provider definitions and
  issuer-capability contract
- `lib/onetime/sso_provider/request_bound_saml.rb` — the SAML reference case
  for criterion 1 (#4450)
