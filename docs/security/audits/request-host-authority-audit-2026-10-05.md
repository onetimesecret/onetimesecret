# Request-host authority: consumer audit and rollout coverage

Snapshot: 2026-10-05, with the rollout-coverage section and three consumer
rows updated 2026-10-07 for #4673, #4674, #4675 and #4680 (#4682). Supporting evidence and coverage notes for
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
| `lib/onetime/application/organization_loader.rb`; `lib/onetime/operations/sessions/track_metadata.rb` | Public/effective: domain-based selection reads effective `HTTP_HOST`, including during session commit. Membership scope also uses the published tenant record. An unregistered display host withholds every organization (#4672); a host that detection rejects carries no scope (#4678, ADR-050). The two-custom-domain scope reduction remains unresolved; see ADR-050's open decisions and #4697. |
| `lib/onetime/session.rb` and `rack-session` | Session preparation is upstream; commit sees the shared environment. The session cookie's Domain is not automatically derived from rewritten `Host`; organization metadata can change through the loader. |
| `lib/onetime/middleware/cookie_tossing.rb` | Public: clearing cookies use DetectHost, falling back to Rack host only when detection is absent. Duplicate-cookie refusal runs before session/rewrite and short-circuits. |
| `rack-protection` `HttpOrigin`, through global Security and the auth profile | Security-sensitive public origin: compare the request's effective scheme, host, and port. Rewriting refuses an origin-target Origin and can admit the public non-default-port or HTTP origin that the off setting refused. Explicit allowances remain separate. |
| `lib/onetime/middleware/http_origin_options.rb` | Resolved public/canonical policy: retain its resolved-host checks. Its `HTTP_HOST` / `SERVER_NAME` fallback occurs without detection and is not repaired by rewriting. Since #4673 the display-origin allowance is made only for a host classified `:canonical`, `:subdomain` or `:custom`; an `:invalid` host with an absent lookup is refused, and one whose read failed is still admitted so the application's own refusal answers. |
| `lib/onetime/security/saml_callback_store.rb`; `lib/onetime/middleware/saml_callback_transport.rb` | Security-sensitive received scope: reconstruct staging authority from the original `Host`, together with detected/display context and callback path. Do not re-key staged callbacks when the setting changes. The transport boundary runs upstream. |
| `apps/web/auth/lib/public_host.rb`; `apps/web/auth/config/overrides/public_base_url.rb` | Authorized public, then configured canonical: keep the resolvers. Credential emails additionally require recipient membership/domain scope; absent authorized origin raises rather than falling back to raw Rack authority. |
| `apps/web/auth/config/features/omniauth.rb`; `apps/web/auth/config/hooks/omniauth_tenant.rb` | Public: SSO URL generation keeps the required allowlisted resolver. Tenant lookup uses resolved context; its last-resort `request.host` fallback remains for missing usable resolved values, not as authorization evidence. |
| `apps/web/auth/config/features/webauthn.rb`; `apps/web/auth/operations/reauth_offer.rb` | Security-sensitive public RP/origin inputs with received-authority fallbacks. Those fallback branches remain unresolved; see ADR-050's open decisions. The live ceremony rows in `apps/web/auth/spec/integration/full_mfa/host_proxy_webauthn_spec.rb` pin the inputs as they are today. |
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
default-on decision, tracked in #4694. Since #4674 the `ci-verdict` check
requires every CI test job, among them `ruby-integration-full`, which runs
the `host_proxy_*` specs in the full-sqlite lane, and `host-proxy-wire`. The
live WebAuthn ceremony rows (`full_mfa`) and the platform SAML rows
(`full_saml_platform`) run only on a pull request that matches
`.github/auth-paths.yml` or carries the `ci:auth` label, and on main,
nightly and release runs. The
[proxy matrix](../../../apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb),
the [stateful boundary specs](../../../apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb)
and the files #4680 added beside them (`host_proxy_origin_spec.rb`,
`host_proxy_document_spec.rb`, `host_proxy_link_emitters_spec.rb`,
`host_proxy_trusted_proxy_spec.rb`, `host_proxy_failure_responses_spec.rb`)
run every row with both settings and pin current behaviour; they do not
establish gem coverage.

#4680 covered the emitters listed here on 2026-10-05: the SSO-link-confirm
email, the V1 secret links (create, receipt read, `secret_link` email), the
billing plan redirect, the CSP `form-action` extras and the og/twitter tags,
`HttpOrigin` on SSO initiation, trusted-proxy `filter` and `depth` modes, a
live WebAuthn ceremony on each shape a browser can be on
(`full_mfa/host_proxy_webauthn_spec.rb`), and platform SAML with the setting
off and on. Still not covered: a Host-rewriting proxy in front of the
platform host (the platform lane boots an IP-literal `site.host`; KNOWN LIMIT
in `full_saml_platform/platform_saml_sso_spec.rb`), the `Referrer-Policy`
header value (#4542), the Sentry event URL (#4321), the Host-preserving bare
`Host` with a trusted `X-Forwarded-Port` (#4681), and the two-custom-domain
organization-scope case below. Rows that pin behaviour #4680 did not change:
G04 and G08 in `host_proxy_origin_spec.rb` (Origin admissions that differ by
setting, part of the #4694 gate), TD01 and TD04 in
`host_proxy_trusted_proxy_spec.rb` (`depth` mode honours `X-Forwarded-Host`
from any peer), the V1 receipt read's `metadata_url` on `site.host` (#4695)
and the og/twitter tags on `site.host` for tenant pages (#4696).

Existing coverage pins canonical-origin-to-tenant selection, not the
two-custom-domain organization-scope case described in
[ADR-050's open decisions](../../adr/adr-050-request-host-authority.md#open-decisions-and-rollout)
and tracked in #4697. The live ceremony rows pin the WebAuthn inputs as they
are today and the refusal of sign-in on an `:invalid` host before any
ceremony starts; the fallback decision itself (#4223 item 3) remains open in
ADR-050.

Use the [proxy upgrade guidance](../../operations/proxy-authority-header.md)
for edge-header and staged SAML callback changes. This snapshot does not
establish release readiness, completed burn-in, or acceptance of residual
behavior.
