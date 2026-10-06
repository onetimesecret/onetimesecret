---
id: "050"
status: proposed
title: "ADR-050: Request-Host Authority at the Rack Boundary"
---

## Status

Proposed

The boundary described here is implemented behind an opt-in setting. This
proposal does not approve default-on rollout or ratify the unresolved
security-sensitive behavior listed in Implementation Notes.

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

Those values serve different purposes. A host accepted for serving is not
necessarily authorized as a credential-link destination. A transport rewrite
also must not silently redefine account scope or admin reachability.

## Decision

### Resolve once; project the result into Rack

Use `Rack::DetectHost` and `DomainStrategy` as the resolution path. Detection
selects a single-valued `X-Forwarded-Host` from trusted infrastructure, then
`Host`; vendor headers and RFC 7239 `Forwarded` are not alternative host
sources. Proxy trust and parsing details belong to the
[proxy authority contract](../operations/proxy-authority-header.md).

After classification, `PublicHostRewrite` projects the accepted public host
into `HTTP_HOST` and `SERVER_NAME`, so downstream Rack readers have the same
hostname as the resolved context. It runs only when:

- the setting is enabled;
- classification is `:canonical`, `:subdomain`, or `:custom`;
- the detected host is valid and matches `onetime.display_domain`;
- neither forwarded-authority carrier remains in the environment; and
- Rack does not already read that hostname from `Host`.

Invalid, absent, or mismatched resolution does not trigger a rewrite. A
canonical display fallback is not evidence that the received host was
accepted. Domain-context overrides do not supply a second classification
path; no override-provenance key is needed now that those paths are removed.

This makes the public host the ergonomic default without requiring every gem
to understand OTS environment keys. It does not make raw Rack authority an
authorization credential, particularly on requests that were not rewritten.

### Keep each authority's purpose explicit

| Purpose | Authority |
| --- | --- |
| Public hostname and tenant context | DetectHost result, then `onetime.display_domain` together with `onetime.domain_strategy` and the request-scoped custom-domain lookup |
| Downstream generic Rack host reads | The projected `HTTP_HOST` / `SERVER_NAME` on eligible requests; otherwise the received authority |
| Deployment-wide canonical URLs | Configured canonical authorities, including `site.host`; never an inferred origin target |
| Received-authority checks and diagnostics | `PublicHostRewrite.original_http_host(env)`, which reads `onetime.original_http_host` when present and `HTTP_HOST` otherwise |
| Credential and SSO destinations | The dedicated `Auth::PublicHost` resolvers, retaining their authorization checks and configured canonical fallbacks |

The original `Host` is preserved only when a rewrite occurs. Raw forwarded
header values are not copied into new environment keys; diagnostics retain
stripped header names and the validated detection result, not another
readable authority carrier.

Positive classification permits projection, not ownership authorization. In
particular, a registered but unverified domain can classify `:custom` and be
rewritten while auth-link resolution declines its tenant destination. Keep
per-consumer auth URL helpers as authorization boundaries, not redundant
workarounds to remove after rollout. The authorization basis proposed in
[ADR-049](adr-049-operator-managed-domain-authorization.md) remains a separate
decision.

Account scope also remains separate. Accepted
[ADR-035](adr-035-tenant-identity-auth-policy-scope.md) states: "An account's
authenticatable surface is governed by its owning domain/org policy, not by
the request host it happens to arrive on". Projecting a transport authority
does not supersede that rule.

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
also disables forwarded scheme resolution. Carrier removal remains required
even while rewriting is off.

### Preserve ordering and public-port semantics

The load-bearing request order is:

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

## Trade-offs

- **We lose:** The assumption that downstream `HTTP_HOST` always means the
  received header. Consumers needing that evidence must opt into the original
  accessor, and response-path readers require review as well as request-path
  readers.
- **We gain:** Mounted Rack code receives the public hostname without
  OTS-specific adapters, while explicit canonical and credential authorities
  retain their separate meanings.
- **Risk:** A trusted proxy that passes through client values defeats the
  intended provenance of forwarded authority. The edge must overwrite or
  remove the relevant headers. Rewriting also changes origin-check and
  organization-selection behavior; matching a Host-preserving topology is not
  proof that every resulting access decision is acceptable.
- **Conditional cost:** With rewriting off, the two-host discrepancy remains.
  Enabling it does not resolve invalid-host fallbacks or audit unaudited gem
  internals. The setting cannot substitute for those reviews.

## Related

