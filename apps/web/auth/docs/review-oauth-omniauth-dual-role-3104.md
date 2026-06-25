# apps/web/auth/docs/review-oauth-omniauth-dual-role-3104.md
---
# Review: rodauth-oauth (IdP) + rodauth-omniauth (SP) dual-role integration — `feature/3104-idp`

> Multi-agent workflow review (4 mappers → synthesis), 2026-05-28. Gem source
> (rodauth-oauth 1.6.4, rodauth-omniauth 0.6.2) was on disk and used to verify
> every load-bearing claim about gem internals.
>
> **Methodology caveat:** the per-codepath adversarial-verification phase failed
> (review agents did the analysis but did not emit structured findings, so the
> independent N-verifier pass never ran). This report is therefore a single
> synthesis pass that re-verified the mappers' findings against gem source — not
> the intended independent-verification design. Findings are reasoned from source;
> none were empirically confirmed by booting the app or running the suite. Treat
> the HIGH `/authorize` CSRF finding in particular as "needs runtime confirmation."

## 1. Executive summary

The dual-role integration is sound and ships safely behind `oauth_enabled?`. The
hard structural problem — two Rodauth features (SP omniauth, IdP oauth) sharing one
instance mounted at Rack `/auth` while rodauth's internal `prefix` stays empty — is
correctly contained: the `only_json?` clobber that previously broke SSO callbacks is
centralized in a single-owner registry (`Auth::JsonMode`), `check_csrf?` chains
rather than clobbers, and the prefix-mismatch URL rewriting is verified against gem
source. No critical (auth-bypass / token-forgery / cross-tenant) defects found. The
two material risks are both *coverage* gaps on load-bearing security gates, plus one
real end-to-end functional defect in the dev loopback refresh-token flow. Every
gem-internal assumption spot-checked (offline_access stripping, unconditional
`auth_time` write, the `jwt_decode` AND-chain, omniauth's non-definition of
`only_json?`/`check_csrf?`) held verbatim against the 1.6.4 / 0.6.2 source on disk.

## 2. Architecture overview

One `Auth::Config` (Rodauth) instance enables `:oauth_authorization_code_grant,
:oauth_pkce, :oidc, :oauth_token_revocation` (IdP/OP) alongside the pre-existing
omniauth feature (SP/RP). `:oidc` transitively pulls `:active_sessions, :oauth_jwt,
:oauth_jwt_jwks, :oauth_implicit_grant`. The instance is mounted by Rack::URLMap at
`/auth`; rodauth's own `prefix` is empty because `remaining_path` is already
`/token` after SCRIPT_NAME is stripped.

That mismatch is the central seam and forces manual `/auth` re-prefixing in three
independent places, all verified:

- **URL/issuer generation** — `authorization_server_url`,
  `oauth_server_metadata_body`, `openid_configuration_body`,
  `prefix_oauth_endpoint_urls!` (oauth.rb:75-131). The gem builds `base_url +
  route_path` with the empty prefix (oauth_base.rb:740, oidc.rb:810), so URLs and
  `iss` come out without `/auth` absent the override.
- **CSRF** — three layers: Rack::Protection `AuthenticityToken` allow_if
  (security.rb:162-166), rodauth `route_csrf` (skipped for SSO via empty
  `omniauth_request_validation_phase`), and the `check_csrf?` override (oauth.rb:201).
  The override's `super()` re-enters the gem chain; the gem's own `when token_path`
  exemptions are dead under the mount (request.path is full `/auth/token`), making
  the override load-bearing.
- **JSON mode** — `Auth::JsonMode` (json_mode.rb) is the sole live `only_json?`
  writer, consulting `OAUTH_EXEMPT_PATHS` + `omniauth_prefix`; must run last
  (config.rb:158).

The account bridge: `accounts.external_id` (Sequel) ↔ `Onetime::Customer`
(Familia/Redis), resolved by `customer_for_account` via extid-then-email. SSO JIT
provisioning runs in `after_omniauth_create_account` (new) / `after_login`
(existing), coordinated by single-consume-by-delete of
`session[:validated_omniauth_domain_id]`.

## 3. Findings by severity

### HIGH — `/authorize` consent POST is exempted by no CSRF layer and the gem form carries only one of two required tokens
- **Where:** lib/onetime/middleware/security.rb:162-166 (allow_if omits
  `/auth/authorize`); rodauth-oauth-1.6.4/templates/authorize.str:2
  (`#{csrf_tag(rodauth.authorize_path) if respond_to?(:csrf_tag)}`).
