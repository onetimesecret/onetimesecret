# SSO: keeping tenant credentials healthy

How to keep a custom domain's SSO configuration (OIDC, Entra ID, SAML) working
between setup and the next failed sign-in. For diagnosing one Entra failure,
see [sso-entra-invalid-client-secret.md](./sso-entra-invalid-client-secret.md).

## No single "credentials valid" check

OAuth 2.0 and OIDC define no endpoint for validating a client credential and no
monitoring schedule. Each check below establishes one thing, and none of them on
its own shows that sign-in works. Track them separately, not as one `valid`
flag.

Microsoft asks for the same kind of ongoing review of app registrations. Its
[security best practices for app registrations](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration)
say: "Conduct a periodic security and health assessment of applications, much
like a Security Threat Model assessment for code." and "Review the credentials
used in applications for freshness of use and their expiration."

## Checks

| Check | What it establishes | When | What Onetime Secret has today |
|---|---|---|---|
| **Stored configuration** | The saved record loads, decrypts, and has the required fields. | After every save, deploy, or encryption-key rotation; periodically. | `SsoConfig#validation_errors`. A value that fails to decrypt is reported as missing (`client_secret is required`). Check saved configuration (below) reloads the record and runs it as the `stored_configuration` check when an admin clicks it. Nothing runs it across domains, from the CLI or on a schedule. |
| **Discovery** | The IdP is reachable and its discovery document is usable. Says nothing about the secret. | Periodically, cached. | Test Connection fetches discovery for `oidc` and `entra_id` from the form values and compares the OIDC issuer exactly. It also reports the document's `token_endpoint_auth_methods_supported`, and for `oidc` warns when the selected token endpoint auth method is not advertised (#4764). Check saved configuration runs the same fetch (`DiscoveryCheck`) from the stored issuer or tenant ID as its `discovery` check, and reports an unreachable IdP as `inconclusive` rather than failed. Both run only when an admin clicks them. |
| **Credential expiry** | A secret or certificate needs rotating soon. | Daily is a reasonable start. | SAML: the record reports `cert_expires_at` / `cert_expired`, the form shows an "expiring soon" notice inside 30 days, and Test Connection and Check saved configuration (`certificate` check) report days left. No one is notified unless they open the form. Entra and OIDC client secrets: the expiry date lives in the customer's tenant, and we never see it. An Entra secret that has already expired is reported by Check saved configuration as `client_secret_expired` (AADSTS7000222). |
| **Admin-triggered test** | Whatever that test actually exercises. | Setup, rotation, troubleshooting. | Test Connection (form values) and Check saved configuration (stored record, with an Entra credential check). See the next two sections for what each covers. |
| **Real sign-ins** | Code exchanges and SSO sign-ins succeed or fail. | Continuously. | Auth log events: `omniauth_tenant_credentials_injecting` (has `domain_id`) and `omniauth_failure` (has `error_type` and `error_message`, no `domain_id`). There is no per-domain count of successes or failures. |

An optional **synthetic browser sign-in** exercises the whole path: redirects,
token exchange, claims, and session creation. It needs a dedicated, restricted
test identity in the customer's tenant, set up with the customer and within
their MFA and Conditional Access policies. Don't ask for an MFA bypass for
monitoring.

## What Test Connection does not cover

From `apps/api/domains/logic/sso_config/test_connection.rb`:

- **It tests the form, not the saved record.** It reads the provider fields from
  the request body so admins can test before saving. A passing test therefore
  says nothing about what was stored or whether it decrypts.
