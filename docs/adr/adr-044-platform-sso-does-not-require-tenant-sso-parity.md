---
id: "044"
status: proposed
title: "ADR-044: Platform SSO Does Not Require Tenant SSO Configurability Parity"
---

## Status

Proposed

## Date

2026-09-17

## Context

Platform generic OIDC is a single install-level connection. Its definition
reads one `OIDC_ISSUER` and `OIDC_CLIENT_ID` pair and registers one route name.
An operator therefore cannot configure both, for example, Okta and Keycloak as
separate generic-OIDC choices on the platform sign-in surface.

Tenant SSO is different by design. It resolves an SSO configuration from the
request's custom domain and injects that domain's credentials at runtime. One
installation can therefore serve different IdP connections for different
domains. The difference is a platform configurability gap, not an OIDC,
strategy-gem, or issuer-scoping gap.

The generic OIDC definition could be parameterized into several named platform
instances. That would extend the existing strategy, protocol, and issuer
semantics without adding a provider gem. It is potentially high-leverage, but
it would make the install-level configuration, routes, registration, and
operator guidance more complex.

Install-level SSO and tenant SSO have different purposes. A self-hosted
installation needing several unrelated IdPs on its platform surface is not a
common enough case to require the same flexibility as per-domain SSO. An
organization that needs its own IdP connection can use its domain's SSO
configuration instead.

## Decision

Platform SSO is not required to have feature or configurability parity with
tenant SSO. In particular, generic platform OIDC remains a single install-level
connection; do not parameterize it into multiple named instances solely to
mirror tenant SSO's per-domain flexibility.

This is an intentional product boundary, not an accidental omission. Tenant
SSO is the appropriate path for distinct domain-specific IdP connections. The
platform connection continues to cover the normal self-hosted case of one
install-level IdP.

This decision is limited to SSO configurability, including the number of
install-level generic OIDC connections. It does not relax security, identity
isolation, or availability requirements on either surface.

A later proposal for multiple platform OIDC instances must establish a
substantial install-level need that tenant SSO cannot address and explain why
the additional configuration and operating surface is justified. It should be
evaluated as a new decision, not inferred from tenant capabilities or from the
absence of a bespoke provider adapter.

## Trade-offs

- **We lose:** A platform operator cannot offer several separately configured
  generic-OIDC choices from one installation. Some multi-IdP requirements must
  use tenant SSO or a single upstream IdP that federates the desired providers.
- **We gain:** A small, understandable platform configuration surface and a
  clear reason not to multiply routes and OIDC definitions for uncommon
  install-level cases.
- **Risk:** A deployment with a genuine multi-IdP platform requirement may
  outgrow this boundary. The required response is an explicit follow-up
  decision with that use case and its operating costs, rather than silently
  expanding the singleton definition.

## Consequences

The lack of several platform OIDC instances is documented as deliberate. It is
not evidence that a provider needs a bespoke OmniAuth strategy: adding an
Okta-, Keycloak-, or similar provider-specific adapter would not solve the
general multiple-platform-IdP problem.

Provider-admission work remains governed by ADR-043. A provider's OIDC
availability decides whether its own adapter is necessary; this ADR separately
decides that platform generic OIDC does not need the same multiplicity as
tenant SSO.

## Related

- [ADR-043: Criteria for Adding Bespoke OmniAuth Strategies](adr-043-omniauth-adapter-admission-criteria.md)
- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
- [Adding an SSO Provider](../authentication/adding-sso-providers.md)
- `lib/onetime/sso_provider/oidc.rb` — install-level generic OIDC definition
- `apps/web/auth/config/hooks/omniauth_tenant.rb` — per-domain credential
  resolution and injection
