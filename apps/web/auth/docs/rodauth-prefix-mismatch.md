# Rodauth Prefix Mismatch — Investigation & Resolution

Issue #3104 follow-up item #12.

> **Update — resolved in #3465.** The decoupling knob described under
> "When this might become a fix" now exists. The forked `rodauth-oauth`
> (consumed via the `Gemfile`) adds an `oauth_mount_prefix` setting, and the
> local override surface in `features/oauth.rb` has collapsed to that single
> setting plus a slim `OAUTH_ISSUER` shim and the load-bearing `/revoke` CSRF
> exemption. The rest of this document is the original investigation, retained
> for history, with two **Correction** notes inline: the claim that setting
> `rodauth.prefix '/auth'` "breaks every rodauth route" does **not** hold for
> rodauth 2.42.0 — route matching is segment-based and prefix-independent (see
> the empirical table under "Why we don't fix the root cause").

## Summary

The auth app is mounted under `/auth` via `Rack::URLMap`
(`lib/onetime/application/registry.rb:72`). Rodauth's own `prefix` setting
(`rodauth-2.42.0/lib/rodauth/features/base.rb:55`, default `''`) is never
set. This produces a recurring mismatch between two coexisting path
namespaces inside the rodauth instance:

| Source                  | Value for `/token` request   |
|-------------------------|------------------------------|
| `request.path`          | `/auth/token` (full URI)     |
| `request.path_info`     | `/token` (URLMap-stripped)   |
| `r.remaining_path`      | `/token` (Roda routing)      |
| `token_path` (rodauth)  | `/token` (prefix + route)    |
| `*_url` methods         | `base_url + /token`          |

`request.is` / `r.on` match against `remaining_path`, while the gem's CSRF
and metadata code paths inspect `request.path`.

