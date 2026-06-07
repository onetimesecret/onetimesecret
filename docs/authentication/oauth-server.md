# OAuth2 / OIDC Identity Provider

**Status:** Active
**Authentication Mode:** Full (Rodauth)
**Issue:** [#3104](https://github.com/onetimesecret/onetimesecret/issues/3104)

---

## Overview

OneTimeSecret can act as an OAuth2 / OpenID Connect identity provider (OP). External relying parties (RPs) authenticate users against an OTS instance using the standard authorization-code + PKCE flow, OIDC discovery, and JWKS public-key publication. The implementation is built on [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth) 1.6.4.

This is the inverse role of the OmniAuth feature documented in [per-install-sso.md](per-install-sso.md): OmniAuth makes OTS a **service provider** (consumer) of external IdPs; this feature makes OTS act **as an IdP**. Both can be enabled simultaneously.

**Requirements:**
- `AUTHENTICATION_MODE=full`
- SQL database with migrations applied through `010_oauth_grants_pkce_check.rb`
- RSA private key in `OAUTH_JWT_RSA_PRIVATE_KEY`

## Enabling

```bash
export AUTH_OAUTH_ENABLED=true
```

`bin/generate_oauth_keys` prints a ready-to-paste `.env` snippet containing both the JWT signing key (`OAUTH_JWT_RSA_PRIVATE_KEY`) and a development SP client secret. Append the output directly:

```bash
bin/generate_oauth_keys >> .env
```

The script's output is already in `VAR="..."` form, so `eval "$(bin/generate_oauth_keys)"` also works for one-shot shells that don't read `.env`.

Run migrations (rerun is idempotent):

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

### Issuer (`OAUTH_ISSUER`)

The issuer URL is published in discovery metadata and embedded as the `iss` claim in every ID token. The resolution order is:

1. `OAUTH_ISSUER` if set
2. Otherwise `base_url + Auth::Application.uri_prefix` (e.g. `http://localhost:3000/auth`)

See `apps/web/auth/config/features/oauth.rb:75-78`.

Set `OAUTH_ISSUER` explicitly for any production deployment where `base_url` is computed from a request header (clients reject ID tokens whose `iss` does not match the issuer they discovered). **Rotating the issuer after deploy invalidates every live ID token** — clients will reject them as `iss` mismatches.

## Endpoints

All endpoints are mounted under the auth app's prefix (`/auth`).

| Method   | Path                                       | Purpose                              |
|----------|--------------------------------------------|--------------------------------------|
| GET      | `/auth/.well-known/openid-configuration`   | OIDC discovery document              |
| GET      | `/auth/.well-known/oauth-authorization-server` | RFC 8414 metadata                |
| GET/POST | `/auth/authorize`                          | Authorization request (browser)      |
| POST     | `/auth/token`                              | Token exchange / refresh             |
| GET/POST | `/auth/userinfo`                           | Bearer-protected claim retrieval     |
| GET      | `/auth/jwks`                               | Public-key JWKS document             |
| POST     | `/auth/revoke`                             | RFC 7009 token revocation            |

`/introspect` (RFC 7662) is **not** mounted in v1 — the `:oauth_token_introspection` feature is not enabled (see `apps/web/auth/config/features/oauth.rb:49-52`). Discovery does not advertise an `introspection_endpoint`.

Quick verification:

```bash
curl -s http://localhost:3000/auth/.well-known/openid-configuration | jq
curl -s http://localhost:3000/auth/jwks | jq
```

## Registering an OAuth Client

Clients are rows in the `oauth_applications` table (see `apps/web/auth/migrations/008_oauth_applications.rb`). v1 does not ship a dynamic client registration endpoint — operators seed rows manually or via tooling.

**Required columns** when seeding:

| Column           | Notes                                                                 |
|------------------|-----------------------------------------------------------------------|
| `name`           | Human-readable label                                                  |
| `redirect_uri`   | Exact match required at `/authorize`. Multiple values: newline-separated |
| `client_id`      | Unique; referenced in client config                                   |
| `client_secret`  | Stored as bcrypt hash — see hashing note below                        |
| `scopes`         | Space-separated, e.g. `openid email profile`                          |
| `grant_types`    | Typically `authorization_code refresh_token`                          |
| `response_types` | Typically `code`                                                      |

**Client secret hashing.** The `client_secret` column holds a bcrypt hash, not plaintext. v1 ships no admin UI — callers are responsible for hashing before insert. The dev seeder uses `BCrypt::Password.create(secret)` (`apps/web/auth/initializers/seed_dev_oauth_client.rb:87`); manual SQL inserts must do the same.

**Allowed scopes** are gated by `oauth_application_scopes` (`apps/web/auth/config/features/oauth.rb:148`), currently `openid profile email`. Requesting any other scope at `/authorize` is rejected.

**Token-endpoint auth methods.** `/token` accepts `client_secret_basic` (HTTP Basic) and `client_secret_post` (form body) — set via `oauth_token_endpoint_auth_methods_supported` (`apps/web/auth/config/features/oauth.rb:158`). `client_secret_jwt` and `private_key_jwt` are not supported in v1.

**Example insert** (operator hashes the secret out-of-band):

```sql
INSERT INTO oauth_applications (
  name, redirect_uri, client_id, client_secret, scopes,
  subject_type, id_token_signed_response_alg,
  token_endpoint_auth_method, grant_types, response_types,
  created_at
) VALUES (
  'Example RP',
  'https://app.example.com/oidc/callback',
  'example-client',
  '$2a$12$...bcrypt-hash-of-plaintext-secret...',
  'openid email profile',
  'public',
  'RS256',
  'client_secret_basic',
  'authorization_code refresh_token',
  'code',
  CURRENT_TIMESTAMP
);
```

## Supported Grants and Response Types

| Capability                | Status                                                              |
|---------------------------|---------------------------------------------------------------------|
| `authorization_code`      | Enabled, **PKCE required**                                          |
| `refresh_token`           | Enabled (rotation policy: new refresh token issued on each use)     |
| `client_credentials`      | Disabled                                                            |
| `password`                | Disabled                                                            |
| `device_code`             | Disabled                                                            |
| `urn:ietf:params:oauth:grant-type:jwt-bearer` | Disabled                                       |
| Response type `code`      | Accepted                                                            |
| Response types `token`, `id_token`, `code id_token`, hybrid, `none` | **Rejected at `/authorize`** |

Enabling `:oidc` transitively pulls in `:oauth_implicit_grant`. The DSL setter `oauth_response_types_supported %w[code]` only narrows the discovery doc — it does not gate request validation. v1 overrides `check_valid_response_type?` (`apps/web/auth/config/features/oauth.rb:178-182`) so non-`code` response types are actively rejected at `/authorize` rather than silently accepted.

## PKCE Policy

Two layers enforce PKCE `S256`-only:

1. **Gem behavior at `/authorize`**: once `:oauth_pkce` is enabled, `oauth_require_pkce` defaults to `true` and `oauth_pkce_challenge_method` defaults to `S256`. The gem rejects `plain` at `/authorize`. (See exploration notes in `apps/web/auth/docs/rodauth-oauth-exploration.md`.)
2. **DB CHECK constraint** (`apps/web/auth/migrations/010_oauth_grants_pkce_check.rb`, shipped in [#3232](https://github.com/onetimesecret/onetimesecret/issues/3232)): rejects any `oauth_grants` insert with `code_challenge_method='plain'`. NULL is permitted so non-PKCE flows can still insert.

The DB constraint exists because the gem's `/token` redemption path (`oauth_pkce.rb:75-77`) accepted `plain` if a row with that method ever appeared. The constraint makes the data layer the source of truth.

## Claim Shape

Claims emitted in ID tokens and from `/userinfo` (see `apps/web/auth/config/hooks/oauth.rb`):

| Claim                | Source                                                              |
|----------------------|---------------------------------------------------------------------|
| `sub`                | `accounts.id` (gem default)                                         |
| `email`              | `accounts.email`                                                    |
| `email_verified`     | `accounts.status_id == account_open_status_value` (boolean)         |
| `preferred_username` | `Customer#custid` via `external_id` lookup; falls back to email     |
| `name`               | Same as `preferred_username`                                        |
| `updated_at`         | `accounts.updated_at` as NumericDate (seconds since epoch)          |
| `iss`                | `authorization_server_url` (resolved per the issuer rules above)    |
| `aud`, `iat`, `exp`, `nonce`, `acr`, `at_hash`, `c_hash` | Gem defaults              |
| `auth_time`          | **Omitted** when the account has no active session — see below      |

**`auth_time` omission (sessionless accounts).** The gem's `id_token_claims` unconditionally writes `auth_time = get_oidc_account_last_login_at(account_id).to_i`. When the account has no row in `active_sessions`, the helper returns `nil` and `nil.to_i == 0`, which the gem then emits as `auth_time: 0` (interpreted as 1970-01-01T00:00:00Z by RP clients). OIDC Core 1.0 §2 requires `auth_time` to be the actual authentication moment, so the v1 override drops the claim when it would serialize to 0 (`apps/web/auth/config/features/oauth.rb:227-233`, fix in commit `9e83377f2`).

## JWT Validation Notes

**ID token `iss` claim.** Must match the discovery `issuer` value. If you set `OAUTH_ISSUER`, RPs must discover from that exact URL (or be configured with that issuer string) — token validation will fail otherwise.

**`/userinfo` does not enforce JWT `exp` at the gate.** rodauth-oauth 1.6.4 (`oauth_jwt_base.rb:217-285`, json-jwt branch) wraps claim validation in an AND-chain: a JWT is rejected only when **every** claim check fails simultaneously. A bearer token with a valid `iss`/`aud`/`iat`/`jti` and an expired `exp` passes the JWT-level gate.

In practice `/userinfo` is protected by the **DB-row gate** (`oauth_base.rb:596-602`): `valid_oauth_grant_ds` filters `oauth_grants.expires_in >= CURRENT_TIMESTAMP`, and `/token` writes `now + oauth_access_token_expires_in` (3600s) into that column on every exchange. The row's expiry is the effective expiry for issued access tokens; an attacker cannot forge a row.

The override is **not** applied here — patching the gem's predicate safely requires re-implementing all six claim checks and tracking upstream on every bump. The correct fix belongs upstream. Regression coverage pins both halves:

- `apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb:312` — documents the gem's current behavior (test will fail with 401 once the gem is patched).
- `apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb:355` — pins the DB-row gate.

See `apps/web/auth/config/features/oauth.rb:239-281` for the full analysis ([#3231](https://github.com/onetimesecret/onetimesecret/issues/3231)).

## Token Lifetimes

| Setting                          | Value         | Source                                  |
|----------------------------------|---------------|-----------------------------------------|
| Authorization code TTL           | 5 minutes     | `oauth_grant_expires_in 300`            |
| Access token TTL                 | 60 minutes    | `oauth_access_token_expires_in 3600`    |
| Refresh token TTL                | 30 days       | `oauth_refresh_token_expires_in`        |
| Refresh token policy             | Rotation      | new refresh token issued per exchange   |

(`apps/web/auth/config/features/oauth.rb:137-145`.)

## Operational Notes

### Key Rotation

`OAUTH_JWT_RSA_PRIVATE_KEY` is the only signing key in v1 — there is no secondary key for staged rotation. Replacing it requires:

1. Stop the application.
2. Update the env var with the new PEM.
3. Restart.

Every ID token and JWT access token issued under the previous key becomes invalid (signature verification fails against the new JWKS). Plan rotation alongside a session-flush window. Generating a new keypair in development:

```bash
bin/generate_oauth_keys
```

The env var accepts a single-line PEM with literal `\n` escapes (`bin/generate_oauth_keys` emits this form so the value fits in `.env`).

### URI Scheme Restriction

```bash
# Production: restrict redirect URIs to https
export OAUTH_VALID_URI_SCHEMES=https
```

Default is `"http https"` so localhost callbacks work in development. Tighten in production to block plaintext callbacks from registered clients.

### Revoking a Client

Delete or null its row in `oauth_applications`. There is no admin UI in v1; operate against the database directly:

```sql
-- Permanently remove a client (cascades to its grants)
DELETE FROM oauth_applications WHERE client_id = 'example-client';

-- Revoke all live grants for a client without deleting the registration
UPDATE oauth_grants SET revoked_at = CURRENT_TIMESTAMP
WHERE oauth_application_id = (
  SELECT id FROM oauth_applications WHERE client_id = 'example-client'
);
```

### CSRF Bypass for Programmatic Endpoints

The endpoints in `OAUTH_NO_CSRF_PATHS` (`/token`, `/userinfo`, `/revoke`, `/jwks`) bypass rodauth's CSRF check because they are reached programmatically without a browser session. PKCE, client authentication on `/token`, and Bearer authentication on `/userinfo` provide protocol-level equivalents. `/authorize` is **not** in this set — it is browser-driven and keeps CSRF protection.

See `apps/web/auth/config/features/oauth.rb:200-209` for the override; the prefix-mismatch reason this override exists is documented in [rodauth-prefix-mismatch.md](../../apps/web/auth/docs/rodauth-prefix-mismatch.md).

## Local Development

For the loopback flow that lets OTS act as both SP and IdP in a single process (no external IdP needed), see [oauth-local-development.md](oauth-local-development.md).

## Codebase Reference

| File                                                              | Role                                       |
|-------------------------------------------------------------------|--------------------------------------------|
| `apps/web/auth/config/features/oauth.rb`                          | IdP feature, prefix overrides, CSRF + response-type gates |
| `apps/web/auth/config/hooks/oauth.rb`                             | Claim mapping (`get_oidc_param`), `OAUTH_EXEMPT_PATHS` |
| `apps/web/auth/config/json_mode.rb`                               | Single owner of `only_json?` (composes OAuth + OmniAuth exemptions) |
| `apps/web/auth/initializers/seed_dev_oauth_client.rb`             | Dev SP client seeder (gated to dev/test)   |
| `apps/web/auth/migrations/008_oauth_applications.rb`              | Client registry table                      |
| `apps/web/auth/migrations/009_oauth_grants.rb`                    | Auth-code + token storage                  |
| `apps/web/auth/migrations/010_oauth_grants_pkce_check.rb`         | PKCE `plain` rejection (CHECK constraint)  |
| `bin/generate_oauth_keys`                                         | RSA keypair + dev SP secret generator      |
| `apps/web/auth/docs/rodauth-oauth-exploration.md`                 | Gem reconnaissance, feature inventory      |
| `apps/web/auth/docs/rodauth-prefix-mismatch.md`                   | URLMap prefix mismatch ADR                 |
| `apps/web/auth/docs/auth-config-one-shot.md`                      | `@configured` constraint ADR               |

## See Also

- [Local Development Loopback](oauth-local-development.md)
- [OmniAuth (SP role) Configuration](per-install-sso.md)
- [Switching to Full Auth Mode](switching-to-full-mode.md)
- [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth)
