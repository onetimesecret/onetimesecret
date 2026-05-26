# OAuth/OIDC Local Development

**Status:** Active
**Audience:** OTS contributors working on authentication code
**Issue:** [#3104](https://github.com/onetimesecret/onetimesecret/issues/3104)

---

## Overview

The `:local` SP provider routes OTS's OmniAuth (service-provider) layer back at the same instance's OAuth/OIDC IdP. The result: contributors can exercise the full SP → IdP → SP loop in a single process without standing up Zitadel, Keycloak, or another external IdP.

Use it when:
- Working on `apps/web/auth/config/features/oauth.rb` or `hooks/oauth.rb` claim mapping
- Reproducing an SP-side bug without IdP-specific setup
- Writing integration specs that need a real HTTP loop, not an OmniAuth mock

For the IdP itself (endpoints, claims, registration), see [oauth-server.md](oauth-server.md).

## One-Time Setup

Generate the RSA signing key and dev SP secret:

```bash
bin/generate_oauth_keys >> .env
```

This appends two variables:

- `OAUTH_JWT_RSA_PRIVATE_KEY` — RSA 2048 PEM used by the IdP to sign ID tokens and JWT access tokens. Single line with literal `\n` escapes so it fits in `.env`.
- `OAUTH_SP_DEV_CLIENT_SECRET` — plaintext secret for the seeded `onetimesecret-sp-dev` client. The DB stores its bcrypt hash; the env var lets the SP-side OmniAuth provider authenticate at `/token`.

Run migrations:

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

## Required Environment

```bash
export AUTHENTICATION_MODE=full
export AUTH_OAUTH_ENABLED=true
export AUTH_SSO_ENABLED=true              # SP-side OmniAuth must also be on
export OAUTH_JWT_RSA_PRIVATE_KEY=...      # from bin/generate_oauth_keys
export OAUTH_SP_DEV_CLIENT_SECRET=...     # from bin/generate_oauth_keys
```

Optional overrides (defaults shown):

| Variable                       | Default                                                | Purpose                                |
|--------------------------------|--------------------------------------------------------|----------------------------------------|
| `OAUTH_ISSUER`                 | `http://localhost:3000/auth`                           | IdP issuer URL                         |
| `OAUTH_SP_DEV_CLIENT_ID`       | `onetimesecret-sp-dev`                                 | Client identifier                      |
| `OAUTH_SP_DEV_ROUTE_NAME`      | `local`                                                | URL segment for SP routes              |
| `OAUTH_SP_DEV_DISPLAY_NAME`    | `Local IdP`                                            | Button label on signin page            |
| `OAUTH_SP_DEV_ISSUER`          | falls back to `OAUTH_ISSUER`                           | SP-side issuer override                |
| `OAUTH_SP_DEV_REDIRECT_URI`    | `http://localhost:3000/auth/sso/local/callback`        | SP callback URL                        |

## The Seeded Dev Client

`apps/web/auth/initializers/seed_dev_oauth_client.rb` inserts an `oauth_applications` row on every boot. It is:

- **Idempotent.** A `where(client_id: ...).any?` check skips insert when the row exists. A `Sequel::UniqueConstraintViolation` rescue covers the concurrent-boot race (the unique index on `client_id` is the actual safety net).
- **Gated to dev/test.** `should_skip?` returns true unless `Onetime.development? || Onetime.testing?`. Production never seeds this row.
- **Inert without the secret.** If `OAUTH_SP_DEV_CLIENT_SECRET` is unset, the initializer logs and exits without inserting.

The seeded row:

| Column                          | Value                                             |
|---------------------------------|---------------------------------------------------|
| `client_id`                     | `onetimesecret-sp-dev`                            |
| `client_secret`                 | bcrypt hash of `OAUTH_SP_DEV_CLIENT_SECRET`       |
| `redirect_uri`                  | `OAUTH_SP_DEV_REDIRECT_URI`                       |
| `scopes`                        | `openid email profile`                            |
| `grant_types`                   | `authorization_code refresh_token`                |
| `response_types`                | `code`                                            |
| `token_endpoint_auth_method`    | `client_secret_basic`                             |

## The Loopback Flow

The SP-side wiring lives in `Auth::Config::Features::OmniAuth.configure_local_idp_provider` (`apps/web/auth/config/features/omniauth.rb:180-215`). It registers an `:openid_connect` OmniAuth strategy named `:local` that points back at this instance's `/auth` mount.

End-to-end flow:

```
User clicks "Local IdP" button on /signin
    │
    ▼
POST /auth/sso/local                        (SP-side OmniAuth: initiate)
    │
    ▼
302 → /auth/authorize?response_type=code&...   (IdP)
    │
    ▼
User consents at IdP
    │
    ▼
302 → /auth/sso/local/callback?code=...     (SP callback)
    │
    ▼
POST /auth/token (Basic auth: client_id/secret)   (server-to-server)
    │
    ▼
ID token + access token returned to SP
    │
    ▼
GET /auth/userinfo (Bearer)                     (optional claim fetch)
    │
    ▼
SP creates/links account, syncs session, redirects to dashboard
```

The gate (`return unless Onetime.auth_config.oauth_enabled?`) skips registration when the IdP is off — the provider would have nowhere to talk to.

## Running the Auth Spec Suite

The `Auth::Config` class is a **one-shot**: its `@configured` guard prevents re-configuration within a process. The first call to `Auth::Config.configure` bakes the feature flags (`AUTH_OAUTH_ENABLED`, `AUTH_SSO_ENABLED`, etc.) into the class for the rest of the process. See [auth-config-one-shot.md](../../apps/web/auth/docs/auth-config-one-shot.md) for the full analysis.

Practical consequences:

1. **Set feature flags before requiring specs.** `apps/web/auth/spec/spec_helper.rb:114-115` reloads `Onetime.auth_config` and then `require`s the auth `application.rb`, which triggers `Auth::Config.configure`. Any env var read at configure time becomes immutable in-process.

2. **The OAuth IdP specs pre-boot the env.** `oauth_idp_*_spec.rb` files set `AUTH_OAUTH_ENABLED`, `OAUTH_ISSUER`, `OAUTH_JWT_RSA_PRIVATE_KEY`, and `OAUTH_SP_DEV_CLIENT_SECRET` at the **top of the file** (before any `require`):

   ```ruby
   ENV['AUTH_OAUTH_ENABLED']         = 'true'
   ENV['OAUTH_ISSUER']               ||= 'http://localhost:3000/auth'
   ENV['OAUTH_JWT_RSA_PRIVATE_KEY']  ||= OpenSSL::PKey::RSA.new(2048).to_pem
   ENV['OAUTH_SP_DEV_CLIENT_SECRET'] ||= "spec-sp-secret-#{SecureRandom.hex(12)}"

   require_relative '../spec_helper'
   ```

3. **First-loaded spec wins.** If you run the full suite, whichever spec triggers `Auth::Config.configure` first selects the configuration for every subsequent spec. The fix landed in commits `5541ae845` (capture-and-restore ENV in `before(:all)/after(:all)` to bound contamination), `73b9b3ff3` and `88d675bb5` (reload `auth_config` before loading `application.rb` in spec_helper).

Run the IdP specs:

```bash
# Single file
bundle exec rspec apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb

# All IdP integration specs
bundle exec rspec apps/web/auth/spec/integration/oauth_idp_*_spec.rb

# Full auth suite
bundle exec rspec apps/web/auth/spec/
```

## Common Pitfalls

**`OAUTH_JWT_RSA_PRIVATE_KEY must be set` on boot.** Either the env var is missing or it was rotated between processes. Regenerate with `bin/generate_oauth_keys >> .env` and remove the previous `OAUTH_JWT_RSA_PRIVATE_KEY=...` line from `.env`. Rotation invalidates every live ID/access token.

**Spec sees "OAuth IdP feature is not enabled" at boot.** An earlier spec triggered `Auth::Config.configure` without `AUTH_OAUTH_ENABLED=true`. Run the OAuth spec file in isolation, or ensure your spec pre-boots the env at file load (the `oauth_idp_*_spec.rb` files do this).

**Forgetting `AUTH_SSO_ENABLED` for the local provider.** The IdP can run without SSO, but the `:local` SP provider needs OmniAuth enabled to register. Set both.

**Integration spec leaves env vars set.** Use `before(:all)/after(:all)` to capture-and-restore `ENV['AUTH_OAUTH_ENABLED']` and friends. A leak across files only matters if a later spec expects the var unset — but it happens.

**Discovery doc URLs missing `/auth`.** Symptom of the rodauth prefix mismatch; the v1 patches in `apps/web/auth/config/features/oauth.rb` rewrite endpoint URLs after super. If you add a new metadata field that contains a URL, extend the rewrite list in `prefix_oauth_endpoint_urls!`. See [rodauth-prefix-mismatch.md](../../apps/web/auth/docs/rodauth-prefix-mismatch.md).

## Registering a Test Client

For tests that need a second client (e.g. RP isolation, scope variations), insert another `oauth_applications` row. The dev seeder is a useful template:

```ruby
require 'bcrypt'
require 'auth/database'

db = Auth::Database.connection
db[:oauth_applications].insert(
  account_id: nil,
  name: 'Test RP — scope isolation',
  description: 'Used by spec/integration/...',
  redirect_uri: 'http://localhost:3000/test/callback',
  client_id: 'test-rp-scopes',
  client_secret: BCrypt::Password.create('test-secret'),
  scopes: 'openid email',                       # narrower than dev SP
  subject_type: 'public',
  id_token_signed_response_alg: 'RS256',
  token_endpoint_auth_method: 'client_secret_basic',
  grant_types: 'authorization_code',
  response_types: 'code',
)
```

Wrap in a fixture or `before(:all)` for repeatability and remember to clean up in `after(:all)` if your spec mutates state.

## Codebase Reference

| File                                                              | Role                                       |
|-------------------------------------------------------------------|--------------------------------------------|
| `apps/web/auth/config/features/omniauth.rb`                       | `configure_local_idp_provider` (~163-215)  |
| `apps/web/auth/initializers/seed_dev_oauth_client.rb`             | Dev client seeder                          |
| `bin/generate_oauth_keys`                                         | Key + secret generator                     |
| `apps/web/auth/spec/integration/oauth_idp_endpoints_spec.rb`      | Per-endpoint error responses               |
| `apps/web/auth/spec/integration/oauth_idp_protocol_spec.rb`       | End-to-end SP → IdP loop                   |
| `apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb`      | Token lifecycle + claim correctness        |
| `apps/web/auth/spec/integration/oauth_idp_security_spec.rb`       | Security invariants                        |
| `apps/web/auth/docs/auth-config-one-shot.md`                      | `@configured` constraint ADR               |
| `apps/web/auth/docs/rodauth-prefix-mismatch.md`                   | URLMap prefix mismatch ADR                 |

## See Also

- [OAuth/OIDC Identity Provider](oauth-server.md)
- [OmniAuth Testing Guide](omniauth-testing.md)
- [Per-Install SSO](per-install-sso.md)
