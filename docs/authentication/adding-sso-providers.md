# Adding an SSO Provider

All SSO provider wiring is data in one place: one definition file per
provider under `lib/onetime/sso_provider/`, collected in order by
`lib/onetime/sso_provider/registry.rb`
(`Onetime::SsoProvider::Registry::DEFINITIONS`).
Both consumers read the registry, so they cannot drift:

- `Onetime::AuthConfig#provider_definitions` — serializer gating
  (`sso_providers`), per-provider email-linking trust flags, and the CSP
  `form-action` origins.
- `Auth::Config::Features::OmniAuth.configure` — boot-time strategy
  registration (real credentials, or placeholder credentials for
  org-level tenant SSO).

The frontend is fully provider-agnostic: `route_name` + `display_name` flow
from the serializer through `ssoProviders` into `SsoButton`, so a new backend
provider appears on the login and signup pages with zero frontend changes.

## Checklist

1. **Pick the strategy gem** and add it to the `Gemfile`
   (e.g. `gem 'omniauth-gitlab'`), then `bundle install`.

2. **Decide the issuer question first** (see below). Prefer OIDC-capable
   providers.

3. **Add one definition file** under `lib/onetime/sso_provider/`
   (e.g. `lib/onetime/sso_provider/gitlab.rb`), then require it and append
   its `DEFINITION` to `DEFINITIONS` in
   `lib/onetime/sso_provider/registry.rb`. Copy an existing file of the
   same shape (issuer-capable: copy `entra.rb` or `oidc.rb`; plain OAuth2:
   copy `github.rb`). Every field is documented in the registry header.
   Keep the env prefix consistent (`FOO_CLIENT_ID`, `FOO_ROUTE_NAME`,
   `FOO_DISPLAY_NAME`, `FOO_TRUST_EMAIL_FOR_LINKING`) — the registry spec
   enforces this.

4. **Run the guard rails** — always through the lane runner (never `rspec`
   directly; see AGENTS.md — the runner clears ambient env and provisions
   isolated test services):

   ```bash
   tests/lanes/run unit       # registry shape + AuthConfig specs
   tests/lanes/run full-pg    # auth app provider registration + integration
   ```

5. **Set the env vars** for the deployment and verify the provider appears in
   the serializer output (`sso_providers`) and registers at boot
   (`[OmniAuth] Configuring …` in the log).

6. **Optional frontend polish** — a brand icon: add the glyph to
   `src/shared/components/icons/sprites/MdiSprites.vue` and map the default
   route name in `PROVIDER_ICONS` in
   `src/apps/session/components/SsoButton.vue`. Unmapped providers get the
   neutral building-office icon.

7. **Optional ordering** — `SSO_PROVIDER_ORDER` (comma/space-separated route
   names) reorders the buttons; unlisted providers keep registry order after
   the listed ones.

## Known limitations

