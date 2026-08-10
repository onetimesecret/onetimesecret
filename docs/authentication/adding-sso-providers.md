# Adding an SSO Provider

All SSO provider wiring is data in one place:
`lib/onetime/sso_provider_registry.rb` (`Onetime::SsoProviderRegistry::DEFINITIONS`).
Both consumers read it, so they cannot drift:

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

3. **Add one entry to `DEFINITIONS`** in
   `lib/onetime/sso_provider_registry.rb`. Copy an existing entry of the
   same shape (issuer-capable: copy `:entra` or `:oidc`; plain OAuth2: copy
   `:github`). Every field is documented in the file header. Keep the env
   prefix consistent (`FOO_CLIENT_ID`, `FOO_ROUTE_NAME`, `FOO_DISPLAY_NAME`,
   `FOO_TRUST_EMAIL_FOR_LINKING`) — the registry spec enforces this.

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

When a provider supports both modes (GitLab, Auth0, Okta), integrate it
through OIDC (`omniauth_openid_connect` with the provider's issuer) rather
than its bespoke OAuth2 strategy — it then inherits issuer scoping for free.

## Known provider quirks

- **Apple** (`omniauth-apple`): callback is a **POST** (`form_post` response
  mode) — verify the callback route and any CSRF/CSP assumptions against a
  POST callback; the email is only present on the **first** authorization;
  the user's name arrives in the request body, not the id_token. Apple is
  OIDC-based and issuer-capable (`https://appleid.apple.com`).
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
