# Clerk platform OIDC investigation results

Related scope: [Clerk platform OIDC compatibility spike](clerk-platform-oidc.md).

## Status

**Live checks complete for a Clerk development instance (2026-10-12).** Outcome, as this investigation's interpretation: configuration-only compatibility, with one setting beyond the generic OIDC variables (CLERK-07); see [Assessment](#assessment). No production-support claim is established. No application code or installed dependencies were changed. The local configuration added for the live run is listed under [Live sign-in results](#live-sign-in-results-2026-10-12).

Source inspection baseline: `fba1dd2623c299a5f0bd4c02952269b6f1991a8c`, 2026-10-12.

Inspected installed/locked dependencies:

- `omniauth_openid_connect` 0.8.0
- `openid_connect` 2.5.0
- `rack-oauth2` 2.3.0

## Findings and dispositions

The findings began as source and documentation observations. Dispositions that say "live" record observations of the Clerk development instance. No finding authorizes weakening existing checks.

| ID | Finding | Disposition |
| --- | --- | --- |
| CLERK-01 | OTS and its OIDC strategy request `/.well-known/openid-configuration`. Clerk documents `/.well-known/oauth-authorization-server`; its sample also omits `userinfo_endpoint`, which the strategy needs for UserInfo. | **Resolved by live discovery (see below):** the instance serves `/.well-known/openid-configuration` (HTTP 200, no redirect) including `userinfo_endpoint`. The installed gem's discovery and the OTS discovery fetcher both accept it. No fallback needed. |
| CLERK-02 | Configured issuer, discovery issuer and token issuer are checked for exact agreement. | **Discovery-level match observed:** the advertised issuer has no trailing slash; configured exactly, it matches in both the gem and `DiscoveryIssuer`, and the trailing-slash form is rejected by both. In the ID-token probe, the token's `iss` passed the strategy's exact-issuer `verify!`. |
| CLERK-03 | The strategy defaults to HTTP Basic client authentication; omitting a client secret does not select authentication method `none`. Clerk's metadata example advertises `client_secret_basic` and `none`. | **Spike scope:** use a confidential OAuth application with client ID and secret. The instance advertises `client_secret_basic`, `client_secret_post` and `none`, so the strategy default is advertised. Token exchange with `client_secret_basic` was observed live. Public-client compatibility was not attempted. |
| CLERK-04 | The installed strategy generates S256 PKCE and a nonce. It also permits callback parameters to take precedence over stored nonce/verifier values, and skips ID-token verification if the response omits an ID token. State checking still applies. | **Partly resolved live:** a separate probe showed Clerk returns an ID token for `openid`, echoes the nonce, and passes the strategy's signature/`iss`/`aud`/`nonce` verification. Live negative checks also passed: `access_denied`, a cookie-less replay, and a foreign `state` on an authenticated session were all rejected without a new session. The strategy-level caveats (callback parameters take precedence over stored nonce/verifier; verification is skipped when no ID token is returned) are unchanged and were not exercised. No dependency patch made. |
| CLERK-05 | The strategy merges UserInfo and ID-token claims, with ID-token claims taking precedence. Explicit false email verification differs from absent verification in OTS provisioning/linking logic. | **Claims consistent for one identity:** for a GitHub-sourced Clerk user, the ID token and UserInfo agree on `sub` and `email`, and both carry `email_verified: true` as a boolean. **Collision observed:** a Clerk-asserted email that matches a verified OTS account with a password is held at the password link interstitial, not auto-linked (see [Existing-email collision](#existing-email-collision)). Email auto-link trust stays disabled. Conflicting Clerk claims have not been observed. |
| CLERK-07 | Live, Chrome: "Sign in with Clerk" stalls on "Redirecting to identity provider…". The page recorded an enforced `form-action` violation for the POST to `/auth/sso/oidc`. OTS adds only the issuer origin (`https://unified-parrot-698.clerk.accounts.dev`) to `form-action`. For a signed-out browser, Clerk's `/oauth/authorize` answers 302 to its hosted sign-in page at `https://unified-parrot-698.accounts.dev/sign-in`, a different origin. Chrome masks the cross-origin hop in the violation report, so naming it as the blocked hop is an inference from the observed redirect chain. | **Configuration constraint:** add the Account Portal origin with the existing `SSO_FORM_ACTION_ORIGINS` override (process-wide, read at boot). [per-install-sso.md](../../authentication/per-install-sso.md) scopes the override to "split-endpoint OIDC or a tenant discovery-availability fallback". Clerk's case differs: its authorization endpoint shares the issuer origin, and the following redirect leaves it. Applying the override here is an interpretation of its purpose. **Verified live:** after adding the override and restarting, the same click reached Clerk's sign-in page and the flow completed. |
| CLERK-06 | External identity uses provider route, issuer and subject. Route/issuer changes affect identity resolution; platform lookup also supports legacy issuerless rows. | **Experiment constraint:** use a dedicated test installation/identity set, retain a stable provider route, and avoid repurposing an existing provider's identities. Observed live: first and repeat login, a held collision, and explicit linking through the authenticated connect path; each identity row carries the exact issuer. |

Source entry points:

- [OIDC provider definition](../../../lib/onetime/sso_provider/oidc.rb)
- [Discovery fetcher](../../../lib/onetime/sso_provider/discovery_fetcher.rb)
- [Discovery issuer checks](../../../lib/onetime/sso_provider/discovery_issuer.rb)
- [Platform/tenant setup hook](../../../apps/web/auth/config/hooks/omniauth_tenant.rb)
- [Identity resolution and persistence](../../../apps/web/auth/config/features/omniauth.rb)
- [Provisioning and email trust hooks](../../../apps/web/auth/config/hooks/omniauth.rb)

External primary sources:

- [Clerk SSO/OIDC guide](https://clerk.com/docs/guides/configure/auth-strategies/oauth/single-sign-on): “The issuer of the token, which matches your Clerk Frontend API URL”.
- [Clerk OAuth implementation guide](https://clerk.com/docs/guides/configure/auth-strategies/oauth/how-clerk-implements-oauth): “You can easily retrieve this metadata by loading your Clerk Frontend API URL with `/.well-known/oauth-authorization-server` appended to it.” Its metadata sample advertises `client_secret_basic`, `none` and `S256`; those are documentation evidence, not a captured response from the target instance.

## Executed validation

The existing `.test-mode` sentinel was present. Tests ran through the isolated lane runner:

```sh
tests/lanes/run full-sqlite --quiet \
  --only apps/web/auth/spec/integration/full/install_oidc_issuer_mismatch_spec.rb \
  --only apps/web/auth/spec/integration/full/sso_route_registration_spec.rb
```

**Result:** 25 examples, 0 failures; seed 55505; SQLite lane, exit 0.

This validates the selected existing discovery/registration tests. Discovery responses are stubbed, and route registration coverage includes tenant placeholder routes. It does **not** validate Clerk endpoints, confidential-client token exchange, live platform provisioning, linking, logout or Entra interoperability. No new synthetic Clerk fixture was introduced to substitute for missing live evidence.

## Live discovery observation (2026-10-12)

Target: Clerk **development** instance `ins_3Kby3r8xmjZfttgZ0sRl5BhclL4` (application `app_3Kby3t5UfTev48Cuh5AzNfSmkYk`), primary domain `unified-parrot-698.clerk.accounts.dev`, marked "Development domain" in the dashboard. OTS source for this check: `main` @ `3c45bb6dd5`, code-identical to the inspection baseline above (the baseline commit changes only documentation).

Both well-known documents returned HTTP 200, `application/json`, with no redirect:

- `https://unified-parrot-698.clerk.accounts.dev/.well-known/openid-configuration`
- `https://unified-parrot-698.clerk.accounts.dev/.well-known/oauth-authorization-server`

Values recorded from the OpenID configuration document:

| Field | Observed value |
| --- | --- |
| `issuer` | `https://unified-parrot-698.clerk.accounts.dev` (no trailing slash) |
| `authorization_endpoint` / `token_endpoint` | `…/oauth/authorize` / `…/oauth/token` |
| `userinfo_endpoint` | `…/oauth/userinfo` (present here; absent from the `oauth-authorization-server` document) |
| `jwks_uri` | `…/.well-known/jwks.json`; one RS256 key, `kid` equal to the instance ID |
| `response_types_supported` | `code` |
| `code_challenge_methods_supported` | `S256` |
| `token_endpoint_auth_methods_supported` | `client_secret_basic`, `none`, `client_secret_post` |
| `id_token_signing_alg_values_supported` | `RS256` |
| `scopes_supported` | includes `openid`, `email`, `profile` |
| `claims_supported` | includes `sub`, `email`, `email_verified`, `iss`, `aud` |
| `end_session_endpoint` | absent |
| `backchannel_logout_supported` / `frontchannel_logout_supported` | `false` / `false` |
| `authorization_response_iss_parameter_supported` | `true` |

Checks run against the live document, outside the app and without credentials:

- `OpenIDConnect::Discovery::Provider::Config.discover!` (`openid_connect` 2.5.0, the call the strategy makes) succeeded for the exact issuer and resolved the UserInfo endpoint and JWKS. With a trailing slash appended it raised `DiscoveryFailed: Issuer mismatch`.
- `Onetime::SsoProvider::DiscoveryFetcher` fetched the document with status `:ok`. `DiscoveryIssuer.check_document` returned `:match` for the exact issuer and `:mismatch` for the trailing-slash form.

Implications, limited to discovery:

- CLERK-01 is not a blocker for this instance.
- `OIDC_ISSUER` must be `https://unified-parrot-698.clerk.accounts.dev` exactly.
- The discovery document advertises no RP-initiated or channel logout. OTS logout therefore cannot end the Clerk session through a discovered endpoint. What remains active upstream was observed later; see [OTS logout with the Clerk session still active](#ots-logout-with-the-clerk-session-still-active).
- Clerk advertises the RFC 9207 `iss` authorization-response parameter. The installed strategy does not check it; this is a note, not a blocker.

### OAuth application observed in the dashboard

An OAuth application named "OTS platform OIDC development spike" already exists on this instance (created 2026-10-12). Non-secret configuration as displayed:

- **Public:** off (confidential client).
- **Consent screen:** on.
- **Device authorization grant:** off.
- **Scopes granted:** `email`, `offline_access`, `openid`, `profile`. OTS requests only `openid email profile`; `offline_access` is granted but unused.
- **Redirect URI:** `https://dev.onetime.dev/auth/sso/oidc/callback`. This matches the URI OTS builds for platform sign-in on a `HOST=dev.onetime.dev`, `SSL=true` installation (`Auth::PublicHost.required_base_url!` plus the strategy callback path).

During the live run the operator approved regenerating the client secret in the dashboard. It was copied with the dashboard's copy button and appended from the clipboard to the operator's local, uncommitted environment file. Its value does not appear in this record.

## Live sign-in results (2026-10-12)

Setup: the OTS `main` checkout @ `3c45bb6dd5` ran via `bin/dev` with `HOST=dev.onetime.dev`, `SSL=true`, `AUTHENTICATION_MODE=full` and `AUTH_SSO_ENABLED=true`. Entra and GitLab platform providers were also configured. The local configuration added `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_DISPLAY_NAME=Clerk`, `OIDC_TRUST_EMAIL_FOR_LINKING=false` and, after CLERK-07, `SSO_FORM_ACTION_ORIGINS=https://unified-parrot-698.accounts.dev`. Browser: Chrome. Mail went to a local Mailpit.

Before the first sign-in, a token-endpoint request with a dummy authorization code and HTTP Basic client credentials returned `invalid_grant`, and the same request with a wrong secret returned `invalid_client`. The OAuth client therefore authenticates with `client_secret_basic`, the strategy default.

The sign-in page showed "Sign in with Clerk" alongside the Microsoft and GitLab buttons.

### First login

The Clerk user signed in through Clerk's GitHub social connection, not a `+clerk_test` address. Its email had no existing OTS account. Baseline: 8 SQL accounts, 0 `oidc` identities.

Observed, in order, in the auth log for one callback (`GET /auth/sso/oidc/callback`, 302, about 1.0 s):

- `omniauth_callback_start` with `provider: :oidc` and a `uid` of the form `user_…`.
- `omniauth_account_created` (account 9).
- Customer creation: `origin: sso_jit, verified: true, verified_by: sso, verification_hold: none`.
- `create-default-workspace`: an organization was created.
- The pre-login session was deleted (session rotation), then `login_success` and `session_sync_complete`.
- A `new_login_alert` email was queued and delivered to Mailpit.

Afterwards there were 9 accounts and 1 `oidc` identity. The identity row has `issuer = https://unified-parrot-698.clerk.accounts.dev` and a 32-character `uid` with the `user_` prefix, which is Clerk's subject format. The browser landed on the OTS dashboard, and later API requests authenticated as the new Customer.

The log shows no explicit `email_verified: false`; `verification_hold: none` is consistent with a verified or absent claim. Whether the token response carried an ID token, and so whether `verify_id_token!` ran, is not visible in these logs (see CLERK-04).

**Deviation from the proposed constraints:** this first-login run used the operator's real GitHub-linked identity, not a dedicated test identity. The operator chose this during the run.

### OTS logout with the Clerk session still active

Choosing Logout in OTS sent `POST /auth/logout`. The log shows `before_logout`, deletion of the session and `Logout complete`, and the browser returned to the anonymous home page. OTS made no request to Clerk, which matches the absent `end_session_endpoint`.

On the next "Sign in with Clerk", Clerk asked for no credentials and went straight to its consent screen. Consent is not remembered between authorizations for this application. The Clerk session therefore survives OTS logout, and the next OTS sign-in needs only a consent click.

The repeated consent screen comes from Clerk, not OTS. OTS's authorization request carries no `prompt` parameter, only `client_id`, `redirect_uri`, `response_type`, `scope`, `state`, `nonce` and the PKCE fields. The OAuth application has its **Consent screen** setting on, and in every run Clerk showed the screen again after an earlier **Allow** by the same user. Turning that setting off should send Clerk straight back to OTS, but that was not tested. It was left on deliberately, and the cancellation check depends on it. For comparison, outside this investigation and not verified here: Microsoft Entra ID records a user's or administrator's consent and normally does not ask again unless the application sends `prompt=consent`, which is why Entra sign-ins return without an interstitial.

### Cancellation

Choosing **Deny** on Clerk's consent screen returned to `/auth/sso/oidc/callback` with `access_denied`. OTS logged `omniauth_failure` with `error_type: :access_denied` and redirected to `/signin`, which showed "Sign-in was cancelled. You can try again whenever you're ready." The next request was anonymous (`user_id: nil`). Clerk logged `oauth_consent.denied`.

### Repeat login

After **Allow**, the browser reached the OTS dashboard as the same Customer. Account and identity counts were unchanged (9 accounts, 1 `oidc` identity, one account for the email), and the log shows `login_success` for account 9 with no account or Customer creation.

The callback URL carried an `iss` parameter equal to the issuer (RFC 9207). The installed strategy does not check it.

### Double callback on one consent click

During the repeat login, OTS received two callback requests 0.28 s apart. Both passed the state check, both logged `login_success` for account 9, two new sessions were created, and two `new_login_alert` emails went out. Chrome's network log for the tab shows one callback navigation. Clerk's application log shows two `oauth_authorization.granted` events (16:41:20 and 16:41:21) and two `oauth_token.created` events. That indicates two authorization codes, not one code redeemed twice. The consent screen received one automated click; why Clerk recorded two grants was not determined.

On the OTS side, both requests carried the same pre-login session and read `omniauth.state` and the PKCE verifier before either request removed them. Single use of the state slot is therefore not enforced between concurrent callbacks that share a session. Observed effects: an extra authenticated session that the browser does not hold, and a duplicate login alert. This is a non-blocking observation; no code was changed.

Clerk's `oauth_token.created` events list `scopes: "openid email profile offline_access"`, although OTS requested `openid email profile`. The application has `offline_access` enabled. The OTS sign-in logs do not show whether a refresh token was returned; the [ID-token verification probe](#id-token-verification-probe) shows Clerk issuing one to this client. The strategy does not use it.

### ID-token verification probe

OTS does not log whether the token response carried an ID token, so a separate authorization was run outside OTS. A scratchpad script generated its own `state`, `nonce` and S256 PKCE verifier. Chrome opened Clerk's authorize URL with those values, and the operator's existing Clerk session clicked **Allow**. The redirect went to the registered OTS callback while the browser held an authenticated OTS session.

OTS side: OmniAuth rejected the callback with `csrf_detected | Invalid 'state' parameter` and redirected to `/signin`. The existing session kept its handle and stayed authenticated as account 9. OTS did not redeem the code; the script redeemed it afterwards.

The script then redeemed the code with HTTP Basic client authentication and verified the result with the calls the strategy uses: `OpenIDConnect::ResponseObject::IdToken.decode` against the discovered JWKS, then `verify!(issuer:, client_id:, nonce:)`. Only pass/fail and non-secret values were printed.

| Check | Result |
| --- | --- |
| Token response keys | `access_token`, `expires_in`, `id_token`, `refresh_token`, `scope`, `token_type` |
| Token `scope` | `openid email profile offline_access`. `offline_access` was not requested, and a refresh token was issued. |
| ID token signature | RS256; `kid` matches the JWKS key; signature verified |
| `verify!(issuer, client_id, nonce)` | pass |
| `iss` / `aud` / `nonce` | exact issuer / `["YkRVCNNWDhHFFBpG"]` (array) / matches the value sent |
| `sub` | same `user_…` subject as the stored OTS identity |
| `email_verified` (ID token and UserInfo) | `true` (boolean) |
| ID-token lifetime (`exp − iat`) | 86400 s |
| UserInfo `sub` and `email` | match the ID token |
| Second redemption of the same code (sequential) | HTTP 400 `invalid_grant`; no tokens |

Conclusion, limited to what was observed: Clerk issues a verifiable ID token to this client for the `openid` scope, and the installed strategy verifies an ID token whenever one is present (CLERK-04). That the earlier OTS sign-ins received and verified an ID token is an inference from this probe, not an observation from those sign-ins.

The probe's access and refresh tokens were not stored or used further.

### Replayed callback without a session

Requesting the already-used 16:41 callback URL again without cookies returned 302 to `/signin?auth_error=…`. OTS logged `csrf_detected | Invalid 'state' parameter`, wrote no `login_success`, and set only a new anonymous session cookie.

### Existing-email collision

Setup: OTS account 8 for `clerk-b+clerk_test@solutious.com` was created beforehand with `bin/ots customers create`. It is verified, has a generated password and has no linked identity. On the Clerk side, the instance session was signed out first. Signing out of `dashboard.clerk.com` does not sign out of the instance; a sign-in attempt in between went through the still-active instance session. "Sign in with Clerk" was then clicked from the OTS sign-in page; on Clerk's page the operator chose **Sign up** with that `+clerk_test` address and allowed consent. Baseline: 9 accounts, 1 `oidc` identity, account 8 with no identities.

Observed for one callback (`GET /auth/sso/oidc/callback`, 302, about 1.0 s):

- `omniauth_callback_start` with `provider: :oidc` and a new subject, `user_…od58`.
- `omniauth_link_challenge_issued` (warning level) with the exact issuer.
- A redirect to the `/link-sso/<token>` interstitial. It reads: "You signed in with OpenID Connect, which matches the existing account clerk-b+clerk_test@solutious.com. Enter that account's password to link OpenID Connect and continue." It offers a password field, **Link and continue** and **Cancel**.
- No `login_success`, no account creation and no identity row. Afterwards: 9 accounts, 1 `oidc` identity, account 8 still with no identities.

Implementation reference, not a project claim: the challenge branch in [the OmniAuth hooks](../../../apps/web/auth/config/hooks/omniauth.rb) (lines 299–324) mints a challenge only on the platform surface and only when the located account has a password. The challenge is single-use and expires after 300 s (`SsoLinkChallenge::DEFAULT_EXPIRATION`). This run's challenge was left to expire unused, because account 8's generated password was never displayed.

Not exercised: submitting the interstitial (correct password, wrong password, **Cancel**), the mailbox-proof branch for accounts without a password, and auto-linking with `OIDC_TRUST_EMAIL_FOR_LINKING=true`.

Non-blocking usability note: the sign-in button uses the configured `OIDC_DISPLAY_NAME` ("Sign in with Clerk"), but the interstitial names the provider "OpenID Connect". [LinkSso.vue](../../../src/apps/session/views/LinkSso.vue) (lines 56–60) resolves the label with `providerLabel()`, not the operator `display_name`; its comment gives the reason as backend display-name defaults that would read wrongly in that sentence. A self-hoster who labels the slot "Clerk" will see both names in one sign-in. After linking, the Connected Identities list also names the identity "OpenID Connect", while its connect button read "Connect Clerk".

Non-blocking defect, not specific to Clerk: during the run the "Sign in with Clerk" button rendered with no icon. At the tested revision, [SsoButton.vue](../../../src/apps/session/components/SsoButton.vue) fell back to `heroicons` / `solid-building-office` for route names it did not map, including `oidc`. That resolves to the sprite id `heroicons-solid-building-office`. The sprite sources under `src/shared/components/icons/sprites/` define `heroicons-building-office` and `heroicons-building-office-16-solid` but not that id, and the live document (checked on the dashboard page, which shares the sprite) had no element with it. Every generic OIDC button was affected. The component's unit spec stubs the icon component, so it did not catch the missing symbol. Fixed alongside this document: the fallback is now `building-office-16-solid`, the mapping lives in [ssoProviderIcons.ts](../../../src/sources/ssoProviderIcons.ts), and a spec checks every entry against the sprites.

### Explicit linking

Account 8's password was generated at creation and never shown, so the operator set a new one through OTS's own forgot-password flow (reset link delivered to Mailpit) and signed in as account 8 with it. The linking path used was the authenticated connect flow, not the collision interstitial.

From Connected Identities ("Connect Clerk"), as account 8:

- `POST /auth/sso/oidc` 302 from account 8's session. No `omniauth_connect_reauth_required` was logged; the password sign-in was about 70 s earlier.
- Clerk skipped credentials (B's Clerk session was active) and showed consent; the operator clicked **Allow**.
- One callback: `omniauth_callback_start` with B's subject, then `omniauth_identity_connected` with `provider: :oidc`, the exact issuer and `account_id: 8`, then session rotation, `login_success` for account 8 and a `new_login_alert`.
- Afterwards: 9 accounts, 2 `oidc` identities; account 8 has one, with the exact issuer and subject `user_…od58`. Connected Identities lists it with that issuer and a masked identifier.

Repeat sign-in after linking: after OTS logout, "Sign in with Clerk" went from Clerk's consent screen to one callback that logged `login_success` for account 8. There was no link interstitial and no new account or identity row. The consent screen stayed open about 30 minutes before **Allow**, and the flow still completed.

Not exercised: unlinking ("Remove"), and linking when the reauth window has lapsed (`omniauth_connect_reauth_required` path).

## Live experiment prerequisites

The Clerk Frontend API/issuer URL and the OTS canonical browser origin are recorded above. A live authorization-code exchange additionally needs the Clerk OAuth application configured as follows (the existing application matches):

- Confidential client, not a public SPA client.
- Granted scopes: `openid`, `email`, `profile`.
- Consent retained. OTS always sends S256 PKCE (`pkce: true`). The dashboard has no separate "PKCE required" switch for a confidential client; its PKCE text appears under the **Public** option.
- Redirect URI matching the OTS canonical origin followed by `/auth/sso/oidc/callback` when retaining the default route name.
- Client ID and secret supplied to the server through the operator's local secret/configuration mechanism, not committed or pasted into the investigation record.

Relevant existing OTS settings are `AUTHENTICATION_MODE=full`, `AUTH_SSO_ENABLED=true`, `OIDC_ISSUER`, `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET`. `OIDC_DISPLAY_NAME=Clerk` can label the provider without changing its route identity. `OIDC_TRUST_EMAIL_FOR_LINKING=false` preserves the conservative initial linking setup. `SSO_FORM_ACTION_ORIGINS` must include the Clerk Account Portal origin (`https://unified-parrot-698.accounts.dev` for this instance), or sign-in stalls for a signed-out browser (CLERK-07). These settings were applied to the operator's local, uncommitted environment for the live run; no committed configuration was changed.

The default generic OIDC slot must be free in the test installation or explicitly allocated to this experiment. Existing generic OIDC configuration must not be silently overwritten. No organization/domain SSO switch is required merely to evaluate platform sign-in.

## Remaining acceptance evidence

| Area | Status |
| --- | --- |
| Actual discovery endpoint, metadata and issuer | Observed live; compatible at discovery level |
| Confidential-client token exchange and callback matching | Observed: `client_secret_basic` accepted; callback on the registered URI succeeded |
| ID-token signature/issuer/audience/nonce, UserInfo and subject agreement | Observed in a separate probe; not visible in OTS logs |
| First login and workspace provisioning | Observed: account, identity, Customer and workspace created; session established |
| Repeat login without duplicate identity | Observed: same account and identity; no new rows |
| Existing-email collision | Observed: held at the password link interstitial; no identity, no session, no auto-link |
| Explicit linking | Observed: authenticated connect bound B's identity to account 8; the next Clerk sign-in resolved to account 8 |
| Cancellation and rejected callback behavior | Observed: `access_denied` and replayed `csrf_detected` both end without a session |
| OTS logout with Clerk session still active | Observed: OTS session ends; Clerk session persists; next sign-in skips credentials, shows consent |
| Configuration-only versus code-change outcome | Configuration-only, with `SSO_FORM_ACTION_ORIGINS` required (interpretation; see [Assessment](#assessment)) |

## Assessment

This section is the investigation's interpretation of the evidence above, not a project claim.

**Classification (acceptance criterion 7): configuration-only compatibility, with one required setting.** Every in-scope flow worked against the installed strategy and the unchanged OTS code. Beyond the generic OIDC variables, a signed-out browser needs the Clerk Account Portal origin in `SSO_FORM_ACTION_ORIGINS` (CLERK-07). Without it, Chrome blocks the redirect chain and sign-in stalls. That override is documented for a different purpose, so a self-hoster guide for Clerk needs to name it explicitly.

Acceptance criteria against the evidence:

| Criterion | Result |
| --- | --- |
| 1. Instance, revision, dependencies, configuration, callback | Recorded: development instance, `main` @ `3c45bb6dd5`, the three gem versions, non-secret settings, registered redirect URI |
| 2. Discovery, issuer, PKCE, client authentication, claims | Observed compatible. OTS sends S256 PKCE; whether Clerk rejects a missing or wrong verifier was not tested |
| 3. First and repeat login | Observed; no duplicate provisioning |
| 4. Collision and explicit linking | Observed: collision held for a password link; explicit link via connect; trust for email linking disabled throughout |
| 5. Cancellation, failed callbacks, state/nonce | Observed: `access_denied`, cookie-less replay and foreign `state` all end without a new session. A nonce mismatch through OTS was not exercised |
| 6. Logout with an active Clerk session | Observed: OTS session ends; Clerk session persists; the next sign-in needs only a consent click |
| 7. Classification | Configuration-only, with `SSO_FORM_ACTION_ORIGINS` (interpretation) |

Limits of this result:

- Development instance only. A production instance was not examined, and its issuer and Account Portal origins were not checked. If they differ from the development hosts, as expected but unverified, `OIDC_ISSUER`, the redirect chain and the `form-action` origin need their own check.
- The first login used the operator's real GitHub-linked identity (see the deviation note).
- Clerk grants `offline_access` and issues a refresh token although OTS requests neither; OTS does not use it. Removing `offline_access` from the application's scopes would avoid issuing unused refresh tokens.
- After OTS logout, the Clerk session lets anyone at that browser sign back in with one consent click. OTS has no endpoint through which to end the Clerk session. Signing out of the Clerk dashboard does not sign out of the instance.
- Not exercised: Clerk-side PKCE enforcement, a callback without an ID token, nonce mismatch, wrong password or **Cancel** at the link interstitial, the passwordless mailbox-proof link, `OIDC_TRUST_EMAIL_FOR_LINKING=true`, unlinking, and email change or user deletion at Clerk.

OTS-side observations from the run, none specific to Clerk and none blocking: the shared state slot is not single-use under concurrent callbacks; generic OIDC screens name the provider "OpenID Connect" rather than the configured display name; and the generic OIDC button had no icon (fixed alongside this document).

## Run artifacts left in place

The live run left the following in place. Nothing has been removed yet; the operator decides what to keep.

- **Local OTS configuration:** the Clerk block in the operator's uncommitted environment file occupies the generic OIDC slot and holds the regenerated client secret. `SSO_FORM_ACTION_ORIGINS` widens `form-action` for the whole process.
- **OTS development data:** accounts 8 (`clerk-b+clerk_test@solutious.com`) and 9 (the GitHub-linked identity), their `oidc` identity rows, Customers and workspaces. Account 8 has an operator-set password. Account 9 also has a password, from a reset on that account during the run.
- **Clerk instance:** two users, the GitHub-linked user and `clerk-b+clerk_test@solutious.com`. The OAuth application's client secret was regenerated during the run.
- **Clerk tokens:** the ID-token probe's access and refresh tokens were not revoked. OTS sign-ins probably also received refresh tokens (see the `offline_access` note); OTS discards them, but Clerk may still treat them as valid.
- **Local tooling:** the `bin/dev` process, browser sessions (including an active Clerk session for the `+clerk_test` user), Mailpit messages and the probe script in a session scratchpad outside the repository.
