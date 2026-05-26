# Rodauth Prefix Mismatch — Investigation & Deferral

Issue #3104 follow-up item #12.

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
and metadata code paths inspect `request.path`. Setting `rodauth.prefix =
'/auth'` would synchronize those, but would also produce `remaining_path =
'/token'` versus required `'/auth/token'` in `request.is token_path`,
breaking every rodauth route. The two namespaces are mutually exclusive at
the framework level.

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

## Why we don't fix the root cause

Three approaches were considered and rejected:

1. **Set `rodauth.prefix '/auth'`.** Breaks route matching: `request.is
   token_path` becomes `request.is '/auth/token'`, but `remaining_path` is
   `/token` after URLMap strips `SCRIPT_NAME`. Every rodauth route 404s.

2. **Mount auth app at `/` and route internally with `r.on('auth')`.**
   Loses isolation from main app routing; conflicts with the
   `Onetime::Application::Base` registry pattern; would force every other
   mounted app to do likewise.

3. **Patch upstream rodauth-oauth to use `request.path_info` for CSRF
   matching.** Correct fix, but invasive and breaks gem semantics for any
   user who has set `rodauth.prefix` non-empty. Belongs in an upstream
   issue, not a local monkey-patch.

The current patch surface (3 method overrides + 1 helper) is small,
documented, and exercised by integration tests. The cost of carrying it
is lower than the cost of any structural fix.

## Regression coverage

Any new rodauth-oauth route or per-feature `check_csrf?` override the gem
adds in a future version will hit the same trap. Reviewers of gem bumps
should check:

- `grep -rn 'case request.path' rodauth-oauth-X.Y.Z/lib/` — any new
  per-feature CSRF override needs its path added to `OAUTH_NO_CSRF_PATHS`.
- `grep -rn 'oauth_server_metadata_body\|openid_configuration_body'` for
  new metadata fields that bypass `prefix_oauth_endpoint_urls!`.
- Any new `*_endpoint` field added to discovery metadata needs to be
  appended to the symbol list at `features/oauth.rb:116`.

Current integration tests pinning the behavior:

- `spec/integration/oauth_idp_lifecycle_spec.rb` — exercises /token,
  /userinfo, /revoke under the `/auth` mount; would 403 on CSRF or 404
  on path mismatch if the overrides regressed.
- Discovery endpoint specs — verify the `iss` field and endpoint URLs
  contain `/auth`.

## When this might become a fix

If rodauth or rodauth-oauth grows a config knob that decouples
"prefix used for URL generation" from "prefix used for `request.is`
matching" (e.g. an explicit `mount_prefix` separate from `prefix`), all
three overrides above collapse into a single setting. Until then, the
mismatch is a framework-level constraint of running rodauth-oauth
behind `Rack::URLMap`, and the local patch is the right place to absorb
it.
