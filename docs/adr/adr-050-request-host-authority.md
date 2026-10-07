---
id: "050"
status: proposed
title: "ADR-050: Request-Host Authority at the Rack Boundary"
---

## Status

Proposed. Implemented behind the opt-in `site.network.public_host_rewrite`
(`PUBLIC_HOST_REWRITE`) setting, which remains off by default. This proposal
does not approve default-on rollout or the unresolved behavior under
[Open decisions and rollout](#open-decisions-and-rollout).

## Date

2026-10-05

## Context

A Host-rewriting proxy sends the origin target in `Host` and the browser's
public authority in `X-Forwarded-Host`. Host detection and domain
classification resolve the public hostname, but Rack consumers can still see
the origin target. Tenant lookup, authentication links, SSO callbacks, and
origin checks can consequently disagree within one request.

Correcting each application consumer leaves mounted gems and future callers
with the wrong default. Leaving forwarded headers available to Rack is not an
alternative trust boundary: Rack's forwarded-authority resolution does not
apply `Rack::DetectHost`'s proxy-trust decision. The application needs one
resolution path and an explicit distinction between public authority,
configured canonical authority, and the authority received by the server.

A host accepted for serving is not necessarily authorized as a credential-link
destination. A transport rewrite must not silently redefine account scope or
admin reachability.

## Decision

### Resolve once; project the result into Rack

Use `Rack::DetectHost` and `DomainStrategy` as the resolution path. Detection
selects a single-valued `X-Forwarded-Host` from trusted infrastructure, then
`Host`; vendor headers and RFC 7239 `Forwarded` are not alternative host
sources. Proxy trust and parsing details belong to the
[proxy authority contract](../operations/proxy-authority-header.md).

After classification, `PublicHostRewrite` projects the accepted public host
into `HTTP_HOST` and `SERVER_NAME`. It runs only when:

- the setting is enabled;
- classification is `:canonical`, `:subdomain`, or `:custom`;
- the detected host is valid and matches `onetime.display_domain`;
- neither forwarded-authority carrier remains in the environment; and
- Rack does not already read that hostname from `Host`.

Invalid, absent, or mismatched resolution does not trigger a rewrite. A
canonical display fallback is not evidence that the received host was
accepted. Domain-context overrides do not supply a second classification path.
Raw Rack authority is not an authorization credential, including on requests
that were not rewritten.

### Keep each authority's purpose explicit

| Purpose | Authority |
| --- | --- |
| Public hostname and tenant context | DetectHost result, then `onetime.display_domain` together with `onetime.domain_strategy` and the request-scoped custom-domain lookup |
| Downstream generic Rack host reads | The projected `HTTP_HOST` / `SERVER_NAME` on eligible requests; otherwise the received authority |
| Deployment-wide canonical URLs | Configured canonical authorities, including `site.host`; never an inferred origin target |
| Received-authority checks and diagnostics | `PublicHostRewrite.original_http_host(env)`, which reads `onetime.original_http_host` when present and `HTTP_HOST` otherwise |
| Credential and SSO destinations | The dedicated `Auth::PublicHost` resolvers, retaining their authorization checks and configured canonical fallbacks |

The original `Host` is preserved only when a rewrite occurs. Diagnostics retain
stripped header names and the validated detection result, not copies of raw
forwarded values in new environment keys.

Positive classification permits projection, not ownership authorization. A
registered but unverified domain can classify `:custom` and be rewritten while
auth-link resolution declines its tenant destination. Keep per-consumer auth
URL helpers as authorization boundaries. The authorization basis proposed in
[ADR-049](adr-049-operator-managed-domain-authorization.md) remains separate.
Account scope still follows owning domain/org policy, not the request host,
under accepted [ADR-035](adr-035-tenant-identity-auth-policy-scope.md).

### Sanitize independently of rewriting

`StripForwardedHost` deletes `X-Forwarded-Host` and the entire `Forwarded`
header on every request, regardless of classification or the rewrite setting.
It runs after legitimate detection and admin provenance checks but before
session and application consumers. Scheme information legitimately resolved
from a trusted proxy is carried forward before deletion; untrusted forwarded
scheme and port inputs are removed.

Whole-header deletion avoids a second RFC 7239 parser whose disagreement with
Rack could leave an authority behind. Prefer request-local sanitization to
`Rack::Request.forwarded_priority = []`: the latter is process-global and
also disables forwarded scheme resolution.

### Preserve ordering and public-port semantics

The required request order is:

`DetectHost → AdminNetworkIsolation → StripForwardedHost → session/identity
→ DomainStrategy → PublicHostRewrite → downstream security and applications`.

The admin host gate judges the detected host and corroborates it against the
received headers before mutation. It must not move below the rewrite or lose
its provenance inputs through earlier sanitization. `PublicHostRewrite`
stays directly after `DomainStrategy`. Upstream middleware shares the mutable
environment and may see rewritten values on the response path; upstream
placement alone is not an exemption from the consumer audit.

For an actual rewrite, the public port comes from the validated, selected
`X-Forwarded-Host` authority, or a valid trusted `X-Forwarded-Port` when that
host is bare. Do not carry the origin hop's received port into the public
host. Put a non-default public port in `HTTP_HOST`, then remove
`X-Forwarded-Port` so Rack's authority and port reads agree. Leave
`SERVER_PORT` as the server's listening port. A matching received hostname
is left intact, including its port; this is not universal port normalization.

### Organization scope on a host that detection rejects

Decided 2026-10-07 (#4678). A request whose `Host` is rejected by
`Rack::DetectHost` (an IP literal, `localhost` and the other names on its
invalid list, a malformed name, or no `Host` at all) carries no domain scope.
`OrganizationLoader#request_scope_domains` answers an empty scope for it, as
for a canonical host, and every membership is permitted. This is a different
case from a display host that was read and has no record, where every
organization is withheld (#4225, #4672).

The rule rests on what a custom domain can be, not on the detection list.
None of these hosts can be a custom-domain record, since `CustomDomain.valid?`
requires a public-suffix-valid name, so none is ever read and no lookup is
published for one. A host that cannot name a custom domain has no scope to
apply. If detection were later widened to accept such a host, it would be
read, found absent, and withheld; the dependency fails closed.

Withholding would gain nothing. On a direct connection the client chooses
`Host`, and a canonical `Host` classifies before any read and yields the same
empty scope. Behind a trusted proxy a rejected forwarded host falls through
to the proxy's `Host` and classifies `:canonical`. It would cost an on-box
API client calling the origin by IP or `localhost` its organization context
on a domains-enabled install, and `Logic::OrganizationContext#auth_org`
neither lazy-creates nor falls back after a scope refusal.

Follow-through, referencing #4678: one sentence in the proxy authority
contract stating that such requests are served as the canonical host, so
excluding direct-origin access is the operator's control, and a loader log
line for the case beside its unregistered-host refusal. The behaviour is
pinned by the examples for `:invalid` with nothing published in
`spec/unit/organization_loader_cache_scope_spec.rb` and
`spec/unit/domain_strategy_classification_contract_spec.rb`.

## Consequences

- Mounted Rack code receives the public hostname without OTS-specific adapters;
  consumers needing the received `Host` must use the original accessor.
- The edge must overwrite or remove relevant forwarded headers. A trusted proxy
  passing through client values defeats their intended provenance.
- Rewriting changes origin-check and organization-selection behavior. Matching
  a Host-preserving topology does not establish that access decisions are safe.
- With rewriting off, the two-host discrepancy remains. Enabling it does not
  repair invalid-host fallbacks or establish coverage of unaudited gem internals.

## Open decisions and rollout

Required full-stack proxy coverage and real-proxy burn-in precede a separate
default-on decision. The dated [consumer audit and coverage checklist](../security/audits/request-host-authority-audit-2026-10-05.md)
records inspected consumers, gem-audit limits, and outstanding test coverage.
Two policy gaps require explicit disposition:

- **WebAuthn and reauth fallback:** an `:invalid` request, or a custom context
  without its published record, makes the WebAuthn resolver decline. RP ID,
  ceremony origin, and reauth origin can then come from raw Rack authority.
  Invalid requests are not rewritten. The refusal/fallback policy needs a
  decision and a live ceremony regression.
- **Organization scope:** when received `Host` names custom domain A and
  detected/display context names custom domain B, the loader checks A+B with
  rewriting off but can check only B after rewriting. A membership permitted
  on B but not A can therefore pass that scope check only with rewriting on.
  Preserving A for membership checks or deliberately excluding transport A
  requires an explicit policy decision and regression coverage. The host that
  detection rejects is not part of this gap; it is decided under
  [Organization scope on a host that detection rejects](#organization-scope-on-a-host-that-detection-rejects).

Other unresolved concerns remain: the display-origin allowance on invalid
classification, tenant lookup failure responses, and the Host-preserving
bare-Host/forwarded-port mismatch. In the latter case, Rack's `port` can include
a trusted forwarded port that `base_url` omits; only actual rewrites normalize
the pair.

## Related

- [Consumer audit and rollout coverage](../security/audits/request-host-authority-audit-2026-10-05.md)
- [Proxy authority contract and upgrade guidance](../operations/proxy-authority-header.md)
- [Trusted proxy configuration](../deployment/trusted-proxies.md)
- [Admin network isolation](../operations/admin-network-isolation.md)
- [Organization authorization discriminators](../architecture/org-authorization-discriminators.md)
- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
- [ADR-049: Operator-Managed Domain Authorization](adr-049-operator-managed-domain-authorization.md) (Proposed)
