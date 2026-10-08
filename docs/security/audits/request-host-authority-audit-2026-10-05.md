# Request-host authority: consumer audit and rollout coverage

Snapshot: 2026-10-05. Supporting evidence and coverage notes for
[ADR-050: Request-Host Authority at the Rack Boundary](../../adr/adr-050-request-host-authority.md),
not an independent policy decision or default-on approval. The ADR records the
open policy decisions; this document records the dated implementation inventory.

## Consumer dispositions

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
| `lib/onetime/application/organization_loader.rb`; `lib/onetime/operations/sessions/track_metadata.rb` | Public/effective: domain-based selection reads effective `HTTP_HOST`, including during session commit. Membership scope also uses the published tenant record. The two-custom-domain scope reduction remains unresolved; see ADR-050's open decisions. |
| `lib/onetime/session.rb` and `rack-session` | Session preparation is upstream; commit sees the shared environment. The session cookie's Domain is not automatically derived from rewritten `Host`; organization metadata can change through the loader. |
| `lib/onetime/middleware/cookie_tossing.rb` | Public: clearing cookies use DetectHost, falling back to Rack host only when detection is absent. Duplicate-cookie refusal runs before session/rewrite and short-circuits. |
| `rack-protection` `HttpOrigin`, through global Security and the auth profile | Security-sensitive public origin: compare the request's effective scheme, host, and port. Rewriting refuses an origin-target Origin and can admit the public non-default-port or HTTP origin that the off setting refused. Explicit allowances remain separate. |
| `lib/onetime/middleware/http_origin_options.rb` | Resolved public/canonical policy: retain its resolved-host checks. Its `HTTP_HOST` / `SERVER_NAME` fallback occurs without detection and is not repaired by rewriting. The display-origin allowance on `:invalid` requests remains an independent open concern. |
| `lib/onetime/security/saml_callback_store.rb`; `lib/onetime/middleware/saml_callback_transport.rb` | Security-sensitive received scope: reconstruct staging authority from the original `Host`, together with detected/display context and callback path. Do not re-key staged callbacks when the setting changes. The transport boundary runs upstream. |
| `apps/web/auth/lib/public_host.rb`; `apps/web/auth/config/overrides/public_base_url.rb` | Authorized public, then configured canonical: keep the resolvers. Credential emails additionally require recipient membership/domain scope; absent authorized origin raises rather than falling back to raw Rack authority. |
| `apps/web/auth/config/features/omniauth.rb`; `apps/web/auth/config/hooks/omniauth_tenant.rb` | Public: SSO URL generation keeps the required allowlisted resolver. Tenant lookup uses resolved context; its last-resort `request.host` fallback remains for missing usable resolved values, not as authorization evidence. |
| `apps/web/auth/config/features/webauthn.rb`; `apps/web/auth/operations/reauth_offer.rb` | Security-sensitive public RP/origin inputs with received-authority fallbacks. Those fallback branches remain unresolved; see ADR-050's open decisions. |
| `apps/web/auth/config/email/`; SSO-link mail injection in `apps/web/auth/config/hooks/omniauth.rb`; `lib/onetime/mail/views/` and `templates/` | Auth URLs consume recipient-bound origins. Display-domain labels are not URL authority. Layout and secret-mail URLs use supplied `baseuri` / `share_domain`, with configured canonical fallback. V3 feedback's display-domain label falls back to configured `site.host`; it is escaped text, not destination authority. |
| `apps/web/billing/controllers/plans.rb`, `billing.rb`; `apps/web/billing/operations/create_checkout_link.rb`; core/billing controller URI helpers | Canonical: checkout success/cancel and portal-return URLs intentionally use configuration, not the tenant request. URI host/default operations are not Rack host reads. |
| `lib/onetime/billing_config.rb`; Stripe initializer and bootstrap config serializer | Configured outbound checkout allowlist: do not migrate to received or rewritten Host. Browser validation in `src/utils/redirect.ts` compares the destination with configured checkout, Stripe, and browser same-origin authorities. |
| `lib/onetime/rodauth_admin.rb` | Configured admin URL, not inferred request authority. |
| `lib/onetime/middleware/tenant_csp_extras.rb`; `lib/onetime/tenant_sso_resolution.rb`; core request setup | Public tenant context: keep the resolved tenant/IdP source for CSP extras, including response-path emission. No raw Host authority is needed. |
| Secret creation and receipt/reveal/burn logic under `apps/api/v1/`, `v2/`, and `incoming/`; secret-mail views | Public sharing context or persisted `share_domain`, then canonical fallback. Receipt/secret destinations do not automatically follow the current Rack host. |
| `apps/web/core/views/helpers/initialize_view_vars.rb`; `views/base.rb`; `templates/partials/head.rue` | Public title/branding but canonical social URL/domain and relative-image authority. Rewriting does not turn these into tenant URLs. `head-secret-share.rue` has no identified live inclusion and is not a verified emitter. |
| `lib/onetime/session/surface.rb` | Security-sensitive resolved classification/tenant identity: retain published context, not raw Rack authority. |
| `lib/onetime/initializers/setup_diagnostics.rb` | Scrub the SDK event's URL; this is not a Rack authority resolver. How Sentry constructs that URL is outside the inspected gem scope. |

## Rollout coverage

`site.network.public_host_rewrite` (`PUBLIC_HOST_REWRITE`) is off by default.
Required full-stack proxy coverage and real-proxy burn-in precede a separate
default-on decision; the current integration job is not itself a required
merge check. Existing
[proxy matrix](../../../apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb)
and [stateful boundary specs](../../../apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb)
exercise both settings, but do not establish complete emitter or gem coverage.

The remaining work includes SSO-link-confirm email, billing/receipt/secret
and social emitters, actual CSP and Referrer-Policy headers, live WebAuthn,
and platform SAML with rewriting enabled. The stateful boundary specs cover
configured trusted-proxy `filter` mode with trusted/untrusted peers and both
rewrite settings for HTTPS, Secure sessions, and login. Other proxy modes and
the full emitter matrix under configured trust still need coverage.

Existing coverage pins canonical-origin-to-tenant selection, not the
two-custom-domain organization-scope case described in
[ADR-050's open decisions](../../adr/adr-050-request-host-authority.md#open-decisions-and-rollout).
The WebAuthn/reauth fallback decision also needs a live ceremony regression.

Use the [proxy upgrade guidance](../../operations/proxy-authority-header.md)
for edge-header and staged SAML callback changes. This snapshot does not
establish release readiness, completed burn-in, or acceptance of residual
behavior.
