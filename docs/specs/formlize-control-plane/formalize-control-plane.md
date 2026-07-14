# docs/specs/formlize-control-plane/formalize-control-plane.md

written: 2026-07-14

---

# Formalize the canonical-domain / custom-domain split (control plane vs data plane)

## Summary

We have install-level configuration (`etc/defaults/*.yaml`, ENV) and domain-level configuration (per-`CustomDomain` brand settings, `CustomDomain::SsoConfig`), but the boundary between them grew feature-by-feature and is fuzzy in places. Two things are missing:

1. **A stated architectural rule** for which surfaces are served on which class of hostname, and how install-level settings interact with domain-level settings.
2. **Enforcement of that rule** — most visibly, pinning the Colonel (admin) surface to the canonical domain so it is never reachable via a custom domain.

This issue proposes an ADR that makes the rule explicit, an enforcement plan for privileged surfaces, a config reorganization that encodes the rule in the config schema itself, and the corresponding documentation updates.

We've already made one decision in this space ad hoc: `auth.full.sso.allow_platform_fallback_for_tenants` (default `false`) decides whether a custom domain may inherit install-level SSO credentials. That was the right call, but it was made locally for one feature. The ADR generalizes it so the next twenty features don't each re-litigate the question.

## Background: current state

**Canonical identity is implicit.** `site.host` is the closest thing to a canonical domain, and `features.domains.default` ("the default domain used for link URLs; when not set, `site.host` is used") already distinguishes _where secrets are shared_ from _where the install lives_. But nothing states that `site.host` is the privileged hostname, and nothing enforces it.

**Colonel is role-pinned, not host-pinned.** Colonel accounts are managed via `bin/ots customers role promote`, and colonel routes check the role. As far as routing is concerned, though, the colonel UI and its API endpoints respond on any Host header the app is served under — including custom domains when `features.domains.enabled: true`. The same applies to account settings, org management, and billing surfaces.

**Install-level and domain-level settings interleave without stated semantics.** Examples of the fuzziness:

- Authentication spans two layers with undefined plane scope: `auth.mode` (`AUTHENTICATION_MODE`) switches the auth subsystem itself, while `site.authentication.enabled|signup|signin|required` is policy on top of a running subsystem. Neither declares which hostnames it governs — does disabling signin affect tenant users on custom domains, or only account holders on the canonical domain? Undefined.
- `site.interface.ui.header.branding.*` is install-level branding; per-domain brand settings override it in practice — but "domain overrides install" is convention, not contract.
- `site.interface.api.guest_routes.*` and `ui.capabilities.*` are install-level. Whether a tenant domain could ever want (or be allowed) different values is unspecified.
- `auth.full.sso.allow_platform_fallback_for_tenants` explicitly governs install→domain inheritance — the only setting that does.
- Session config (`site.session`) issues one cookie (`onetime.session`) with the same policy across all hostnames, privileged or not.

## Proposal

### Part A — ADR: "Canonical domain as control plane"

Add `docs/architecture/decisions/NNNN-canonical-domain-control-plane.md`. Draft content follows; the PR that adds it is the place to argue specifics.

#### Decision

Every install has exactly one **canonical domain** (today: `site.host`). Custom domains are **data-plane surfaces**: they serve the branded secret lifecycle (conceal/reveal/burn/receipt, homepage form, incoming-secrets form) and nothing else. All control-plane surfaces — Colonel, account settings, org/domain/billing management, signup/signin for account holders, privileged API — are served **only** on the canonical domain.

This is the pattern the rest of the industry converged on: Keycloak splits `hostname` from `hostname-admin`; Ghost splits `url` from `admin.url`; Shopify moved every merchant to `admin.shopify.com` while storefronts stay on custom domains; Zendesk host-mapping applies to the Help Center only.

#### Why (the four reasons)

