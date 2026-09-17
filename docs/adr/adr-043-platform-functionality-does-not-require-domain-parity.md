---
id: "043"
status: proposed
title: "ADR-043: Platform Functionality Does Not Require Domain-Level Parity"
---

## Status

Proposed

## Date

2026-09-17

## Context

OneTime Secret exposes capabilities at two different scopes: the platform or
installation level, and the domain level. These scopes serve different use
cases. A platform capability configures the installation as a whole, while a
domain capability can vary for each domain hosted by that installation.

It is tempting to treat any difference between the two scopes as a feature
gap. Doing so would make the more flexible scope an implicit specification for
the other. It would also expand platform configuration, user experience,
documentation, and testing even when there is no substantial platform-level
use case for that flexibility.

The appropriate configuration surface depends on the purpose and expected use
of each scope. Some capabilities should exist at both scopes, but they do not
necessarily need the same options, multiplicity, or degree of flexibility.

## Decision

Platform- or installation-level functionality is not required to match
domain-level functionality feature for feature. The two scopes may
intentionally provide different capabilities and configuration surfaces.

A domain-level capability does not, by itself, establish a requirement for a
platform-level equivalent. A proposal to add or expand platform functionality
must demonstrate a substantial installation-wide use case, explain why the
domain-level capability does not address it, and justify the additional
configuration and operating surface on its own merits.

This decision does not prohibit parity when both scopes have a clear need for
the same behavior. It establishes that parity is a product choice, not a
default requirement. It also does not relax the security, identity isolation,
privacy, or availability requirements that apply to either scope.

## Trade-offs

- **We lose:** Operators cannot assume that every domain-level capability is
  also available at the platform level. Some installation-wide use cases may
  require a separate proposal or an alternative configuration model.
- **We gain:** Each scope can remain aligned with its purpose without
  accumulating configuration and interface complexity solely for symmetry.
- **Risk:** A platform-level use case may be underestimated because the
  domain-level path works for common deployments. Such a case should be
  evaluated through an explicit follow-up decision with evidence of the need
  and its operating costs.

## Consequences

Differences between platform and domain functionality are not automatically
classified as omissions. Product and architecture proposals evaluate the need
at the affected scope rather than citing parity alone.

For SSO, per-domain OIDC configuration does not require the platform sign-in
surface to support the same number of independently configured OIDC
connections. Whether to add multiple platform OIDC instances is evaluated as
an installation-level product decision, not inferred from tenant SSO.

## Related

- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