- **Classification:** DEFECT (latent; affects the local-IdP dev loop via
  `configure_local_idp_provider`).
- **Spec pinned:** No. Specs seed `oauth_grant` rows directly; no real consent POST
  is exercised.
- **Verified:** The gem template emits only rodauth's `csrf_tag` (route_csrf
  `_csrf`), NOT the `shrimp` param that Rack::Protection::AuthenticityToken
  validates. No app-level authorize view overrides the gem template. No CSRF
  param-name aliasing exists, so `_csrf` ≠ `shrimp`. A browser consent POST to
  `/auth/authorize` must satisfy both token systems; the form supplies one. If
  AuthenticityToken middleware processes `/auth` (the explicit `/auth/*` allow_if
  entries confirm it does), the POST is rejected before rodauth runs.
- **Risk:** The browser consent step cannot complete; the documented dev loopback
  flow is broken end-to-end. Not an auth bypass — it fails closed.
- **Fix:** Either add `/auth/authorize` to the gem's authorize template so it also
  emits `shrimp` (custom view), or whitelist `/auth/authorize` in security.rb
  allow_if *and* rely solely on rodauth `route_csrf` for it (preferred — keeps one
  CSRF system on the one browser-driven endpoint). Add an integration spec that
  drives a real authenticated consent POST.

### HIGH — `response_type=code` enforcement gate has zero executing assertion
- **Where:** apps/web/auth/config/features/oauth.rb:179 (`check_valid_response_type?`
  override).
- **Classification:** DEFECT (coverage gap on a security gate; the override itself
  is correct).
- **Spec pinned:** No (the gate). protocol_spec:217 tests only the discovery
  *setter* (`response_types_supported == ["code"]`). No spec POSTs
  `response_type=token`/`id_token` to `/authorize`. endpoints_spec defers
  `/authorize` param validation.
- **Verified:** Gem default chain hardcodes acceptance of `token`
  (oauth_implicit_grant.rb:89) and hybrid/`none` (oidc.rb:694-703). The override is
  the *only* thing rejecting implicit/hybrid; the metadata setter alone does not
  block them. Deleting the override leaves the suite green.
- **Risk:** A regression (gem bump, accidental override deletion) silently
  re-activates implicit/hybrid grant issuance while all specs pass.
- **Fix:** Add a spec: authenticated session, POST `/authorize` with
  `response_type=token` (and `id_token`), assert rejection.

### MEDIUM — Loopback `offline_access` yields no refresh token end-to-end
- **Where:** apps/web/auth/config/features/omniauth.rb:204-205 (scope includes
  `offline_access`, no `prompt: consent`).
- **Classification:** DEFECT.
- **Spec pinned:** No — lifecycle_spec:226-243 seeds the grant directly with
  offline_access and bypasses `/authorize`, so the stripping path is never
  exercised.
- **Verified:** oidc.rb:322-326 (verbatim) deletes `offline_access` from the scope
  set unless `prompt == "consent" AND response_type splits to include "code"`. The
  provider sets neither `prompt` nor `extra_authorize_params`; omniauth_openid_connect
  strips nil params. So no refresh_token is issued (oidc.rb:772). The
  "do-not-remove offline_access" comment is correct that the scope is necessary but
  it is insufficient.
- **Fix:** Add `prompt: 'consent'` (via `extra_authorize_params`) to
  `configure_local_idp_provider`, and add a spec driving the real `/authorize`
  consent path.

### MEDIUM — Stale/misleading comment: "`id_token_claims` intentionally NOT overridden"
- **Where:** apps/web/auth/config/hooks/oauth.rb:134-141 vs features/oauth.rb:227-233.
- **Classification:** DEFECT (doc).
- **Verified:** features/oauth.rb:227 *does* override `id_token_claims` (the #3233
  auth_time-drop). The hooks comment claims the opposite. `define_method` REPLACES
  with no super-chain, so a maintainer trusting the hooks comment and adding a second
  override would silently clobber the auth_time fix.