- **It never uses the client secret.** The request's `client_secret` isn't read.
  A wrong, expired, or mis-encoded secret passes. The token endpoint auth
  method check (#4764) compares the selection with the discovery document; it
  sends nothing to the token endpoint.
- **SAML is checked locally.** The IdP isn't contacted.

After a customer saves or rotates a secret, Check saved configuration can
tell whether Entra accepts it; only a real sign-in confirms sign-in works.

## What Check saved configuration covers

`POST /api/domains/:extid/sso/diagnostics`
(`DomainsAPI::Logic::SsoConfig::RunDiagnostics`,
`apps/api/domains/logic/sso_config/run_diagnostics.rb`) reloads the saved
record and reports one check per layer, each `passed`, `failed`,
`inconclusive`, `unsupported` or `skipped`, plus an `overall` verdict
(`failed` if any check failed, else `inconclusive` if any is inconclusive,
else `passed`; `unsupported` and `skipped` do not count).

- `stored_configuration` (all providers): the record reloaded and
  `SsoConfig#validation_errors`. When it fails, the later checks are
  `skipped`.
- `discovery` (`oidc`, `entra_id`): the same fetch Test Connection does,
  from the stored issuer or tenant ID. An IdP that cannot be reached
  (timeout, connection failure, TLS error) is `inconclusive`, not evidence
  about the configuration.
- `certificate` (`saml`): the stored IdP certificate's validity window,
  checked locally.
- `credential` (`entra_id`): one client-credentials token request with the
  stored client ID and secret (`Onetime::SsoProvider::EntraCredentialProbe`,
  `lib/onetime/sso_provider/entra_credential_probe.rb`). It sends the secret
  the way sign-in does (token request body, `auth_scheme: :request_body`;
  a spec pins the probe's scheme to `SsoConfig#build_entra_id_options`).
  `passed` means Entra accepted the saved secret for that request and
  nothing more; see the next section. AADSTS7000215 is reported as
  `invalid_client_secret`, AADSTS7000222 as `client_secret_expired`,
  AADSTS700016 as `app_not_found_in_tenant`; any other AADSTS code is
  `inconclusive` with the bare code. A stored secret shaped like a UUID is
  flagged (`secret_shape: uuid`): that is the Secret ID, not the Value.
  For `oidc` this check is `unsupported`: OIDC does not guarantee the
  client-credentials grant, and we cannot know a scope to ask for.

The response never carries the secret, a token, or Entra's
`error_description` (it holds correlation IDs and the app ID). One log line
records the domain, provider, overall and per-check statuses. No audit
event is written (see item 7 below).

The endpoint is not rate limited beyond the session. That is a known gap,
not an oversight: every run sends the stored Entra secret to Microsoft, and
a loop of runs with a wrong secret can trip Entra's own throttling for the
customer's app registration. No reusable per-customer limiter exists to
apply. Each `lib/onetime/security/*_rate_limiter.rb` module is bound to one
subject type and key prefix (IP, email, secret ID, domain ID, or a colonel
extid under the colonel config and audit trail), and
`Onetime::Operations::RateLimit::Registry::LIMITERS` lists only those;
`DnsRateLimiter` is per domain at 100 per hour on a bucket shared with DNS
verification. A dedicated per-customer limiter (about 10 runs per hour)
registered in that registry is the follow-up.

## A client-credentials request is not an SSO test

Microsoft describes the client credentials grant as one that "permits a web
service (confidential client) to use its own credentials, instead of
impersonating a user, to authenticate when calling another web service."
([client credentials flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow)).
Our sign-in uses the authorization code grant. Both send the secret to the same
token endpoint, but the grant, the permission model, and what the token is for
differ.

- A fresh token shows the secret was accepted for that request.
- AADSTS7000215 (invalid) and AADSTS7000222 (expired) are about the secret.
  Any other error, such as an unsupported grant, an invalid scope, or a policy
  refusal, says nothing about whether the secret is right.
- Success doesn't prove that redirect URIs, user assignment, MFA, or claims
  mapping work.
- A cached token doesn't test the current secret. We don't cache tokens today;
  any future probe must request a fresh one.
- SAML needs different checks: metadata, certificate validity and rotation, and
  a real assertion flow.

**Don't ask a customer to grant Microsoft Graph permissions so a probe
succeeds.** The isolation test in the Entra runbook requests
`https://graph.microsoft.com/.default` and needs no granted permission.
Microsoft says: "Microsoft Entra ID doesn't require that applications be
authorized to get tokens for another application. Thus, app-only tokens can be
issued without a `roles` claim."

Keep that isolation test's A/B comparison as an on-demand diagnostic. Routine
checks test the configured way of sending the secret, not alternatives. For
Entra that is the token request body; for generic OIDC it is the selected
token endpoint auth method, or the default when none is selected (#4764).

## Procedures with the current tools

**Runs on:** production, by an operator, using the log store and the customer's SSO settings page. No console commands.

1. **A customer rotates a secret (Entra, OIDC).** Ask them to add the new secret
   in their tenant before removing the old one, save the new Value in the
   domain's SSO settings, and sign in once on the custom domain. Then remove the
   old secret. In the logs: `domain_sso_config_updated` with
   `client_secret changed: true`, then `omniauth_tenant_credentials_injecting`
   for that `domain_id` with no `omniauth_failure` after it.
2. **Secret expiry (Entra, OIDC).** We can't see it. Ask the customer to set a
   reminder before the secret's expiry date. An expired secret that is still
   listed on the app returns AADSTS7000222.
3. **SAML certificate expiry.** The form warns 30 days ahead, but only when
   someone opens it. Ask the customer to watch the IdP certificate's expiry and
   save the new certificate before the old one expires.
4. **A sign-in fails at token exchange.** `omniauth_failure` with
   `error_type=invalid_credentials` after a tenant injection line: follow
   [sso-entra-invalid-client-secret.md](./sso-entra-invalid-client-secret.md).

## Proposed (not built)

Nothing in this section exists in the codebase, except where an item says so.

1. **Test the saved configuration.** Built for Entra as Check saved
   configuration (above). The probe reloads the record through the same
   decryption sign-in uses and sends the secret with the same
   `auth_scheme` (`:request_body`, #4764), pinned in spec against
   `SsoConfig#build_entra_id_options`. It does not run through
   `inject_tenant_credentials` and the OmniAuth strategy (those need a Rack
   request); it builds the `OAuth2::Client` the way the strategy does. A
   probe with a different transport would have missed the Basic-header
   encoding gap in the Entra runbook, which is why the scheme is pinned.
   Also done: the matching `token_endpoint_auth_method` option for generic
   OIDC, per domain under Advanced in the SSO form and as
   `OIDC_CLIENT_AUTH_METHOD` for the platform provider (#4764). Still
   proposed: a credential check for generic OIDC (none is safe without a
   known scope) and for SAML (needs a real assertion flow).
2. **Report each layer separately:** local integrity, provider reachability,
   credential acceptance, completed sign-in. Built for the first three as
   the per-check response of Check saved configuration. Still proposed:
   completed sign-in (item 4).
3. **Background checks** for integrity, discovery, and SAML expiry. Token probes
   only where the provider supports a suitable, authorized request (Entra client
   credentials, as above).
4. **Per-domain sign-in outcomes.** Needs `domain_id` on `omniauth_failure` for
   tenant callbacks.
5. **Customer-entered secret expiry date** for Entra and OIDC, used only for
   reminders. It's the only way we learn the date without a Graph permission.
6. **Store observations, not a flag:**

   ```text
   check_type
   configuration_revision
   checked_at
   last_success_at
   status: passed | failed | inconclusive | unsupported
   failure_category
   provider_error_code
   ```

   Tie each result to the configuration revision so a job that finishes late
   can't mark a freshly rotated secret as failed. The record's `updated` field
   (set on PUT and PATCH) is a candidate, but it has one-second resolution, so
   two saves in the same second share a value.

7. **Audit every production diagnostic.** The console procedures in the
   [Entra runbook](./sso-entra-invalid-client-secret.md#where-each-procedure-runs)
   and the [token exchange diagnostic](./sso-entra-token-exchange-diagnostics.md)
   decrypt a tenant's credentials and send them to the IdP, and leave no record
   in the operator security audit trail. Wrap them as named operations that
   write one `Onetime::ColonelAuditEvent.record_security` entry each: actor,
   verb (the procedure name), target (the domain ID), result (the marker:
   token, AADSTS code, or local failure class), and a detail hash with the
   UTC time and the probe identifier. Never the credential, the token, or the
   raw error. Check saved configuration (item 1) uses the stored secret and
   writes no such entry yet; it and any background check (item 3) should
   write the same entry.

Safeguards for any background probe:

- Enqueue the domain ID, never the secret.
- Use timeouts, bounded retries with jitter, and per-IdP rate limits.
- Send outbound requests through the same SSRF guard discovery uses
  (`Onetime::SsoProvider::DiscoveryFetcher`, `Onetime::Http::Guard`).
- Redact request and response logs.
- Never disable SSO or switch the authentication method because a probe failed.
  Notify instead.