1. **Availability.** A lapsed custom domain, broken DNS, or failed ACME issuance must never take out admin access. The canonical domain is the recovery path, so nothing on it may depend on tenant-controlled infrastructure. (This is why hosted Discourse keeps `*.discourse.group` working regardless of custom-domain state.)
2. **Session and CSRF scoping.** With one privileged hostname, cookie scope, `same_site` policy, and origin allowlists (`middleware.authenticity_token`, `middleware.http_origin`, CSP) are simple and auditable. Serving authenticated sessions across N tenant hostnames multiplies the CSRF/cookie-tossing surface — we carry middleware for exactly these attacks (`cookie_tossing`, `http_origin`) that gets weaker with every extra privileged hostname.
3. **Single hardening point.** IP allowlisting, WAF rules, forced SSO/MFA, rate limits, and monitoring for admin access can be applied to one hostname at the proxy layer (Caddy/nginx) without per-tenant configuration.
4. **Tenant-controlled DNS is a phishing surface.** The tenant (or whoever registers their lapsed domain, or compromises their DNS) controls where a custom domain points. If privileged UI is served there, a hostile or compromised tenant domain becomes a credential-harvesting clone of our admin login — with a valid certificate. Never render a privileged login form on a hostname whose DNS we don't control.

#### Surface classification

| Surface                                                                                         | Canonical     | Custom domain                                     |
| ----------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------- |
| Secret reveal/burn/receipt                                                                      | ✓             | ✓                                                 |
| Homepage / conceal form, incoming form                                                          | ✓             | ✓ (per-domain brand + homepage mode)              |
| Guest API (`/api/v3/guest/*`)                                                                   | ✓             | ✓ (subject to install-level `guest_routes` floor) |
| Tenant end-user signin on that domain (data-plane auth; per-domain SSO is the current instance) | ✓             | ✓ — scoped to that domain                         |
| Account signup/signin (account holders)                                                         | ✓             | ✗                                                 |
| Account settings, org/domain/billing management                                                 | ✓             | ✗                                                 |
| Colonel UI + colonel API                                                                        | ✓             | ✗                                                 |
| Authenticated (API-key) API                                                                     | ✓             | ✗ (recommend; see open questions)                 |
| Internal apps (`apps/internal`, ACME ask endpoint)                                              | loopback only | ✗                                                 |

The one deliberate nuance: data-plane authentication. A custom domain may authenticate its own users for data-plane actions — e.g. requiring signin to create secret links while the public homepage form is disabled. Per-domain SSO (`CustomDomain::SsoConfig`) is the first implemented instance of this capability; future methods are further instances, not new architectural decisions. None of it is control-plane access, so it stays on the custom domain. _Managing_ a domain's auth config is control-plane and does not.

#### Install-level vs domain-level: interaction semantics

Every configurable behavior gets exactly one of three scopes, declared in the config schema:

1. **`platform`** — exists only at install level; domains can never see or override it. Examples: `site.secret`, `redis.*`, `middleware.*`, `diagnostics.*`, `jobs.*`, `auth.mode` (`AUTHENTICATION_MODE`), control-plane authentication policy (`site.authentication.*`), colonel access.
2. **`floor`** — install level sets a ceiling on capability; domain level may _restrict further but never expand_. Monotonic: turning something off at install level turns it off everywhere; a domain cannot re-enable it. Examples: data-plane authentication capability (proposed `features.domains.authentication.enabled`), `api.guest_routes.*`, `ui.capabilities.*`, `secret_options.passphrase.required` (a domain may require passphrases even if the install doesn't; it may not waive an install-level requirement).
3. **`default`** — install level provides the value used when a domain hasn't set its own; domain level freely overrides. Examples: branding (`header.branding.*`, logo, locale, `footer_links`), homepage mode, TTL options within install-level bounds.

Authentication doesn't fit a single scope — it decomposes across three layers, and the ADR should state this explicitly:

1. **Subsystem switch** — `auth.mode` (`AUTHENTICATION_MODE`). Platform scope. When disabled there are no sessions and no identity store; authentication is off on every plane and there is nothing to override.
2. **Control-plane policy** — today's `site.authentication.enabled|signup|signin`. Platform scope, canonical-only by definition after the split: governs colonel login, the secret-creation workspace, and account signup/signin/management on the canonical domain.
3. **Data-plane capability** — may custom domains authenticate their users at all? Floor scope: install level grants or denies (proposed `features.domains.authentication.enabled`); each domain configures whether and how within that grant.

This makes "canonical control plane locked down, custom domains still authenticating users to create secrets" a supported configuration — administration continues via `bin/ots` — expressed through decomposition rather than a domain-level override of an install-level off-switch. Monotonicity holds at every layer, and the dependency chain is strictly one-directional: mode → plane policies → per-domain config. Data-plane auth requires the auth subsystem to be enabled because it authenticates against the shared identity store.

The existing `allow_platform_fallback_for_tenants` slots in cleanly: it's the knob for whether an install-level _credential_ may serve as a domain-level _default_ (default no). The ADR should name this the general rule for secrets/credentials: **install-level credentials never flow to tenant domains unless explicitly opted in per install, and ideally per domain.**

### Part B — Pin the Colonel (and control plane) to the canonical domain

- [ ] Add a host-guard at the routing layer (Otto/rack level, not per-handler) that classifies the request Host as `canonical` or `custom_domain` once, early, alongside the existing domain-strategy resolution — then declares each route's allowed class. Control-plane routes on a non-canonical Host return **404**, not 403 or a redirect: don't advertise that an admin surface exists, and never redirect a user from a tenant-controlled hostname to a privileged login (that's the phishing vector — reason 4).
- [ ] Colonel first: `/colonel` UI and colonel API endpoints refuse non-canonical hosts even for a validly-authenticated colonel session. Then account/org/domain/billing management routes.
- [ ] Session partitioning: authenticated control-plane sessions are only ever created and honored on the canonical Host. A session cookie presented on a custom domain grants at most data-plane identity. Revisit `site.session` (one cookie, one policy) as part of this — consider a distinct cookie name/policy for the canonical domain (`__Host-` prefix candidate).
- [ ] `development.domain_context_enabled` (persona testing override) must not be able to spoof the canonical/custom classification for the host guard — the config already says production-off; the guard should be independently immune.
- [ ] Vue router: hide control-plane navigation when the app is served from a custom domain, but treat frontend checks as cosmetic; the backend guard is the enforcement.
- [ ] Tests: request specs for every control-plane route × {canonical host, custom host, unknown host}; regression test that a colonel session on a custom domain gets 404.

### Part C — Config reorganization

Goal: make the schema teach the model, so the next contributor can't add a setting without picking a scope.

- [ ] **Name the canonical domain explicitly.** Introduce `site.canonical_domain` (ENV `CANONICAL_DOMAIN`), defaulting to `site.host` for backward compatibility. `site.host` remains "what the app answers to / link generation fallback"; `canonical_domain` is the privileged identity. Alias, deprecate gently, don't break existing installs.
- [ ] **Split authentication config by plane.** `site.authentication.*` becomes explicitly control-plane policy; add the data-plane floor (`features.domains.authentication.enabled` or similar); `auth.mode` stays the subsystem switch. Deprecation aliases per the migration rules below.
- [ ] **Declare scope per key.** Whether as a comment convention in `config.defaults.yaml` (`# scope: platform|floor|default`) or, better, in the config normalization layer so violations are checkable at boot. The normalization layer already forces values in places (e.g. `allow_nil_global_secret` outside dev); this extends that mechanism.
- [ ] **Regroup by scope, not by feature age.** Current `site.*` mixes platform config (secret, session, middleware) with floor config (authentication, api.guest_routes, ui.capabilities) and default config (branding, footer_links). Target shape — exact naming to be settled in the PR:
  - `site.*` → platform identity + security (canonical_domain, host, ssl, secret, session, middleware, security)
  - `defaults.*` (or `tenant_defaults.*`) → everything a domain may override (branding, locale, homepage mode, TTL presentation)
  - `limits.*` (or keep in place but marked `floor`) → capability floors (authentication, guest_routes, capabilities, passphrase policy)
  - `features.domains.*` stays: it's platform config _about_ the domains feature itself.
- [ ] **Per-domain settings model.** Domain-level overrides continue to live on `CustomDomain` (Redis), but validated against the same schema+scope declarations, so a `floor` key can't be expanded from the domain side by construction rather than by review vigilance.
- [ ] Migration/back-compat: old keys and ENV vars keep working for ≥2 minor releases with boot-time deprecation warnings that name the replacement.

### Part D — Documentation

- [ ] The ADR itself (`docs/architecture/decisions/`).
- [ ] `etc/defaults/config.defaults.yaml` + `auth.defaults.yaml`: scope annotations on every key; header comment linking to the ADR.
- [ ] ENV var reference: mark each variable install-scoped vs domain-affecting; add `CANONICAL_DOMAIN`.
- [ ] docs.onetimesecret.com self-hosting guide: new page "Canonical domain vs custom domains" — what belongs where, how to harden the canonical domain at the proxy (IP allowlist / forced SSO example), and the explicit warning that admin is intentionally unreachable on custom domains (this _will_ generate "bug" reports otherwise; the docs page is the pre-emptive answer).
- [ ] `etc/examples/Caddyfile-example`: show the split — canonical vhost with optional hardening block, on-demand TLS vhost serving data-plane only.
- [ ] Custom-domain docs: state plainly that admin/account functions live on the canonical domain by design.
- [ ] Upgrade notes for the release that enables the host guard: behavior change for anyone currently administering via a custom domain.

## Acceptance criteria

- [ ] ADR merged with the surface classification and three-scope semantics.
- [ ] Colonel routes return 404 on non-canonical hosts (backend-enforced, tested).
- [ ] Control-plane session cookies not honored on custom domains.
- [ ] Every key in `config.defaults.yaml` / `auth.defaults.yaml` carries a declared scope; boot-time validation exists for at least `floor` violations.
- [ ] Authentication config decomposed by plane (subsystem mode / control-plane policy / data-plane floor) per the ADR.
- [ ] `CANONICAL_DOMAIN` supported with `site.host` fallback; no breaking change for existing installs.
- [ ] Docs updated per Part D.

## Out of scope

- Multi-region/jurisdiction routing (`features.regions`) — same ADR applies per region; no new decisions needed here.
- Per-organization (as opposed to per-domain) setting overrides — orgs may become a fourth scope later; the three-scope model should be designed so inserting `org` between install and domain doesn't break the lattice.
- Any change to secret encryption or link formats.

## Open questions

1. **Authenticated API on custom domains.** Recommendation above is canonical-only (API keys are control-plane credentials). Counterargument: existing integrations may point API clients at a branded hostname. Decide before the host guard ships; if we allow it, it should be a `floor`-scoped opt-in, off by default.
2. **`features.domains.default` vs `canonical_domain`.** With an explicit canonical domain, does `DEFAULT_DOMAIN` remain purely "which domain generated links use"? Probably yes, but the ADR should state it so the two don't drift back together.
3. **Single-domain installs.** When `features.domains.enabled: false` (the majority of self-hosted installs), the guard is a no-op — canonical is the only hostname. Confirm the implementation costs nothing in that path.

---

> Do any of the aforementioned products, run their multitenant SaaS installations from their control-plane install, with each tenant running on the data-plane? Or do any run a separate UI/frontend for their self-service SaaS onboarding to multitenant?

Both patterns exist, and which one a vendor uses is determined almost entirely by one variable: whether tenancy lives inside the application's data model or at the instance level.

**In-app tenancy → the SaaS is the control-plane install.** WordPress.com is literally WordPress Multisite (sharded, but the tenancy is the application's own); network admin is the control plane and signup is in-app. GitLab.com runs the same codebase as self-managed as one giant installation where tenants are namespaces — onboarding is the app's own signup. Chatwoot's app.chatwoot.com and Sentry's sentry.io are the same story: the OSS app run multi-tenant, superadmin surface as control plane, self-service onboarding shipped in the product itself. Closed platforms with row-level tenancy (Shopify, Zendesk) are the same shape.

**Instance-per-tenant → a separate provisioning app appears.** Ghost is single-tenant per install, so Ghost(Pro) has a proprietary account/billing portal that orchestrates instances; the OSS app contains zero SaaS onboarding. Supabase likewise: each project is a dedicated stack, and the hosted control plane is a separate (partly proprietary) platform. The cleanest public example is Frappe Cloud: their control plane is itself a separate open-source Frappe app (`frappe/press`) that provisions ERPNext benches. Discourse hosting sits in between — the OSS app has multisite support, but CDCK's customer onboarding/billing is a separate system that provisions sites onto multisite clusters.

The instructive hybrid is GitLab: tenancy is in-app, but billing still got extracted into a satellite app (CustomersDot, customers.gitlab.com) because Zuora/subscription logic didn't belong in the product every self-hoster runs. That's the recurring compromise for open-core vendors with in-app tenancy: onboarding stays in the product, monetization plumbing leaks out into a satellite.

OTS is structurally in the first camp — orgs and custom domains are in-app tenancy, so running onetimesecret.com as the control-plane install with tenants on the data plane is the pattern your peers use, not an anomaly. The GitLab precedent is the one to watch: the pressure point isn't onboarding, it's whether Stripe-specific billing eventually wants to be a satellite rather than config-gated code (`billing.example.yaml`) inside the self-hosted product.
