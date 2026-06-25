# rodauth-oauth — exploration notes (task 1, issue #3104)

Reconnaissance only. No production code written. All claims below are
sourced from the installed gem at:
`/Users/d/.rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rodauth-oauth-1.6.4`

## Version pinned

```ruby
gem 'rodauth-oauth', '~> 1.6'
```

Resolved to `1.6.4` (released 2025-12-11). Reasons:

- Gem's own dep is `rodauth ~> 2.28`; project ships `rodauth 2.42.0` — compatible.
- Ruby `>= 2.5`; project ships Ruby `3.4.7+` — compatible.
- 1.x is the OIDC-certified line (Basic / Implicit / Hybrid / Config / Dynamic / Form Post / 3rd-Party-Init / Session-Mgmt / RP-Initiated-Logout / Front-Channel / Back-Channel OP profiles).
- `bundle install` succeeded with no resolver conflicts.

`bundle show rodauth-oauth` → installed path above.

Gemfile location: project root `Gemfile` (single Gemfile; `apps/web/auth/`
does NOT have its own — auth runs out of the root bundle).

Source: `rodauth-oauth-1.6.4/rodauth-oauth.gemspec` (rodauth `~> 2.28`),
`README.md` line 306 (Ruby 2.5+), rubygems versions page.

## Feature flags relevant to our scope

Symbols passed to `enable :foo`:

- `:oauth_authorization_code_grant` — auth-code flow, `/authorize` and `/token` endpoints.
  - `depends :oauth_authorize_base`.
  - File: `lib/rodauth/features/oauth_authorization_code_grant.rb`.
