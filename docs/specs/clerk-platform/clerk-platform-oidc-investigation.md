# Clerk platform OIDC investigation results

Related scope: [Clerk platform OIDC compatibility spike](clerk-platform-oidc.md).

## Status

**Partial investigation; live compatibility blocked on instance configuration.** No Clerk login, token exchange or production-support claim is established. No application authentication code, installed dependencies or operator configuration was changed.

Source inspection baseline: `fba1dd2623c299a5f0bd4c02952269b6f1991a8c`, 2026-10-12.

Inspected installed/locked dependencies:

- `omniauth_openid_connect` 0.8.0
- `openid_connect` 2.5.0
- `rack-oauth2` 2.3.0

## Findings and dispositions

These findings are source/documentation observations, not observations of a live Clerk instance. No finding authorizes weakening existing checks.

| ID | Finding | Disposition |
| --- | --- | --- |
| CLERK-01 | OTS and its OIDC strategy request `/.well-known/openid-configuration`. Clerk documents `/.well-known/oauth-authorization-server`; its sample also omits `userinfo_endpoint`, which the strategy needs for UserInfo. | **Live blocker:** inspect the selected instance's actual discovery response before deciding whether configuration alone suffices. Do not infer that an undocumented endpoint is absent, or treat sample omissions as actual behavior. No fallback implementation proposed without evidence. |
| CLERK-02 | Configured issuer, discovery issuer and token issuer are checked for exact agreement. | **Configuration constraint:** use the exact advertised issuer, not the application website URL or discovery-document URL. Existing issuer rejection tests pass; Clerk issuer behavior remains untested. |
| CLERK-03 | The strategy defaults to HTTP Basic client authentication; omitting a client secret does not select authentication method `none`. Clerk's metadata example advertises `client_secret_basic` and `none`. | **Spike scope:** use a confidential OAuth application with client ID and secret. Public-client compatibility remains unverified and outside this first attempt. |
| CLERK-04 | The installed strategy generates S256 PKCE and a nonce. It also permits callback parameters to take precedence over stored nonce/verifier values, and skips ID-token verification if the response omits an ID token. State checking still applies. | **Unresolved validation caveat:** record actual Clerk ID-token issuance and nonce behavior; negative callback checks remain outstanding. These observations are not evidence of an end-to-end exploit or justification to relax checks. No dependency patch made. |
| CLERK-05 | The strategy merges UserInfo and ID-token claims, with ID-token claims taking precedence. Explicit false email verification differs from absent verification in OTS provisioning/linking logic. | **Live claim checks outstanding:** record subject/email/verification consistency and collision outcomes. Keep email auto-link trust disabled for the initial experiment. Conflicting Clerk claims have not been observed. |
| CLERK-06 | External identity uses provider route, issuer and subject. Route/issuer changes affect identity resolution; platform lookup also supports legacy issuerless rows. | **Experiment constraint:** use a dedicated test installation/identity set, retain a stable provider route, and avoid repurposing an existing provider's identities. First/repeat login and linking remain outstanding. |

Source entry points:

- [OIDC provider definition](../../lib/onetime/sso_provider/oidc.rb)
- [Discovery fetcher](../../lib/onetime/sso_provider/discovery_fetcher.rb)
- [Discovery issuer checks](../../lib/onetime/sso_provider/discovery_issuer.rb)
- [Platform/tenant setup hook](../../apps/web/auth/config/hooks/omniauth_tenant.rb)
- [Identity resolution and persistence](../../apps/web/auth/config/features/omniauth.rb)
- [Provisioning and email trust hooks](../../apps/web/auth/config/hooks/omniauth.rb)

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

## Live experiment prerequisites

The next input is the selected Clerk development instance's **public Frontend API/issuer URL** and the intended **OTS canonical browser origin**. Neither is inferable from the Clerk application ID alone.

With those values available, discovery can be checked without an OAuth client secret. A live authorization-code exchange additionally needs a Clerk OAuth application configured as follows:

- Confidential client, not a public SPA client.
- Granted scopes: `openid`, `email`, `profile`.
- PKCE required; consent retained.
- Redirect URI matching the OTS canonical origin followed by `/auth/sso/oidc/callback` when retaining the default route name.
- Client ID and secret supplied to the server through the operator's local secret/configuration mechanism, not committed or pasted into the investigation record.

Relevant existing OTS settings are `AUTHENTICATION_MODE=full`, `AUTH_SSO_ENABLED=true`, `OIDC_ISSUER`, `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET`. `OIDC_DISPLAY_NAME=Clerk` can label the provider without changing its route identity. `OIDC_TRUST_EMAIL_FOR_LINKING=false` preserves the conservative initial linking setup. These are setup requirements, not changes applied by this investigation.

The default generic OIDC slot must be free in the test installation or explicitly allocated to this experiment. Existing generic OIDC configuration must not be silently overwritten. No organization/domain SSO switch is required merely to evaluate platform sign-in.

## Remaining acceptance evidence

| Area | Status |
| --- | --- |
| Actual discovery endpoint, metadata and issuer | Awaiting public instance URL |
| Confidential-client token exchange and callback matching | Awaiting OAuth application and local configuration |
| ID-token signature/issuer/audience/nonce, UserInfo and subject agreement | Not tested live |
| First login and workspace provisioning | Not tested live |
| Repeat login without duplicate identity | Not tested live |
| Existing-email collision and explicit linking | Not tested live |
| Cancellation and rejected callback behavior | Not tested against Clerk |
| OTS logout with Clerk session still active | Not tested live |
| Configuration-only versus code-change outcome | Undetermined |

No final compatibility verdict is available until these blockers and checks are resolved.