Strategy registration is a **boot-time snapshot**: `configure_provider` reads
the env vars and `orgs_sso_enabled?` once, when the auth app boots. Adding or
removing a provider, changing its credentials, or toggling org-level SSO
requires a restart — a runtime config reload does not re-register strategies.
(The serializer-side values — button order via `SSO_PROVIDER_ORDER`, display
names — are read per request, but a provider that didn't register at boot
can't appear regardless.)

## The issuer decision (read before adding anything)

The identity table is keyed `(provider, issuer, uid)`. Issuer scoping is what
isolates tenants on the org-SSO surface, so every new provider must be
classified:

- **Issuer-capable** (`issuer_capable: true`): OIDC discovery providers, and
  strategies whose auth hash carries a validated `iss` claim in
  `extra.raw_info` (Entra ID). These slot into the existing issuer resolution
  chain (`resolve_issuer` in `apps/web/auth/config/features/omniauth.rb`) and
  work on **both** the platform and tenant surfaces. If the strategy exposes
  its issuer some other way, extend `resolve_issuer` — never let a real IdP
  issuer collapse to the `''` sentinel.

- **Issuerless** (`issuer_capable: false`): plain OAuth2 providers (GitHub,
  Google, Facebook, Discord, GitLab in OAuth2 mode). They resolve to the `''`
  sentinel issuer on every surface, so the **tenant surface refuses them at
  callback time** (`refuse_issuerless_on_tenant?` — this is deliberate,
  fail-closed protection against cross-surface identity binds). They remain
  available for platform SSO only. Each new issuerless provider re-adds a
  `(provider, '', uid)` platform-collision surface, so add them sparingly.

### Install-wide discovery issuer check (`discovery_issuer_var`)

An issuer-capable provider that uses OIDC discovery (`discovery: true`) with an
install-wide issuer from the env should set `discovery_issuer_var` to the name
of that env var (`oidc.rb` sets `'OIDC_ISSUER'`). On the first platform sign-in
attempt in each process, the `omniauth_setup` hook fetches the discovery
document and compares its `issuer` to the env value with exact string equality
(`Onetime::SsoProvider::IssuerValidation`). On a mismatch the attempt is
redirected to `/signin?auth_error=sso_issuer_mismatch` without reaching the
IdP, and `AuthConfig#provider_active?` reports the provider unavailable while
the result is cached. Route registration does not change, so tenant OIDC on
the same route keeps working. See
[Issuer mismatch](per-install-sso.md#issuer-mismatch) for timing and log
fields.

Rules:

- Name only the install-wide issuer env var. Tenant issuers come from the
  `SsoConfig` record and are checked by Test Connection, not by this hook.
- Leave it unset for providers without discovery or with a fixed, non-operator
  issuer (Entra ID, plain OAuth2 providers).
- The placeholder issuer (`https://placeholder.invalid`) is never checked.

When a provider supports both modes (GitLab, Okta), integrate it through OIDC
(`omniauth_openid_connect` with the provider's issuer) rather than its bespoke
OAuth2 strategy — it then inherits issuer scoping for free. Auth0 is
configured this way: the bespoke `omniauth-auth0` strategy was tried and
dropped before release because its claim validation never runs (see the note
below) and its `jwt ~> 2` pin held the whole bundle off jwt 3.x. Apple is a
**platform-only** provider, absent from `SsoConfig::PROVIDER_ROUTE_MAP`.

## Known provider quirks

- **Apple** (`omniauth-apple`): issuer-capable, but via a **static strategy
  option** rather than discovery or a claim read — the gem hard-codes
  `ISSUER = 'https://appleid.apple.com'` and rejects any id_token whose `iss`
  differs (after checking the signature against Apple's JWKS), while nesting
  the decoded JWT under `extra.raw_info.id_info` with symbol keys, a shape
  `resolve_issuer`'s token-issuer branch does not read. The definition
  therefore declares `issuer:` itself; precedence #1 returns it.
  **Operator prerequisite:** Apple sets `response_mode=form_post` whenever a
  scope is requested, so the callback is a **cross-site POST**. A
  `SameSite=Lax` cookie (this app's default) is withheld on it, taking the
  OmniAuth state and nonce with it, so Sign in with Apple requires
  `site.session.same_site: none` together with `secure: true`. A cross-site
  POST also hits `Rack::Protection::HttpOrigin`, which guards the auth app and
  would deny the callback with a 403 before OmniAuth runs — every earlier
  provider's callback was a GET, which `safe?` short-circuits, so nothing
  exercised that path. That half is handled in code:
  `Onetime::Middleware::HttpOriginOptions` allows a POST to an OmniAuth
  **callback** path when the Origin is one of the configured IdP origins, and
  deliberately does not extend that to the request phase. **Any future
  `form_post` provider inherits this; a provider that posts back from an
  origin outside `AuthConfig#sso_idp_origins` would still 403.** Do not drop the
  scope to get Apple's GET redirect instead — without `email name` Apple
  returns no email and account creation cannot complete. The **name** arrives
  only on the **first** authorization for a given Services ID (in the `user`
  POST param); the **email** comes from the id_token on every authorization,
  so repeat sign-ins and JIT account creation are unaffected. The email may be
  a private-relay address (`@privaterelay.appleid.com`, flagged by
  `is_private_email`) — which is why `APPLE_TRUST_EMAIL_FOR_LINKING` defaults
  to false.
- **Auth0**: use generic OIDC (`OIDC_*`; see `per-install-sso.md`), with
  `OIDC_ISSUER` carrying the trailing slash Auth0 puts in `iss`
  (`https://<tenant>/`); the issuer check is exact. The bespoke
  `omniauth-auth0` gem (3.2) is not integrated: its claim validation
  (`verify_iss`/`verify_aud`/`verify_nonce`/`verify_expiration`) is gated on
  `session_authorize_params[:scope]`, but that hash is built as
  `params.to_hash` on a `Hashie::Mash` and has **string** keys, so the gate
  never opens and `exp` and `nonce` go unchecked. It also pins `jwt ~> 2`,
  which moved the lock from jwt 3.2.0 to 2.10.3 for every consumer. Generic
  OIDC validates all of those claims and keeps Auth0 tenant-capable. Auth0 is
  a **broker**: one tenant can federate many upstream IdPs into a single
  issuer, so `OIDC_TRUST_EMAIL_FOR_LINKING` trusts *every* connection the
  tenant enables, including unverified database and social connections.
- **Entra ID**: uid is `tid+oid` by default. If you ever set
  `ignore_tid: true`, cross-tenant safety rests entirely on issuer scoping —
  see the security note on the `:entra` registry entry.
- **Google/GitHub**: issuerless (see above). Google's OAuth2 strategy does
  return an id_token, but the strategy does not surface a validated `iss`
  via `options[:issuer]`; it is treated as issuerless by design.

## Failure UX

User cancellation at the IdP (`access_denied`) redirects to
`/signin?auth_error=sso_cancelled` and renders calm copy; every other failure
uses `sso_failed`. New error codes must be added both to
`omniauth_failure_redirect` (`apps/web/auth/config/hooks/omniauth.rb`) and to
`authErrorMessages` in `src/apps/session/views/Login.vue` (unknown codes fall
back to the generic `sso_failed` message, so a frontend/backend version skew
degrades gracefully instead of rendering nothing).
