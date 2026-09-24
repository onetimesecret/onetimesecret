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
   (e.g. `gem 'omniauth-gitlab'`), then `bundle install`. If the gem's own
   defaults do not meet the gates this application needs, subclass the
   strategy under `lib/onetime/sso_provider/` and point the definition's
   `gem_require` at that file; the file requires the gem itself, so the gem
   still loads lazily (`request_bound_saml.rb` is the precedent). When the
   gem *is* the trust decision, pin it exactly and write the rationale in
   the `Gemfile` (ruby-saml); `bundler-audit` runs against `Gemfile.lock` on
   every PR (`.github/workflows/static-analysis.yml`).

2. **Decide the issuer question first** (see below). Prefer OIDC-capable
   providers.

3. **Add one definition file** under `lib/onetime/sso_provider/`
   (e.g. `lib/onetime/sso_provider/gitlab.rb`), then require it and append
   its `DEFINITION` to `DEFINITIONS` in
   `lib/onetime/sso_provider/registry.rb`. Copy an existing file of the
   same shape (issuer-capable: copy `entra.rb` or `oidc.rb`; plain OAuth2:
   copy `github.rb`). Every field is documented in the registry header.
   Keep the env prefix consistent (`FOO_ROUTE_NAME`, `FOO_DISPLAY_NAME`,
   `FOO_TRUST_EMAIL_FOR_LINKING`, and `FOO_CLIENT_ID` where the protocol has
   a client credential — SAML has none and declares `SAML_IDP_*` instead) —
   the registry spec enforces the route/display/trust prefix.

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
   neutral building-office icon; `saml` maps to the generic `key` glyph.

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

A definition whose `strategy_options` **raises** (Auth0, SAML) is skipped with
an error in the boot log; boot itself never fails. When org-level SSO is on,
the placeholder route is registered anyway — the same outcome as the vars
being absent — so a platform-side typo cannot delete the route that tenant
SSO injects into; `vars_valid` keeps the platform button hidden meanwhile.

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
  issuer collapse to the `''` sentinel. SAML is that case: `resolve_issuer`
  has a dedicated branch, decided by strategy **class**
  (`OmniAuth::Strategies::SAML`, never by route name), that reads the
  validated IdP EntityID from `extra['idp_entity_id']` and raises instead of
  ever returning `''` — see the SAML quirk below.

- **Issuerless** (`issuer_capable: false`): plain OAuth2 providers (GitHub,
  Google, Facebook, Discord, GitLab in OAuth2 mode). They resolve to the `''`
  sentinel issuer on every surface, so the **tenant surface refuses them at
  callback time** (`refuse_issuerless_on_tenant?` — this is deliberate,
  fail-closed protection against cross-surface identity binds). They remain
  available for platform SSO only. Each new issuerless provider re-adds a
  `(provider, '', uid)` platform-collision surface, so add them sparingly.