> **Correction (#3465).** An earlier draft claimed that setting
> `rodauth.prefix = '/auth'` would make `request.is token_path` require
> `/auth/token` while `remaining_path` is `/token`, "breaking every rodauth
> route," and that the two namespaces are "mutually exclusive at the framework
> level." That is **not** how rodauth 2.42.0 matches. `handle_<name>` runs
> `request.is send(:"#{name}_route")` against the bare route *segment*
> (`"token"`), and `route!` looks up `route_hash[remaining_path]` whose keys
> are `"/#{segment}"` — both prefix-independent. `prefix` only feeds
> `route_path` (URL generation and the `check_csrf?` string comparisons), not
> matching. So `prefix '/auth'` under `Rack::URLMap('/auth')` routes fine; it
> fixes the URL and CSRF symptoms but **not** the issuer, and it is rejected
> for a different reason (blast radius on every non-OAuth route). See the
> corrected rationale and empirical table below.

## Concrete symptoms

1. **Discovery URLs missing `/auth`.** `oauth_server_metadata_body` and
   `openid_configuration_body` build endpoints via
   `base_url + route_path(name)`; `route_path` uses rodauth's empty
   `prefix`. Without patching, discovery emits
   `http://host/token` instead of `http://host/auth/token`.
   - Gem source: `rodauth-2.42.0/lib/rodauth/features/base.rb:668-672`
     ```ruby
     def route_path(route, opts={})
       path  = "#{prefix}/#{route}"
       ...
     end
     ```

2. **CSRF exemption silently fails.** Per-feature `check_csrf?` overrides
   compare against unprefixed `*_path`:
   - `oauth_base.rb:158-165` (`token_path`)
   - `oidc.rb:215-222` (`userinfo_path`)
   - `oauth_token_revocation.rb:71-78` (`revoke_path`)
   - `oauth_authorize_base.rb:61-68` (`authorize_path`)

   Each does `case request.path when token_path`. With `request.path =
   "/auth/token"` and `token_path = "/token"`, no branch matches; super
   runs; CSRF gets enforced on `/token`, breaking SP clients.

3. **Issuer claim mismatch.** Default `authorization_server_url` returns
   `base_url`; default `oauth_server_metadata_body[:issuer]` does the same
   (`oauth_base.rb:746-748`). Discovery clients expecting `/auth` see a
   mismatched `iss`.

## Existing mitigations

`apps/web/auth/config/features/oauth.rb` covers all three symptoms:

- Symptom 1: `prefix_oauth_endpoint_urls!` rewrites every endpoint URL in
  metadata bodies (lines 114-130), applied via overrides on
  `oauth_server_metadata_body` (line 90) and `openid_configuration_body`
  (line 103).
- Symptom 2: `check_csrf?` override (line 199) builds full-path versions
  of `OAUTH_NO_CSRF_PATHS` and matches `request.path` directly.
- Symptom 3: Overrides `authorization_server_url` (line 76) and forces
  `body[:issuer] = authorization_server_url` (line 92).

`apps/web/auth/config/json_mode.rb:43` independently applies the same
`Auth::Application.uri_prefix` prefixing for json-mode path matching.

### Nuance: `oauth_token_revocation` enforces CSRF on form requests

Of the four per-feature `check_csrf?` overrides listed in Symptom 2,
`oauth_token_revocation.rb:71-78` is structurally different from the
others:

```ruby
def check_csrf?
  case request.path
  when revoke_path
    !json_request?   # enforce CSRF on form requests, skip on JSON
  else
    super
  end
end
```

The other three (`oauth_base`, `oidc`, `oauth_authorize_base`) return
`false` unconditionally on path match. Revocation alone *requires* CSRF
for form-encoded requests. This is inverted from OAuth 2.0 spec
expectations: RFC 7009 defines `/revoke` as form-encoded and
authenticated by client credentials, not CSRF tokens.

Two things follow:

1. Even with the prefix mismatch resolved, a standard form-encoded
   `/revoke` from an SP would still be CSRF-blocked by the gem's own
   override. The local `check_csrf?` override
   (`features/oauth.rb:199`) sidesteps this by exempting `/revoke`
   regardless of content type — correct for OAuth semantics.
2. If we ever drop the local override expecting "rodauth-oauth handles
   this correctly once prefix matches," form-encoded revoke breaks.
   The exemption is load-bearing, not merely a prefix workaround.

## Why we don't fix the root cause

Three approaches were considered and rejected:

1. **Set `rodauth.prefix '/auth'`.** ~~Breaks route matching~~ — it does
   **not** (see the Correction in Summary and the table below). Under
   `Rack::URLMap('/auth')`, `prefix '/auth'` routes correctly and fixes the
   discovery-URL and CSRF symptoms. The real reasons to avoid it: (a) it does
   **not** fix the issuer (`base_url`, prefix-independent); and (b) `prefix`
   prefixes **every** rodauth route's URL generation (login, logout, omniauth,
   email links), whereas OTS only wants the OAuth/OIDC endpoints prefixed and
   already does manual `Auth::Application.uri_prefix` prefixing elsewhere
   (`json_mode.rb`) that assumes unprefixed `*_path`. The OAuth-scoped,
   gem-level `oauth_mount_prefix` (taken in #3465) avoids that blast radius.

2. **Mount auth app at `/` and route internally with `r.on('auth')`.**
   Loses isolation from main app routing; conflicts with the
   `Onetime::Application::Base` registry pattern; would force every other
   mounted app to do likewise.

3. **Patch upstream rodauth-oauth to use `request.path_info` for CSRF
   matching.** Correct fix, but invasive and breaks gem semantics for any
   user who has set `rodauth.prefix` non-empty. Belongs in an upstream
   issue, not a local monkey-patch.

At the time of writing, the patch surface (3 method overrides + 1 helper) was
deemed smaller than any structural fix. **#3465 superseded that judgment:** the
gem-level `oauth_mount_prefix` collapses the surface to one setting (plus the
`OAUTH_ISSUER` shim and the `/revoke` exemption), so the structural fix is now
the cheaper one to carry.

### Empirical verification (rodauth 2.42.0)

Measured with `Rack::Test` + `Rack::URLMap` — pristine rodauth core (no fork)
for the routing rows, the fork for the post-fix row:

| Scenario | Result |
|----------|--------|
| pristine core — `prefix '/auth'` + `URLMap('/auth')`, `GET /auth/login` | `200`, login form → **routes** (refutes "every route 404s") |
| pristine core — `prefix` unset + `URLMap('/auth')`, `GET /auth/login` | `200` → routes (OTS today) |
| pristine core — `prefix '/auth'`, **no** mount, `GET /auth/login` | `404`; `GET /login` → `200` (prefix alone doesn't relocate routes; the mount does) |
| **fork (post-fix)** — `oauth_mount_prefix '/auth'` (prefix unset) + `URLMap('/auth')` | `POST /auth/token` routes & **CSRF-exempt**; discovery `token_endpoint` = `http://example.org/auth/token`, `issuer` = `http://example.org/auth` |

The first three rows show `prefix` is irrelevant to *matching* (segment-based,
via `route_hash[remaining_path]` + `request.is <segment>`); the fourth shows the
fork's `oauth_mount_prefix` carrying the mount point into URL generation, the
`issuer`, and the per-endpoint CSRF comparisons without touching matching.
Pinned by `rodauth-oauth`'s `test/oauth/mount_prefix_test.rb` (URLMap mount) and
an OTS-config replica run under Ruby 3.4.9.

## Regression coverage

**Superseded by #3465.** New OAuth routes and per-feature `check_csrf?`
overrides are now handled at the gem level: every route defined via the fork's
`auth_server_route` gets mount-aware `*_path`/`*_url` automatically, so there is
no local list (`OAUTH_NO_CSRF_PATHS`) or helper (`prefix_oauth_endpoint_urls!`)
to keep in sync — both were removed. The gem-bump checklist now lives in the
fork (`doc/release_notes/1_6_5.md`): a new per-feature CSRF override must compare
against the route's (mount-aware) `*_path`, and new discovery fields must be
populated from a route's `*_url` helper rather than `base_url` directly.

Integration tests pinning the behavior:

- `apps/web/auth/spec/integration/oauth/*` — exercise discovery, /token,
  /userinfo, /revoke under the `/auth` mount.
- `rodauth-oauth`'s `test/oauth/mount_prefix_test.rb` — pins the gem-level
  mount-prefix behavior (discovery URLs, issuer, and /token CSRF exemption
  under a `Rack::URLMap` mount).

## This became the fix (#3465)

rodauth-oauth grew exactly the config knob anticipated here: an
`oauth_mount_prefix` that decouples "prefix used for URL generation /
`request.path` comparison" from "prefix used for route matching" (which stays on
`remaining_path`). The forked gem (consumed via the `Gemfile`) honors it in the
discovery metadata builders, the per-feature `check_csrf?` comparisons, and the
issuer derivation, so the three local overrides collapsed into the single
`auth.oauth_mount_prefix { Auth::Application.uri_prefix }` setting. The `/revoke`
CSRF exemption is retained separately (load-bearing — see the Nuance section);
the `OAUTH_ISSUER` shim is retained for static prod deployments.