- [Proxy authority contract and upgrade guidance](../operations/proxy-authority-header.md)
- [Trusted proxy configuration](../deployment/trusted-proxies.md)
- [Admin network isolation](../operations/admin-network-isolation.md)
- [Organization authorization discriminators](../architecture/org-authorization-discriminators.md)
- [ADR-035: Tenant Identity and Authentication-Policy Scope](adr-035-tenant-identity-auth-policy-scope.md)
- [ADR-049: Operator-Managed Domain Authorization](adr-049-operator-managed-domain-authorization.md) (Proposed)

## Implementation Notes

### Consumer dispositions at the current boundary (2026-10-05)

This is a source-inspected inventory of production authority readers in
`lib/` and `apps/`, plus the associated URL and policy consumers. It replaces
reliance on an assumption that all host readers want the same value. Gem
inspection is limited to `rack-session` and `rack-protection`; no complete
audit of Rodauth, OmniAuth, Otto, Sentry, or other gem internals is implied.
These dispositions describe current implementation, not blanket approval of
its security consequences.

Paths below are relative to the repository root.

| Consumer | Disposition |
| --- | --- |
| `lib/middleware/detect_host.rb`; `lib/onetime/middleware/strip_forwarded_host.rb`; `public_host_rewrite.rb` in the same directory | Detection reads received carriers under proxy trust; sanitization removes them; rewriting preserves the received `Host` and projects only the matching positive resolution. |
| `lib/onetime/middleware/admin_network_isolation.rb`; `lib/onetime/application/network_requirements.rb` | Security-sensitive: keep the upstream detected-host allowlist and received-header corroboration. Downstream Colonel routes consume that verdict, not rewritten `Host`. |
| `apps/api/colonel/auth_strategies.rb` proxy diagnostic | Received: report the preserved original after rewriting. This is not a second host allowlist. |
| `lib/onetime/application/organization_loader.rb`; `lib/onetime/operations/sessions/track_metadata.rb` | Public/effective: domain-based selection reads effective `HTTP_HOST`, including during session commit. Membership scope also uses the published tenant record. The two-custom-domain scope reduction below remains unresolved. |
| `lib/onetime/session.rb` and `rack-session` | Session preparation is upstream; commit sees the shared environment. The session cookie's Domain is not automatically derived from rewritten `Host`; organization metadata can change through the loader. |
| `lib/onetime/middleware/cookie_tossing.rb` | Public: clearing cookies use DetectHost, falling back to Rack host only when detection is absent. Duplicate-cookie refusal runs before session/rewrite and short-circuits. |
| `rack-protection` `HttpOrigin`, through global Security and the auth profile | Security-sensitive public origin: compare the request's effective scheme, host, and port. Rewriting refuses an origin-target Origin and can admit the public non-default-port or HTTP origin that the off setting refused. Explicit allowances remain separate. |
| `lib/onetime/middleware/http_origin_options.rb` | Resolved public/canonical policy: retain its resolved-host checks. Its `HTTP_HOST` / `SERVER_NAME` fallback occurs without detection and is not repaired by rewriting. The display-origin allowance on `:invalid` requests remains an independent open concern. |
| `lib/onetime/security/saml_callback_store.rb`; `lib/onetime/middleware/saml_callback_transport.rb` | Security-sensitive received scope: reconstruct staging authority from the original `Host`, together with detected/display context and callback path. Do not re-key staged callbacks when the setting changes. The transport boundary runs upstream. |
| `apps/web/auth/lib/public_host.rb`; `apps/web/auth/config/overrides/public_base_url.rb` | Authorized public, then configured canonical: keep the resolvers. Credential emails additionally require recipient membership/domain scope; absent authorized origin raises rather than falling back to raw Rack authority. |
| `apps/web/auth/config/features/omniauth.rb`; `apps/web/auth/config/hooks/omniauth_tenant.rb` | Public: SSO URL generation keeps the required allowlisted resolver. Tenant lookup uses resolved context; its last-resort `request.host` fallback remains for missing usable resolved values, not as authorization evidence. |
| `apps/web/auth/config/features/webauthn.rb`; `apps/web/auth/operations/reauth_offer.rb` | Security-sensitive public RP/origin inputs with received-authority fallbacks. Those fallback branches remain unresolved; see below. |
| `apps/web/auth/config/email/`; SSO-link mail injection in `apps/web/auth/config/hooks/omniauth.rb`; `lib/onetime/mail/views/` and `templates/` | Auth URLs consume recipient-bound origins. Display-domain labels are not URL authority. Layout and secret-mail URLs use supplied `baseuri` / `share_domain`, with configured canonical fallback. V3 feedback's display-domain label falls back to configured `site.host`; it is escaped text, not destination authority. |
| `apps/web/billing/controllers/plans.rb`, `billing.rb`; `apps/web/billing/operations/create_checkout_link.rb`; core/billing controller URI helpers | Canonical: checkout success/cancel and portal-return URLs intentionally use configuration, not the tenant request. URI host/default operations are not Rack host reads. |
| `lib/onetime/billing_config.rb`; Stripe initializer and bootstrap config serializer | Configured outbound checkout allowlist: do not migrate to received or rewritten Host. Browser validation in `src/utils/redirect.ts` compares the destination with configured checkout, Stripe, and browser same-origin authorities. |
| `lib/onetime/rodauth_admin.rb` | Configured admin URL, not inferred request authority. |
| `lib/onetime/middleware/tenant_csp_extras.rb`; `lib/onetime/tenant_sso_resolution.rb`; core request setup | Public tenant context: keep the resolved tenant/IdP source for CSP extras, including response-path emission. No raw Host authority is needed. |
| Secret creation and receipt/reveal/burn logic under `apps/api/v1/`, `v2/`, and `incoming/`; secret-mail views | Public sharing context or persisted `share_domain`, then canonical fallback. Receipt/secret destinations do not automatically follow the current Rack host. |
| `apps/web/core/views/helpers/initialize_view_vars.rb`; `views/base.rb`; `templates/partials/head.rue` | Public title/branding but canonical social URL/domain and relative-image authority. Rewriting does not turn these into tenant URLs. `head-secret-share.rue` has no identified live inclusion and is not a verified emitter. |
| `lib/onetime/session/surface.rb` | Security-sensitive resolved classification/tenant identity: retain published context, not raw Rack authority. |
| `lib/onetime/initializers/setup_diagnostics.rb` | Scrub the SDK event's URL; this is not a Rack authority resolver. How Sentry constructs that URL is outside the inspected gem scope. |