When a provider supports both modes (GitLab, Okta), integrate it through OIDC
(`omniauth_openid_connect` with the provider's issuer) rather than its bespoke
OAuth2 strategy — it then inherits issuer scoping for free. Auth0 is
configured this way: the bespoke `omniauth-auth0` strategy was tried and
dropped before release because its claim validation never runs (see the note
below) and its `jwt ~> 2` pin held the whole bundle off jwt 3.x. Apple is a
**platform-only** provider, absent from `SsoConfig::PROVIDER_ROUTE_MAP`. SAML
is in that map (`'saml'`) and is tenant-eligible, because its issuer is the
tenant's own IdP EntityID.

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
- **SAML 2.0** (`omniauth-saml` + `ruby-saml`, #4450): issuer-capable,
  tenant-eligible, and the reference case for ADR-044 criterion 1 (an IdP that
  speaks only SAML has no OIDC login flow). It is registered **only** through
  this application's subclass `OmniAuth::Strategies::RequestBoundSAML`
  (`lib/onetime/sso_provider/request_bound_saml.rb`, declared as
  `strategy: :request_bound_saml`); the stock strategy is issuerless as
  shipped and accepts unsolicited responses, so `STRATEGY_CLASS_MAP` in the
  tenant hook names the subclass alone. The definition
  (`lib/onetime/sso_provider/saml.rb`) is configuration only and loads without
  either gem. `Onetime::SsoProvider::Saml.strategy_options_for` is the single
  hardened-options builder for the platform definition and the tenant arm
  (`CustomDomain::SsoConfig#build_saml_options`); the `security:` hash is
  always passed **in full**, because omniauth-saml builds
  `Settings.new(options)` without `keep_security_attributes` and a partial
  hash would replace ruby-saml's defaults with nils. `allowed_clock_drift`
  and `check_duplicated_attributes` are Response options and only work at the
  top level of the strategy options, not under `security`.
  The subclass owns every SAML-specific gate. Each fails closed and surfaces
  as an ordinary OmniAuth failure (the existing `sso_failed` path) with a
  scalar-only `[saml_response_refused]` log event naming the `reason`:
  - **No IdP-initiated SSO.** The request phase stores the AuthnRequest id in
    the session (`saml_authn_request_id` — one per session, so a second
    sign-in tab supersedes the first) and the callback consumes it before a
    byte is parsed, passing it as `matches_request_id`. A callback with no
    pending id is refused (`saml_no_pending_request`). ruby-saml treats a
    nil `matches_request_id` as "do not check", so this binding is the whole
    of the login-CSRF control — SAML has no `state` parameter.
    Only a POST carrying a `SAMLResponse` consumes the id: anything else
    (a cross-site `<img>` GET, a HEAD, a bare POST) is refused
    (`saml_response_missing`) with the pending id left in place, because
    the SameSite=None cookie the POST binding needs means such a request
    arrives with the user's session and would otherwise cancel their
    in-flight sign-in.
  - **Binding read from the signed assertion.** `matches_request_id` is
    compared by ruby-saml against the UNSIGNED `Response/@InResponseTo`;
    the signed assertion's `SubjectConfirmationData/@InResponseTo` is
    checked only when present. A valid signed assertion whose confirmation
    data omits it (IdP-initiated, or one an attacker obtained by starting
    their own login) therefore passes the gem once rewrapped in a Response
    naming the victim's pending id. After validation the strategy re-reads
    the bearer `SubjectConfirmation` elements through ruby-saml's
    signed-assertion accessor and requires EVERY one to carry
    `InResponseTo` byte-equal to the pending id
    (`saml_in_response_to_unbound`). IdPs that omit the attribute on
    SP-initiated responses are refused by design; Okta, Entra ID and AD FS
    always emit it. Requiring the attribute is the SAML 2.0 Profiles
    baseline (4.1.4.2/4.1.4.3). Requiring it on *every* bearer confirmation
    is stricter than the baseline, which accepts the assertion when any one
    bearer confirmation validates; that is a deliberate hardening choice
    (a mixed bound/unbound assertion is ambiguous about which login it
    answers), not a spec requirement.
  - **Signature algorithm allowlist.** ruby-saml verifies with whichever
    `SignatureMethod` / `DigestMethod` URI the response declares and maps
    any URI it does not recognise to SHA-1 (`xml_security.rb` `algorithm`),
    so a SHA-1 signed response verifies under the hardened settings. After
    validation the strategy reads every `ds:Signature` in the validated
    REXML document(s) (`response.document`, `decrypted_document`) — the same
    parser and objects the verifier read — and refuses anything outside
    `ALLOWED_SIGNATURE_METHODS` / `ALLOWED_DIGEST_METHODS` (RSA/ECDSA
    SHA-256/384/512, digests SHA-256/384/512) as
    `saml_weak_signature_algorithm`. `idp_cert_fingerprint_algorithm` is
    pinned to SHA-256 for the same reason: the gem matches a certificate
    embedded in the response against the pinned one by fingerprint (SHA-1 by
    default) and then verifies with the embedded one.
  - **Issuer byte-equality.** After ruby-saml validates the document, the
    response must carry exactly one Issuer value (Response and signed
    Assertion, uniq'd) that is `==` the configured `idp_entity_id`
    (`saml_issuer_unreadable`, `saml_issuer_mismatch`). The gem's own
    `uri_match?` is case-insensitive on scheme and host, which is not good
    enough for a value the identity row is keyed on. A blank `idp_entity_id`
    or `sp_entity_id` is refused at both phases (`saml_misconfigured`)
    because ruby-saml *skips* issuer and audience validation when they are
    blank.
  - **Never `issuer:`.** In ruby-saml `issuer` is a deprecated alias for
    **our** SP EntityID (`settings.rb`, `sp_entity_id || issuer`); a
    definition that declared it the way Apple's does would key every SAML
    identity on one constant. The validated EntityID reaches `resolve_issuer`
    as `extra['idp_entity_id']` through a SAML-only branch that raises
    `SamlIssuerUnresolved` rather than returning `''`;
    `retrieve_omniauth_identity` rescues that into an audited refusal on
    **both** surfaces (`omniauth_saml_issuer_unresolved_refused`). For SAML,
    `raw_info['iss']` is never read — every `raw_info` key is an attribute
    name the IdP chooses. `registry_spec` asserts the definition has no
    `:issuer` key.
  - **Tenant identities are scoped to the domain.** On a tenant surface the
    issuer half of the key is
    `Onetime::SsoProvider::Saml.tenant_issuer(domain_id, idp_entity_id)`
    — `"<domain_id>|<EntityID>"` — not the bare EntityID. A SAML EntityID is
    an unauthenticated name a tenant admin asserts alongside their **own**
    signing certificate (nothing like OIDC discovery ties it to an origin),
    so on a bare-EntityID key tenant B could configure tenant A's EntityID
    (or the platform's `SAML_IDP_ENTITY_ID`) with B's certificate, have B's
    IdP sign a response naming it and the victim's NameID, pass every
    strategy gate and resolve A's identity row. The scope is read through
    `omniauth_identity_scope_domain_id`, a copy the tenant hook stamps and
    nothing consumes — rodauth-omniauth builds the identity insert hash
    *after* `after_omniauth_create_account` has consumed the session copy.
    `bin/ots sso backfill-issuer` refuses `saml` domains outright, with or
    without `--issuer`: the legacy `''` rows hold OAuth/OIDC `sub` values
    from the domain's previous provider, and a NameID is a different
    namespace, so stamping the SAML issuer onto them would let a NameID that
    collides with an old `sub` resolve to that account. The platform
    surface keeps the bare EntityID, so tenant and platform rows can never
    match each other. `tenant_saml_sso_spec` drives the attack end to end.
  - **Stable uid.** The uid is the NameID; the persistent format is requested
    in every AuthnRequest. A transient NameID is refused unless
    `uid_attribute` is configured (`saml_transient_name_id`); a blank uid is
    refused (`saml_missing_uid`). Tenants have no `uid_attribute` setting —
    the tenant arm resets it to nil so a platform `SAML_UID_ATTRIBUTE` cannot
    leak into tenant logins.
  - **Assertion replay and lifetime.** `Onetime::Security::SamlAssertionReplayGuard`
    claims `SET NX EX` on a digest of (EntityID, assertion id) with
    TTL = `NotOnOrAfter` − now + clock drift, floored at 1s
    (`saml_assertion_replayed`; `saml_assertion_unbounded` when the assertion
    has no ID or no `NotOnOrAfter`; `saml_replay_guard_unavailable` on any
    datastore error). ruby-saml imposes no maximum `NotOnOrAfter`, so the
    strategy does: an assertion valid for longer than
    `MAX_LIFETIME` (3600s) + clock drift past now is refused
    (`saml_assertion_lifetime_exceeded`) rather than remembered for a
    clamped, shorter time — a marker that expires before the assertion
    does is no marker. One hour admits the Entra ID / AD FS default (60
    min) and Okta's (5 min).
  - **Scrubbed `extra`.** The gem's `extra` carries the live
    `response_object` — the settings (IdP cert, SP key if any) and the full
    response XML. The subclass replaces `extra` with scalars:
    `idp_entity_id`, `name_id_format`, `session_index`, and `raw_info` as a
    plain `Hash` of attribute name => `Array<String>` (the injected
    `fingerprint` key dropped; values stay arrays). It also deletes the gem's
    `session['saml_uid']` / `['saml_session_index']`, clears the gem's
    RelayState forwarding (`idp_sso_service_url_runtime_params` — as a
    **class** default, because an instance-level `{}` is deep-merged into the
    gem's default and changes nothing), strips every ruby-saml `skip_*`
    option, and fixes `callback_url` to `full_host + callback_path` (omniauth's
    default appends the request query string and omniauth-saml makes that the
    ACS URL).
  - **SLO is off** (`slo_enabled: false`; `/slo` and `/spslo` answer 501).
    The gem's IdP-initiated logout default is `session.clear` on the Rack
    session, which bypasses this application's active-session rows; SLO needs
    its own design against the revoke/destroy vocabulary before it is turned
    on. `/metadata` stays up as public SP metadata, except that it answers
    404 while the trust anchors are blank (the placeholder registration with
    no tenant resolved).
  - **Verification rests on IdP trust.** SAML has no `email_verified` claim;
    a JIT account is verified because the operator configured the IdP. An
    attribute the IdP happens to name `email_verified` with a `false` value
    is still honoured as a hold — `email_verification_hold` unwraps the
    `Array` values SAML attributes arrive as.
  **Operator prerequisites:** the HTTP-POST binding is a cross-site POST, so
  SAML needs `site.session.same_site: none` with `secure: true` exactly like
  Apple, and the callback origin is admitted through `HttpOriginOptions` from
  the **SSO service URL's** origin (`idp_origin_from`), never the EntityID (an
  opaque name, often a URN on another host). A tenant's SAML IdP origin is
  admitted per request by `sso_callback_from_tenant_idp?`, the counterpart of
  the platform set, sourced from the same record field as CSP `form-action`
  (`AuthConfig::TENANT_ORIGIN_SOURCE_FIELDS`).
  **Skip, not fail-boot.** Issue #4450 asked for a boot failure when
  `SAML_IDP_ENTITY_ID` is missing. `configure_provider` is built never to
  kill boot (an exception inside Rodauth configuration takes password, MFA
  and magic-link sign-in down with it), so SAML follows the skip contract:
  `strategy_options` raises naming the variable, the provider is skipped
  with an error in the boot log, and `vars_valid` (https SSO URL, non-blank
  EntityID, exactly one unexpired PEM certificate — fingerprints are never
  accepted) keeps the button hidden. With org-level SSO on, the placeholder
  route (blank trust anchors) is registered anyway so the tenant hook has a
  route to inject into; the subclass refuses every un-injected request on
  it.
  **Gem currency.** `ruby-saml` is pinned exactly (`= 1.18.1`; its 1.17 and
  1.18 releases were signature-verification and parser-differential CVE
  fixes) with the rationale in the `Gemfile`; `bundler-audit` runs on every
  PR and Renovate's vulnerability alerts open the bump PR. Every bump is a
  review, not an automerge. The gem internals this integration depends on
  carry `RE-VERIFY on bump` markers in three places — the `Gemfile` comment,
  the `request_bound_saml.rb` header, and the `SAML INVARIANT` block in
  `features/omniauth.rb`: the copied `request_phase` body, the wrapped
  private `options_for_response_object` / `handle_response` /
  `other_phase_for_metadata`, `issuers` raising on a missing or repeated
  Issuer, `validate_in_response_to` passing on nil, `Settings.new` replacing
  `security`, `extra` being an overridable method, and options being
  deep-merged. `registry_spec` pins the `SECURITY` keys to
  `Settings::DEFAULTS[:security].keys`, so a new gem default fails the spec.
  ruby-saml's STDOUT logger (it logs AuthnRequest XML at DEBUG) is re-pointed
  at the `Auth` logger by `RubySamlLogBridge` when the gem is required.
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

SAML refusals made by `RequestBoundSAML` are ordinary OmniAuth failures and
land on `sso_failed`; the `reason` is in the `[saml_response_refused]` log
event, and document-validation failures from ruby-saml arrive as
`invalid_ticket` in the `[OmniAuth FAILURE]` line. A custom domain whose
stored SAML record is unusable (expired certificate, unreadable field) is
refused before the strategy runs and lands on `sso_config_unusable`, with an
`omniauth_tenant_config_unusable` audit event at error level.
