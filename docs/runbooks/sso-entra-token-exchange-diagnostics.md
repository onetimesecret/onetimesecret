# SSO: Entra token exchange diagnostics (draft)

Separated implementation notes for the [AADSTS7000215 runbook](./sso-entra-invalid-client-secret.md).
That runbook defines the stored-credential A/B tests, isolated strategy test C,
and live UI procedure referenced below. Use an initialized `bin/console` with
`domain` already loaded for the console probe.

## Operator diagnostic: registered strategy's HTTP client

**Runs on:** production `bin/console` in the affected deployment. Contacts Microsoft with the stored secret. Read-only. Neither the probe nor the observer writes to the operator security audit trail; record who ran it, for which domain, and when in the support ticket, as the [Entra runbook](./sso-entra-invalid-client-secret.md#where-each-procedure-runs) asks.

The [opt-in token exchange diagnostic](../../scripts/diagnostics/entra_token_exchange.rb)
adds a comparison using the **registered** Entra middleware's options rather than
constructing a new strategy. In the same initialized `bin/console`, run:

```ruby
require File.join(Onetime::HOME, 'scripts/diagnostics/entra_token_exchange'); nil
EntraTokenExchangeDiagnostic.probe(domain: domain); nil
```

This reloads the persisted record, clones the registered strategy, calls the real
`inject_tenant_credentials` helper (including `merge_strategy_options`), and uses
`EntraId#client` → `OAuth2::Client#client_credentials` to request one token. It does
not overwrite the registered strategy or save SSO settings. Its HTTP timeout is
30 seconds, with a 10-second connection timeout. It prints sanitized JSON, not
the returned token or raw exception message. Keep HTTP debug logging disabled.

- `access_token_present: true` in the response means the registered client's
  credential transport works for the client-credentials grant in this process.
- A failure here when stored curl B succeeds isolates a difference introduced by
  strategy options, tenant injection, the gem's HTTP client, or process/network
  configuration. Check the request metadata before changing the stored record.
- This still does **not** run browser authorization, OAuth state validation,
  host-resolution middleware, or account/login hooks. For that evidence, use the
  [authorization-code diagnostic](./sso-entra-invalid-client-secret.md#operator-diagnostic-real-entra-strategy-and-authorization-code-exchange)
  or observe a normal UI callback.

## Install the observer in the serving web workers

**Runs on:** the production web workers, as a temporary diagnostic deployment with operator approval. Not a console procedure. The regression coverage at the end of this document is the only part that runs in a development checkout.

The [diagnostic helper](../../scripts/diagnostics/entra_token_exchange.rb) supplies
step 4's instrumentation in the [live UI procedure](./sso-entra-invalid-client-secret.md#close-the-remaining-gap-reproduce-on-the-live-ui-request).
Loading it in `bin/console` only affects that console; it cannot inspect another
worker's in-memory strategy.

With operator approval, deploy the helper alongside the affected application's
build. Temporarily add the following **after**
`Onetime::Application::Registry.prepare_application_registry` in
[`config.ru`](../../config.ru), replacing both placeholders with the existing
domain identifier and public hostname. Neither placeholder is a credential.
Do not alter the tenant SSO record, provider registration, or authentication scheme.

```ruby
require_relative 'scripts/diagnostics/entra_token_exchange'
EntraTokenExchangeDiagnostic.observe!(
  domain_id: '<existing domain identifier>',
  host: '<affected public hostname>'
)
```

Apply this to every replica that might handle the callback. Activating the observer
requires a controlled worker reload; capture the failing release, bundle, and
configuration first. This is a diagnostic deployment, not a proposed restart fix.
Use the authorized test account to start a **fresh normal UI sign-in**. The browser
and application handle the code and state normally: no code copying, replay, state
bypass, or second token exchange is needed.

The observer wraps the normal `build_access_token` call and appends read-only
Faraday middleware after the existing request encoders, just before the HTTP
adapter. It compares the outgoing request with a fresh persisted credential read,
then reports the response from **that same exchange**. It does not change the
request, swallow the OAuth error, or perform an additional token request. The
console probe and observer report these fields:

| Field | Interpretation |
|---|---|
| `mode`, `pid`, `probe_id` | Distinguish console versus browser exchange and correlate request/response lines within a worker. |
| `tenant_config_in_request` | Browser: the tenant setup hook left a config for the expected domain in this request. Console: the explicit injection helper ran. |
| `token_endpoint_matches_stored` | The final token URL matches the persisted tenant's standard Entra v2 token endpoint. |
| `authorization_scheme` | `basic`, `none`, or `other`; no header value is emitted. Expected `none` on a build with #4764, which sends the credentials in the body. `basic` means the worker runs a release up to v0.26.16. |
| `raw_basic_matches_stored` | The outgoing Basic header matches the exact stored client ID/secret pair, without form-encoding. Expected `false` on a build with #4764; `true` identifies an older build that still sends the header. |
| `form_encoded_basic_matches_stored` | The header matches that pair with each component form-encoded before Base64. Both comparisons can be true when encoding changes neither component. Expected `false` on a build with #4764. |
| `body_client_id_present`, `body_secret_present` | Whether the encoded request body contains those fields. Expected `true` on a build with #4764. |
| `body_client_id_matches_stored`, `body_secret_matches_stored` | Whether those decoded body fields equal the persisted credentials. Expected `true` on a build with #4764: the stored pair reaches the wire byte for byte. |
| `authorization_code_grant`, `client_credentials_grant`, `code_present`, `code_verifier_present` | Request shape only; code and verifier values are never emitted. |
| `redirect_uri_matches_expected` | Whether the body uses the configured domain's HTTPS callback and provider route. Expected false for a client-credentials probe, which has no redirect URI. |
| `http_status`, `access_token_present`, `aadsts_code` | Microsoft's response status, token presence, and AADSTS code; no token or error description is emitted. |

Interpret the browser result against stored A/B and the registered-client probe:

- **UI reports 7000215 with `authorization_scheme: "none"` and both body matches
  true:** the worker sent the stored pair in the body, byte for byte, as a build
  with #4764 does. The Basic-header encoding gap is not the cause. Investigate
  leads 1 and 2 in the Entra runbook (a deleted or replaced secret, or the
  Secret ID saved instead of the Value).
- **UI reports 7000215 with `authorization_scheme: "basic"`:** that worker runs a
  release up to v0.26.16, which sends the Basic header. Compare its deployed
  release with the one expected before reading further.
- **UI reports 7000215 and no credential representation matches:** the outgoing
  credentials differ from the persisted pair, or another authentication method is
  in use. Investigate the active strategy/options and worker configuration.
- **UI reports 7000215, the credential representation matches, and the token URL
  and redirect URI match:** reproduced with the same stored credentials through
  the real sign-in exchange. Client-credentials success does not establish
  authorization-code success; investigate grant-specific request/Entra context.
  This does not by itself prove the Basic encoding hypothesis.
- **No observer request line:** first check replica coverage and diagnostic setup.
  The flow may have been rejected before token redemption or resolved to another
  host; absence is not evidence that Microsoft accepted or rejected the secret.
- **`observer_failed`, `probe_failed`, or `exception`:** only an exception class is
  reported. Local/transport failure is not an AADSTS result. Diagnostic setup or
  output failures do not replace the normal sign-in outcome.

Disable the observer by removing the temporary boot lines and reloading all
workers after the agreed window. `EntraTokenExchangeDiagnostic.stop!` disables
future observation only in the process where it is called; it does not affect
other replicas or an exchange already in progress. The helper is not loaded by
default. It drops no credentials from persistent storage and provides no secure
memory-erasure guarantee. Keep raw HTTP logging, HAR export, and session recording
disabled throughout.

Until request-level evidence exists, record **“stored A/B and isolated strategy
succeed; UI failure not yet isolated”**, rather than claiming the secret is wrong
or that the implementation is ruled out. Preserve the record while collecting
this evidence; change transport or rotate credentials only afterwards as a
separately verified fix.

## Regression coverage

The [mounted Entra integration spec](../../apps/web/auth/spec/integration/full/entra_native_claims_spec.rb) includes diagnostic examples for the registered-client probe and a browser callback returning a mocked 7000215. Since #4764 both expect `authorization_scheme: "none"`, `raw_basic_matches_stored: false`, and `body_client_id_matches_stored` and `body_secret_matches_stored` true, and every code exchange in the spec asserts that `client_id` and `client_secret` travel in the form body, byte for byte equal to a stored secret that contains `+` and `%`, with no `Authorization` header. The [diagnostic unit spec](../../spec/unit/auth/entra_token_exchange_diagnostic_spec.rb) checks credential comparisons, output redaction, and preservation of the token request and OAuth error. These tests use a mocked endpoint; they do not prove Microsoft accepts a production credential.