### Remaining policy and rollout boundaries (2026-10-05)

`site.network.public_host_rewrite` (`PUBLIC_HOST_REWRITE`) is off by default.
This ADR changes no setting. Required full-stack proxy coverage and real-proxy
burn-in precede a separate default-on decision; the current integration job
is not itself a required merge check. Existing
[proxy matrix](../../apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb)
and [stateful boundary specs](../../apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb)
exercise both settings, but do not establish complete emitter or gem coverage.

The remaining work includes SSO-link-confirm email, billing/receipt/secret
and social emitters, actual CSP and Referrer-Policy headers, live WebAuthn,
and platform SAML with rewriting enabled. The stateful boundary specs cover
configured trusted-proxy `filter` mode with trusted/untrusted peers and both
rewrite settings for HTTPS, Secure sessions, and login. Other proxy modes and
the full emitter matrix under configured trust still need coverage.

Two source-inspected policy gaps require explicit disposition before
claiming the boundary is ready for default-on:

- **WebAuthn and reauth fallback:** an `:invalid` request, or a custom context
  without its published record, makes the WebAuthn resolver decline. RP ID,
  ceremony origin, and reauth origin can then come from raw Rack authority.
  Invalid requests are not rewritten. The expected refusal/fallback and a
  live ceremony regression remain to be decided; this proposal chooses
  neither by implication.
- **Organization scope:** when received `Host` names custom domain A and
  detected/display context names custom domain B, the loader checks A+B with
  rewriting off but can check only B after rewriting. A membership permitted
  on B but not A can therefore pass that scope check only with rewriting on.
  Existing coverage pins canonical-origin-to-tenant selection, not this
  two-custom-domain case. This proposal does not approve that reduction;
  preserving A for membership checks or deliberately excluding transport A
  requires an explicit policy decision and regression coverage.

Other unresolved behavior is not made acceptable by being outside hostname
projection: the display-origin allowance on invalid classification, tenant
lookup failure responses, and the Host-preserving bare-Host/forwarded-port
mismatch remain separate concerns. On the latter, Rack's `port` can include a
trusted forwarded port that `base_url` omits; only actual rewrites currently
normalize that pair.

Use the linked proxy upgrade guidance for edge-header and staged SAML
callback changes. Do not infer release, completed burn-in, or acceptance of
these residual behaviors from the presence of this record.