- **Fix:** Replace the hooks comment with a pointer to the features/oauth.rb override
  ("id_token_claims IS overridden in features/oauth.rb:227 for #3233; do not add a
  second definition").

### MEDIUM — `only_json?` last-writer-wins ordering is enforced only by sequence + comment
- **Where:** apps/web/auth/config.rb:158 (JsonMode.configure must be last),
  json_mode.rb:34.
- **Classification:** TRADEOFF-RECONFIRM (reasoning holds, fragility acknowledged).
- **Spec pinned:** Indirect — json_mode_spec asserts the exempt union, but against
  `OAUTH_EXEMPT_PATHS_FIXTURE` (hand-copied), not the live constant.
- **Risk:** Any future hook/feature added after config.rb:158 that touches
  `only_json?` silently re-introduces the original SSO-callback-400 bug. No guard,
  only ordering.
- **Fix:** Assert in a spec that JsonMode is the last writer, or have json_mode_spec
  import the live `Hooks::OAuth::OAUTH_EXEMPT_PATHS` instead of the fixture.

### MEDIUM — Triple path-allowlist drift
- **Where:** security.rb:162-166 (`/auth/*` allow_if), OAUTH_NO_CSRF_PATHS
  (oauth.rb:46), OAUTH_EXEMPT_PATHS (hooks/oauth.rb:38).
- **Classification:** TRADEOFF-RECONFIRM (fragility).
- **Risk:** A new OAuth endpoint must be hand-added to all three; missing one yields
  a silent 400/403 or an unintended CSRF bypass. The lists intentionally differ
  (`/authorize` is in EXEMPT_PATHS but not NO_CSRF_PATHS), so they cannot simply be
  unified.
- **Fix:** A spec that, given the gem's mounted OAuth routes, asserts each is covered
  (or deliberately excluded) consistently across the three lists.

### MEDIUM — Account linking is purely email-based with auto-verify (pre-existing)
- **Where:** rodauth-omniauth callback `account_from_omniauth → _account_from_login`;
  `omniauth_verify_account?` true.
- **Classification:** TRADEOFF-RECONFIRM.
- **Risk:** Any IdP the SP trusts that returns a victim's email links/takes over the
  existing OTS account. `before_omniauth_create_account` domain policy gates only NEW
  accounts; existing-account linking has no domain gate. Acceptable for trusted
  enterprise IdPs; reconfirm before adding multi-IdP consumer providers
  (Google/GitHub) where email ownership isn't guaranteed verified.

### MEDIUM — Key-stability unit spec tests the wrong library
- **Where:** apps/web/auth/spec/unit/oauth_jwt_key_stability_spec.rb (ruby-jwt
  `JWT::JWK`); runtime signs/publishes via json-jwt `JSON::JWK` (lifecycle_spec:492
  notes this).
- **Classification:** DEFECT (coverage).
- **Risk:** The two thumbprint algorithms differ, so cross-boot stability of the
  *actually emitted* `kid` is not pinned. If json-jwt's thumbprint were
  non-deterministic across loads, SPs' cached keys would break on deploy and no spec
  catches it. lifecycle_spec:487 pins `kid ∈ JWKS` for one boot only.
- **Fix:** Re-derive the expected thumbprint via `JSON::JWK` (the runtime library)
  and assert stability across two boots.

### LOW (grouped)
- **PKCE plain DB CHECK (migration 010) unasserted** — the real plain-rejection gate;
  no spec inserts `code_challenge_method='plain'` to confirm the constraint fires
  (oauth-server.md:139 prose-only). Fix: one insert-rejection spec.
- **`before_omniauth_create_account` normalization divergence** — domain re-derived
  with `.downcase` (omniauth.rb:119) but account creation uses `normalize_email(:fold)`;
  latent edge case for non-ASCII/Turkish-I addresses.
- **JoinDomainOrganization swallows transient errors** — rescues StandardError →
  soft-fail (join_domain_organization.rb:82); a transient Redis error drops the user
  into their personal workspace with only a log line.
- **seed_dev_oauth_client non-atomic** — relies on unique index +
  UniqueConstraintViolation rescue (documented, dev/test only).
- **`prefix_oauth_endpoint_urls!` mount-path coupling** — substring guard correctly
  distinguishes `/auth` vs `/authorize` (oauth.rb:124-125) but assumes `uri_prefix`
  is exactly the mount path; a mount change without updating this breaks every
  advertised URL.
- **lifecycle_spec:102-115 stale comment** — the "FINDING (seed bug)" note and
  defensive `grant_types .update` are now a no-op; the seeder writes
  `'authorization_code refresh_token'` (seed_dev_oauth_client.rb:92). Remove.

## 4. Documented tradeoffs reconfirmed

- **/userinfo does not enforce JWT `exp` at the JWT layer (#3231).** Reasoning HOLDS.
  Verified verbatim: oauth_jwt_base.rb:269-275 is an AND-chain that returns (rejects)
  only when *all* claim checks fail simultaneously, so a token with valid iss/aud/iat/jti
  but past `exp` passes the JWT gate. The effective gate is the DB row:
  `valid_oauth_grant_ds` filters `expires_in >= CURRENT_TIMESTAMP` (oauth_base.rb:599);
  an attacker cannot forge a row. DIRECT-pinned both halves (lifecycle:312
  inverse-pins the broken chain, lifecycle:355 pins the DB gate). Re-confirm on gem
  bump — lifecycle:312 will flip red if upstream fixes the AND-chain.
- **`response_types_supported: ["code"]` narrower than OIDC Discovery 1.0 §3.** HOLDS.
  Intentional single-consumer IdP. Note the *enforcement* is the oauth.rb:179
  override, not the metadata setter (see HIGH #2).
- **`auth_time` dropped when 0 (#3233).** HOLDS. Verified oidc.rb:565 writes
  `auth_time` unconditionally via `get_oidc_account_last_login_at(...).to_i`, which is
  0 for sessionless accounts. The override deletes it when zero, leaving other claims
  intact. DIRECT-pinned (lifecycle:470).
- **`http` URI scheme allowed in dev.** HOLDS. Defaults to `'http https'`, tightened
  to `https` via `OAUTH_VALID_URI_SCHEMES` in prod (oauth.rb:154).
- **Refresh token 30d (vs gem 1yr), rotation policy.** HOLDS — tighter than gem
  default, explicit.
- **Empty `omniauth_request_validation_phase` skips Roda route_csrf, relying on OAuth
  `state`.** HOLDS — Rack::Protection is also skipped for `/sso`.
- **No `only_json?`/`check_csrf?` clobber from omniauth.** RECONFIRMED FROM SOURCE:
  rodauth-omniauth 0.6.2 declares only `omniauth_*`-prefixed auth methods and does
  NOT define `only_json?` or `check_csrf?` — it only *calls* `check_csrf?` at
  omniauth_base.rb:123. The clobber class of bug does not recur for these.

## 5. Coverage & completeness gaps

What the specs do NOT cover (gem source WAS available and used; these are spec gaps,
not unverifiable-gem claims):
- **`/authorize` consent POST CSRF** — no real consent POST is driven (specs seed
  grant rows). Both the HIGH CSRF defect and the offline_access stripping path are
  invisible to the suite.
- **`response_type` rejection gate** — no spec POSTs a forbidden `response_type` to
  `/authorize`; coverage-coupled to nothing.
- **PKCE plain DB CHECK** — no insert asserts the migration-010 constraint fires.
- **Cross-boot `kid` stability of the json-jwt key** — the unit spec exercises
  ruby-jwt, the wrong library.
- **only_json? exemption** — pinned against a hand-copied fixture, not the live
  constant; can silently drift.
- **CSRF behavior generally** — INDIRECT only; the load-bearing negative case
  (`/authorize` *keeps* CSRF) is untested.

What was verified directly against gem source on disk: offline_access stripping
(oidc.rb:322-326), unconditional auth_time write (oidc.rb:565), the jwt_decode
AND-chain (oauth_jwt_base.rb:269-275), the authorize template's lone csrf_tag
(authorize.str:2), and omniauth's auth-method surface (no only_json?/check_csrf?
definition).

**What this review may have missed:** the spec suite was not run, the app was not
booted, and no live browser consent POST or real loopback SSO round-trip was
exercised. The HIGH CSRF finding is reasoned from source and is empirically
confirmable only by attempting an actual consent POST against a running instance with
AuthenticityToken enabled for `/auth`. The non-OAuth callees of the SP provisioning
path (`CreateCustomer`, `CreateDefaultWorkspace`, `JoinDomainOrganization`) were not
audited beyond the traced seams, nor the Vue/SPA front-end consent UI. RSA-only JWT
signing, JWKS rotation semantics, and discovery-doc consumption by strict third-party
clients were assessed from code/config, not from a conformance tool.

### Methodology note (workflow run wuvwvrwwe)

4 mapper agents + synthesis succeeded; 12 per-codepath review agents failed to emit
structured output (heavy reads + a complex required schema), so the planned
independent adversarial-verification pass did not execute. The findings above come
from the mappers' verified risk lists consolidated and re-checked against gem source
by the synthesis agent — strong, but a single verification pass rather than the N
independent verifiers the design intended. The two HIGH findings warrant runtime
confirmation before acting.