- `:oauth_pkce` — separate flag. `depends :oauth_authorization_code_grant`.
  - **`oauth_require_pkce` defaults to `true`** in this gem (i.e. once you enable PKCE, it's required, not optional). Override with `oauth_require_pkce false`.
  - Default challenge method `S256`. Override `oauth_pkce_challenge_method "plain"` if needed.
  - File: `lib/rodauth/features/oauth_pkce.rb` (lines 9–17).
- `:oidc` — OpenID Connect Core. Enables `/.well-known/openid-configuration` route loader and `/userinfo` endpoint.
  - **`depends :active_sessions, :oauth_jwt, :oauth_jwt_jwks, :oauth_authorization_code_grant, :oauth_implicit_grant`** — you cannot enable `:oidc` without also pulling in `:oauth_implicit_grant`. The implicit flow tables/columns will exist; the only way to actually keep implicit + hybrid response types from being accepted at `/authorize` is to **override the `check_valid_response_type?` predicate**. The `oauth_response_types_supported` DSL setter only affects discovery metadata — request validation in `oauth_implicit_grant.rb:89-93` and `oidc.rb:695-703` hardcodes acceptance of `token`, `id_token`, `code id_token`, `code token`, `id_token token`, `code id_token token`, `none` regardless of that setting. See `apps/web/auth/config/features/oauth.rb` for the override.
  - File: `lib/rodauth/features/oidc.rb` line 71.
- `:oauth_jwt` — JWT access tokens + issuance config. `depends :oauth_jwt_base, :oauth_jwt_jwks`. Pulled in transitively by `:oidc`.
- `:oauth_jwt_jwks` — exposes `/jwks` route. `depends :oauth_jwt_base`. Pulled in transitively by `:oidc`.
- `:oauth_dynamic_client_registration` — RFC 7591 + 7592. `/register` route.
- `:oidc_dynamic_client_registration` — OIDC variant. We probably skip this for v1.
- Refresh tokens: **no separate feature flag**. Refresh tokens are handled in `oauth_base` and stored on the same `oauth_grants` row. Configured via `oauth_refresh_token_expires_in` (default 1 year) and `oauth_refresh_token_protection_policy` (default `"rotation"` — alternatives `"none"`, `"sender_constrained"`).

Other flags exist (`oauth_implicit_grant`, `oauth_client_credentials_grant`, `oauth_device_code_grant`, `oauth_token_revocation`, `oauth_token_introspection`, `oauth_pushed_authorization_request`, `oauth_dpop`, `oauth_tls_client_auth`, `oauth_jwt_secured_authorization_request`, `oauth_jwt_secured_authorization_response_mode`, `oauth_resource_indicators`, `oauth_assertion_base`, `oauth_saml_bearer_grant`, `oauth_jwt_bearer_grant`, `oidc_self_issued`, `oidc_session_management`, `oidc_rp_initiated_logout`, `oidc_frontchannel_logout`, `oidc_backchannel_logout`). Out of scope for v1.

Full list: `ls lib/rodauth/features/` in the gem.

## Default table names (for migrations task)

The gem uses **two production tables** for our scope (plus one optional
table for PAR if we ever enable it, plus one for DPoP, plus one for SAML
bearer — all unused for v1 scope):

- `oauth_applications` — client registry. All OIDC/PKCE/dynamic-reg columns live here as nullable.
- `oauth_grants` — **single table** for auth codes, access tokens, refresh tokens, PKCE state, OIDC nonce/acr/claims. A row's lifecycle: `code` populated at `/authorize`, then `code` nulled + `token`/`refresh_token` populated at `/token`.

NOT used in v1 scope:

- `oauth_pushed_requests` — only if `:oauth_pushed_authorization_request`.
- `oauth_saml_settings` — only if `:oauth_saml_bearer_grant`.
- `oauth_dpop_proofs` — only if `:oauth_dpop`.

Source for full column lists:

- Authoritative AR template: `lib/generators/rodauth/oauth/templates/db/migrate/create_rodauth_oauth.rb` (in the installed gem). Per-column comments mark which feature each column belongs to — perfect for trimming when writing the Sequel version.
- Sequel reference (gem's own tests use these): `https://github.com/HoneyryderChuck/rodauth-oauth/tree/master/test/migrate` — `003_oauth_applications.rb` and `004_oauth_grants.rb`.

### oauth_applications minimum columns (v1 scope)

`id`, `account_id` (FK → accounts, nullable for system-owned clients),
`name`, `description`, `homepage_url`, `redirect_uri` (required),
`client_id` (unique), `client_secret` (unique, hashed by default),
`scopes` (required), `created_at`.

For OIDC: `subject_type`, `id_token_signed_response_alg`,
`userinfo_signed_response_alg`. (And the encrypted variants if we want JWE
support — we don't for v1.)

For dynamic client registration: `token_endpoint_auth_method`,
`grant_types`, `response_types`, `client_uri`, `logo_uri`, `tos_uri`,
`policy_uri`, `jwks_uri`, `jwks`, `contacts`, `software_id`,
`software_version`, `registration_access_token`. Add these as nullable
even if we ship manual seed-based registration — the gem reads them.

For RP-initiated logout (if/when enabled): `post_logout_redirect_uris`.

### oauth_grants minimum columns (v1 scope)

`id`, `account_id` (FK → accounts), `oauth_application_id`
(FK → oauth_applications), `type` (nullable; populated for some flows),
`code` (nullable; auth-code), unique index on
`(oauth_application_id, code)`, `token` (unique), `refresh_token`
(unique), `expires_in` (datetime, NOT NULL), `redirect_uri`, `revoked_at`,
`scopes` (NOT NULL), `created_at`, `access_type` (default `"offline"`).

PKCE columns: `code_challenge`, `code_challenge_method`.

OIDC columns: `nonce`, `acr`, `claims_locales`, `claims`.

Note on hashing: by default the gem stores token/refresh_token **hashes**
in the same columns it reads tokens from (column-name level config:
`oauth_grants_token_hash_column :token`, default). If we want plaintext
storage we set those to `nil`. Default = hashed via bcrypt. Source: README
"Token / Secrets Hashing" + `oauth_base.rb` lines 57–58, 78.

## Built-in routes

The gem registers routes through `auth_server_route(:name)` (a rodauth-oauth
extension to rodauth's routing). For these to mount, `r.rodauth` in the
Roda tree is sufficient — they're auto-mounted at rodauth's prefix.

Route → feature → handler:

- `POST /token` — `:oauth_base` (via `oauth_authorization_code_grant`). Auto-mounted. `oauth_base.rb:128`.
- `GET/POST /authorize` — `:oauth_authorize_base`. Auto-mounted. `oauth_authorize_base.rb:41`.
- `GET /jwks` — `:oauth_jwt_jwks`. Auto-mounted. `oauth_jwt_jwks.rb:12`.
- `GET/POST /userinfo` — `:oidc`. Auto-mounted. `oidc.rb:119`.
- `POST /revoke` — `:oauth_token_revocation`. Auto-mounted when feature enabled.
- `POST /introspect` — `:oauth_token_introspection`. Same.
- `POST /register` — `:oauth_dynamic_client_registration`. Same.

**Discovery routes are NOT auto-mounted.** They are exposed via helper
methods you call from your Roda routing block:

- `GET /.well-known/openid-configuration` — call `rodauth.load_openid_configuration_route` inside `route do |r|`. Source: `oidc.rb:188`.
- `GET /.well-known/oauth-authorization-server` — call `rodauth.load_oauth_server_metadata_route` inside `route do |r|`. The optional positional argument is a *path suffix* appended to the auth base URL (oauth_base.rb:746-748), NOT a full issuer URI. Source: `oauth_base.rb:150`.
- `GET /.well-known/webfinger` (optional, OIDC SelfIssued) — `rodauth.load_webfinger_route`. Source: `oidc.rb:200`.

Confirmed by README of MIGRATION-GUIDE-v1.md line 236:
`+ rodauth.load_openid_configuration_route`.

Default endpoint paths are configurable via
`token_path "/oauth/token"` etc. — see `auth_value_method` declarations in
`oauth_base.rb`.

## Key DSL/config methods

Inside `plugin :rodauth do enable :oauth_…; … end`:

Tables:

- `oauth_applications_table :foo` (default `:oauth_applications`)
- `oauth_grants_table :foo` (default `:oauth_grants`)

Column renames follow the pattern
`oauth_grants_<column>_column :different_name` and
`oauth_applications_<column>_column :different_name`.

TTLs / expiry:

- `oauth_grant_expires_in 300` (auth code, default 5 min)
- `oauth_access_token_expires_in 3600` (default 60 min)
- `oauth_refresh_token_expires_in 60 * 60 * 24 * 360` (default ~1 year)
- `oauth_refresh_token_protection_policy "rotation"` (default; alternatives `none`, `sender_constrained`)

Scopes / metadata:

- `oauth_application_scopes %w[openid profile email]`
- `oauth_valid_uri_schemes %w[https]`
- `oauth_token_endpoint_auth_methods_supported %w[client_secret_basic client_secret_post]`
- `oauth_grant_types_supported %w[refresh_token]`

JWT / OIDC signing (in `oauth_jwt` / `oauth_jwt_base`):

- `oauth_jwt_keys({ "RS256" => private_key })` — hash keyed by alg.
- `oauth_jwt_public_keys({ "RS256" => public_key })` — exposed via JWKS.
- `oauth_jwt_jwe_keys`, `oauth_jwt_jwe_public_keys` — for encrypted ID tokens (not needed v1).
- `oauth_jwt_issuer "https://idp.example.com"` — default derives from `authorization_server_url`. Override to pin.
- `oauth_jwt_audience` — defaults to client_id of token recipient when acting as authorization server.
- `oauth_jwt_subject_type "public"` — or `"pairwise"`; `oauth_jwt_subject_secret` salts pairwise.

Token hashing:

- `oauth_grants_token_hash_column nil` to store plaintext (default `:token` → hashed).
- `oauth_grants_refresh_token_hash_column nil` to store plaintext (default `:refresh_token` → hashed).
- `oauth_applications_client_secret_hash_column nil` to store plaintext client secrets.
- `secret_matches? { |app, secret| … }` and `secret_hash { |secret| … }` to override the hashing algorithm (default bcrypt).

OIDC prompt-login cookie:

- `oauth_prompt_login_cookie_key "_rodauth_oauth_prompt_login"`
- `oauth_prompt_login_interval 5 * 60 * 60` (5h)

## Hooks

The pattern is `before_<route>_route` / `after_<route>_route` blocks inside
the rodauth plugin config, and a number of `auth_methods` you override
with `method_name do |args| … end`.

Route hooks (one pair per `auth_server_route(:name)`):

- `before_token_route` / `after_token_route` (token endpoint). `oauth_base.rb:130`.
- `before_authorize_route` / `after_authorize_route` (authorize endpoint). `oauth_authorize_base.rb:43`.
- `before_jwks_route` (`oauth_jwt_jwks.rb:13`).
- `before_revoke_route` (`oauth_token_revocation.rb:23`).
- `before_introspect_route` (`oauth_token_introspection.rb:19`).
- `before_register_route` (`oauth_dynamic_client_registration.rb:73`).
- `before_par_route` (`oauth_pushed_authorization_request.rb:25`).
- `before_oidc_logout_route` (`oidc_rp_initiated_logout.rb:19`).
- `before_device_route` / `before_device_authorization_route` (`oauth_device_code_grant.rb`).
- `before_authorize` (note: no `_route` — fires inside the authorize POST handler before granting). `oauth_authorize_base.rb:53`.

OIDC user-claim hooks (override in config block):

- `get_oidc_param { |account, param| account[:column_name] }` — required when you advertise OIDC scopes beyond `openid`. Without it, the gem `warn`s at runtime (`oidc.rb:634`). The proxy at `oidc.rb:651-659` inspects the block arity and dispatches to either `(account, param)` (2-arg, our usage) or `(account, param, claims_locales)` (3-arg, only when locales are configured). `account` is a Sequel row Hash (`oidc.rb:130`), so use Hash access (`account[:email]`), not `account.public_send`.
- `get_additional_param { |account, param| … }` — for custom (non-spec) claims.
- `fill_with_account_claims { |claims, account, scopes, claims_locales| … }` — override the whole claims-fill step.
- `id_token_claims(oauth_grant, signing_algorithm)` — the function that returns the claim hash before signing. Override to add/remove claims. `oidc.rb:559`.
- `get_oidc_account_last_login_at { |account| … }` — for the `auth_time` claim.
- `oidc_authorize_on_prompt_none? { |account| … }` — controls behaviour of `prompt=none`.
- `require_acr_value` / `require_acr_value_phr` / `require_acr_value_phrh` — ACR handling.
- `json_webfinger_payload` — only if exposing webfinger.

OAuth/JWT general hooks (`oauth_base`, `oauth_jwt_base`):

- `http_request` / `http_request_cache` — outbound HTTP client (used for dynamic client registration JWKS fetching). Override to inject our HTTP client.
- `secret_matches?` / `secret_hash` — bcrypt replacement.
- `jwks_set` — override the JWKS response.

Helper methods exposed to the Roda routing tree:

- `rodauth.require_authentication` (from rodauth core)
- `rodauth.require_oauth_authorization("scope.read", "scope.write")` — gates a route by token scope.
- `rodauth.current_oauth_account` — the account row associated with the bearer token.
- `rodauth.oauth_applications` — mounts the application management dashboard at `/oauth-applications` (HTML; optional).
- `rodauth.load_openid_configuration_route` — mount discovery (see above).
- `rodauth.load_oauth_server_metadata_route(issuer)` — mount RFC 8414 metadata.

Source for all of the above: corresponding files under
`lib/rodauth/features/` in the installed gem (paths given inline).

## Migration template / generator

Two starting points:

1. **Shipped with the gem (AR-flavoured but fully self-documenting per-feature)**:
   `lib/generators/rodauth/oauth/templates/db/migrate/create_rodauth_oauth.rb`
   — single file, 148 lines, defines all 5 tables (`oauth_applications`,
   `oauth_grants`, `oauth_pushed_requests`, `oauth_saml_settings`,
   `oauth_dpop_proofs`). Comments mark which feature each column belongs
   to, so trimming for our v1 scope is mechanical.

2. **Sequel reference (gem's test suite, our migration framework)**:
   `https://github.com/HoneyryderChuck/rodauth-oauth/tree/master/test/migrate`
   — `003_oauth_applications.rb` and `004_oauth_grants.rb` are the
   straight-Sequel versions to adapt. The repo on GitLab is the canonical
   source; the GitHub mirror at `HoneyryderChuck/rodauth-oauth` is fetched
   via `gh api` since GitLab's web doesn't render raw files cleanly.

We will write our own Sequel migrations (the AR template can't be used
directly — `apps/web/auth/migrations/` is a Sequel migration tree). Both
sources give us trustworthy column lists.

## Surprises vs. the explore-agent's prior summary

I do not have the explore agent's prior summary in front of me; I'll flag
what's likely to surprise based on common assumptions:

1. **No separate `oauth_authorization_codes` or `oauth_access_tokens`
   tables.** Everything (code, access token, refresh token, PKCE
   challenge, OIDC nonce/claims, revocation timestamp) lives on a single
   `oauth_grants` row. The row's lifecycle: `code` set at `/authorize`,
   `code` cleared and `token`/`refresh_token` set at `/token`,
   `revoked_at` set at revocation. This is a deliberate v1.x change
   documented in `MIGRATION-GUIDE-v1.md` lines 11–19.
2. **PKCE defaults to required, not optional.** `oauth_require_pkce true`
   is the default once `:oauth_pkce` is enabled. Set false explicitly if
   we want to support legacy clients without PKCE.
3. **OIDC forces enabling `:oauth_implicit_grant`** through its `depends`
   chain. We can't get OIDC without the implicit grant feature loaded.
   We can disable it at the application registration level (don't allow
   `token`/`id_token` response types in registered clients), but the code
   path is loaded.
4. **Discovery and authorization-server metadata routes are opt-in.** They
   are NOT auto-mounted; you call `load_openid_configuration_route` /
   `load_oauth_server_metadata_route(issuer)` from the Roda tree. JWKS
   route IS auto-mounted (via `oauth_jwt_jwks`).
5. **Tokens and client secrets are hashed by default (bcrypt).** The
   column you `SELECT` from is the same column that stores the hash. To
   disable, set `oauth_grants_token_hash_column nil` etc. — don't try to
   "find" a separate hash column.
6. **The shipped migration template is ActiveRecord**, not Sequel. We have
   a Sequel codebase, so we must hand-translate or copy from the
   `test/migrate` set in the gem's git repo.
7. **`oauth_grant_expires_in` is the AUTH CODE expiry**, not the access
   token expiry. Access token TTL is `oauth_access_token_expires_in`
   (default 60 min). Easy naming trap.
8. **The gem uses `auth_server_route(:name)` not Roda routing macros.**
   Hooks therefore follow rodauth's standard `before_<name>_route` /
   `after_<name>_route` naming, mounted automatically when the feature is
   `enable`d. We do not need to add `r.is "oauth"` blocks for the gem's
   own endpoints.

## Recommended next-task scope (task 2: migrations)

Given the table conventions above, our v1-scope migrations are two
Sequel files:

- `apps/web/auth/migrations/008_oauth_applications.rb`
  - Creates `oauth_applications` with: core columns (`account_id` FK,
    `name`, `description`, `homepage_url`, `redirect_uri`, `client_id`,
    `client_secret`, `scopes`, `created_at`), OIDC columns
    (`subject_type`, `id_token_signed_response_alg`,
    `userinfo_signed_response_alg`), and dynamic-client-registration
    columns even though v1 ships manual seeding
    (`token_endpoint_auth_method`, `grant_types`, `response_types`,
    `client_uri`, `logo_uri`, `tos_uri`, `policy_uri`, `jwks_uri`,
    `jwks`, `contacts`, `software_id`, `software_version`,
    `registration_access_token`).
  - Unique indexes on `client_id` and `client_secret`.

- `apps/web/auth/migrations/009_oauth_grants.rb`
  - Creates `oauth_grants` with: `id`, `account_id` FK, `oauth_application_id` FK,
    `type`, `code`, `token`, `refresh_token`, `expires_in`,
    `redirect_uri`, `revoked_at`, `scopes`, `created_at`,
    `access_type` (default `"offline"`).
  - PKCE columns: `code_challenge`, `code_challenge_method`.
  - OIDC columns: `nonce`, `acr`, `claims_locales`, `claims`.
  - Unique indexes: `(oauth_application_id, code)`, `token`,
    `refresh_token`.

We can defer `oauth_pushed_requests`, `oauth_saml_settings`,
`oauth_dpop_proofs`, and `oauth_device_code_grant` columns to later
migrations if/when we enable those features.

Reference column lists verbatim from
`lib/generators/rodauth/oauth/templates/db/migrate/create_rodauth_oauth.rb`
(installed gem) when writing the Sequel versions.
