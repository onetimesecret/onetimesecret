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
| **Stored configuration** | The saved record loads, decrypts, and has the required fields. | After every save, deploy, or encryption-key rotation; periodically. | `SsoConfig#validation_errors`. A value that fails to decrypt is reported as missing (`client_secret is required`). Nothing runs it across domains, from the CLI or on a schedule. |
| **Discovery** | The IdP is reachable and its discovery document is usable. Says nothing about the secret. | Periodically, cached. | Test Connection fetches discovery for `oidc` and `entra_id` and compares the OIDC issuer exactly. Runs only when an admin clicks it. |
| **Credential expiry** | A secret or certificate needs rotating soon. | Daily is a reasonable start. | SAML: the record reports `cert_expires_at` / `cert_expired`, the form shows an "expiring soon" notice inside 30 days, and Test Connection reports days left. No one is notified unless they open the form. Entra and OIDC client secrets: the expiry date lives in the customer's tenant, and we never see it. |
| **Admin-triggered test** | Whatever that test actually exercises. | Setup, rotation, troubleshooting. | Test Connection. See the next section for what it does not cover. |
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
  A wrong, expired, or mis-encoded secret passes.
- **SAML is checked locally.** The IdP isn't contacted.

After a customer saves or rotates a secret, only a real sign-in confirms it.

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
checks test the configured way of sending the secret, not alternatives.

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

Nothing in this section exists in the codebase.

1. **Test the saved configuration.** After a save, reload the record and test
   through the same decryption and token-request code that sign-in uses
   (`SsoConfig#to_omniauth_options` → `inject_tenant_credentials` → strategy →
   `OAuth2::Client`, same `auth_scheme`). A probe with its own HTTP client would have missed the
   Basic-header encoding gap in the Entra runbook.
2. **Report each layer separately:** local integrity, provider reachability,
   credential acceptance, completed sign-in.
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
   raw error. Any future Test Connection probe or background check that uses
   the stored secret (items 1 and 3) should write the same entry.

Safeguards for any background probe:

- Enqueue the domain ID, never the secret.
- Use timeouts, bounded retries with jitter, and per-IdP rate limits.
- Send outbound requests through the same SSRF guard discovery uses
  (`Onetime::SsoProvider::DiscoveryFetcher`, `Onetime::Http::Guard`).
- Redact request and response logs.
- Never disable SSO or switch the authentication method because a probe failed.
  Notify instead.
