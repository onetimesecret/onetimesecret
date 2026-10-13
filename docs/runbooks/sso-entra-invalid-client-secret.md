# SSO: Entra AADSTS7000215 (invalid client secret)

**Symptom:** reported 2026-10-12 by a custom-domain customer using tenant
Entra ID SSO, after v0.26.16 fixed the v0.26.15 proxy-trust incident:

> Entra ID returns error AADSTS7000215 ("Invalid client secret provided")
> during the token exchange. The sign-in log also shows "Client credential
> type: None", which suggests the client secret is not being sent or not
> being read correctly after the update.

## Where each procedure runs

Every procedure below states where it runs. Nothing here is meant to be pasted into a production console unless its section says so.

| Section | Runs on | Contacts Microsoft | Reads the stored record |
|---|---|---|---|
| Isolation test | The customer's own machine | Yes, with the secret they type in | No |
| Operator diagnostic: persisted credentials through curl | Production `bin/console` in the affected deployment | Yes | Yes, read-only |
| Operator diagnostic: stored credential character and decoding checks | Production `bin/console` | No | Yes, read-only |
| Developer check: capture the actual outgoing credential transport | A development checkout, in the spec suite with synthetic credentials | No, mocked endpoint | No |
| Optional Entra comparison: raw Basic versus encoded Basic | Production `bin/console`, as a variant of the persisted-credential procedure | Yes | Yes, read-only |
| Operator diagnostic: real Entra strategy and authorization-code exchange | Production `bin/console` plus a browser | Yes, a real sign-in at the IdP | Yes, read-only |
| Close the remaining gap: reproduce on the live UI request | The production web workers, with a diagnostic deployment | Yes, a normal sign-in | Yes, read-only |

"Production" means the deployment the customer's domain is served from. A console on a staging host or a developer machine reads a different record and a different gem bundle, and proves nothing about the failing worker.

**Leave a trail.** Every production procedure in this runbook reads a tenant's decrypted credentials, and most send them to Microsoft. None of them writes to the operator security audit trail today (`Onetime::ColonelAuditEvent.record_security`, the trail the colonel audit export reads). Ideally each one would, with the operator, the procedure name, the domain ID, the UTC time and the marker result, and never the credential bytes. Until that exists, record the same facts in the support ticket before you start, and note in the ticket that the console session was not recorded. The proposal is item 7 in [sso-credential-health.md](./sso-credential-health.md#proposed-not-built).

## Release-history evidence

The source comparison below does not prove what a particular running worker sent.
If persisted-credential probes succeed but the UI fails, keep the implementation
and deployment context under investigation using the diagnostics below.

**Why I think so** (from reading the code at v0.26.14, v0.26.15 and v0.26.16, plus the gem source):

1. **Nothing in the secret's path changed between v0.26.14 and v0.26.16.** That path is `SsoConfig#build_entra_id_options` → `inject_tenant_credentials` / `merge_strategy_options` → omniauth-entra-id 3.1.1 `#client` → `OAuth2::Client`. The only changes to `sso_config.rb` in that range were the class reopen (#4220) and the IDN allowlist (#4736). No commits touched the save API or the form, and the omniauth, oauth2 and entra gem versions are the same.
2. **A missing secret can't reach Entra.** omniauth-entra-id raises `ArgumentError` when the secret is nil, so no token request is made. Saving an Entra config with a blank secret is rejected (PUT), or keeps the stored secret (PATCH).
3. **The error shows up under their app in their tenant.** This supports the expected client ID and tenant being used, but does not establish which secret bytes were sent or prove that credential injection completed. Confirm the tenant path on the actual callback rather than inferring it from the Entra event.
4. **The error code means a secret was sent.** Microsoft's "no credential sent" error is AADSTS7000218. [Their troubleshooting page](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/confidential-client-application-authentication-error-aadsts7000218) says it happens "because the application doesn't provide the credentials (client secret or assertion) that the token endpoint expects." AADSTS7000215 means a secret arrived and didn't validate. I found no Microsoft wording on what "Client credential type" shows for a rejected secret, so "None" doesn't show that nothing was sent.

## How Onetime Secret sends the secret

Nothing in our codebase describes Entra's "Client credential type" field. I searched tracked files on main, the history of every branch, the worktrees, and the sibling repos including docs.onetimesecret.com. The only matches are about WebAuthn and Stripe credential types.

What the codebase does answer is how we send the secret.

**We send the client ID and secret in the token request body, not in an `Authorization` header.** Both Entra builders set `client_options: { auth_scheme: :request_body }`: the platform registration in [`lib/onetime/sso_provider/entra.rb`](../../lib/onetime/sso_provider/entra.rb) (`placeholder_options` and `strategy_options`) and the custom-domain builder `SsoConfig#build_entra_id_options` in [`lib/onetime/models/custom_domain/sso_config.rb`](../../lib/onetime/models/custom_domain/sso_config.rb). The tenant hook merges `client_options` key by key (`OmniAuthTenant.merge_strategy_options`), so the key reaches the strategy next to the Entra URLs the strategy sets itself. This landed in [#4764](https://github.com/onetimesecret/onetimesecret/issues/4764). No operator configuration change is needed. Generic OIDC and SAML are unchanged.

With that option, oauth2 2.0.25 form-encodes `client_id` and `client_secret` into the body of the token request and sends no `Authorization` header. The [mounted Entra integration spec](../../apps/web/auth/spec/integration/full/entra_native_claims_spec.rb) pins that shape at a mocked endpoint, with a stored secret that contains `+` and `%`: the decoded body equals the stored pair, the secret is percent-encoded on the wire (`+` as `%2B`, `%` as `%25`), and the request carries no `Authorization` header. The [token exchange diagnostic](./sso-entra-token-exchange-diagnostics.md) reports a healthy exchange as:

```
authorization_scheme: "none"
raw_basic_matches_stored: false
body_client_id_matches_stored: true
body_secret_matches_stored: true
```

- Microsoft documents the body form in its [auth code flow reference](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#request-an-access-token-with-a-client_secret). Microsoft also says the secret "must be URL-encoded before being sent."; form-encoding the body is that step. The auth code flow reference adds: "The Basic auth pattern of instead providing credentials in the Authorization header, per RFC 6749 is also supported."
- Anyone looking for a `client_secret` field in the token request will now find one. Whether Entra logs a header-borne secret as "None" remains a guess; I have no source for it.

**The Basic-header encoding gap no longer applies to Entra sign-in.** [RFC 6749 §2.3.1](https://datatracker.ietf.org/doc/html/rfc6749#section-2.3.1) says the client ID and secret are form-urlencoded before they go into the Basic header. oauth2 2.0.25 skips that step for `:basic_auth` and sends the raw `id:secret`. If Entra form-decodes Basic credentials, a secret containing `+` (decoded as a space) or `%` would arrive changed, and Entra would answer with AADSTS7000215. With the body transport the client form-encodes the secret and the server decodes it, so `+` and `%` arrive unchanged. The gap only matters on a build that still sends the header; the local decoding check below models that transformation for such builds. It does not establish how Entra decodes Basic credentials.

**Releases up to v0.26.16 sent the secret in the `Authorization: Basic` header.** Those builds set no `auth_scheme`, so the oauth2 gem's default (`:basic_auth`) applied. Running the real omniauth-entra-id 3.1.1 strategy with oauth2 2.0.25 on such a build gave `auth_scheme=:basic_auth`, `body_keys=["grant_type", "code"]`, and an `Authorization: Basic` header that decodes to the raw `id:secret` pair. The body had no `client_secret` and no `client_id`, which is how a reader of the request could conclude the secret was "not sent." That transport did not change between v0.26.14 and v0.26.16 (same gems, no override), so it was not the regression the customer saw. On such a build the diagnostic reports `authorization_scheme: "basic"` and `raw_basic_matches_stored: true`. Customers on an affected release get the body transport by upgrading.

**Diagnostic tests check the outgoing transport, not Microsoft's decoding.** The [diagnostic regression coverage](./sso-entra-token-exchange-diagnostics.md#regression-coverage) compares credential representations at a mocked endpoint, including the mounted browser callback. It does not establish how Entra interprets those credentials.

## Error codes

Our case returned AADSTS7000215, which means Entra treated the app as a confidential client and checked the secret. From [Microsoft's error code reference](https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes):

| Code | Microsoft's wording | What it means here |
|---|---|---|
| 7000215 | "Invalid client secret is provided." | **What the customer got.** Entra checked the secret and no secret on the app matched it. |
| 700025 | "Client is public so neither 'client_assertion' nor 'client_secret' should be presented." | What a public-client app (the Single-page application / "Allow public client flows" setup) returns. |
| 7000218 | "The request body must contain the following parameter: 'client_assertion' or 'client_secret'." | What Entra returns when no secret arrives. |
| 7000222 | "The provided client secret keys are expired." | What an expired secret returns. |

## Leads

An expired secret that's still listed on the app returns 7000222, not 7000215, so "it expired" is unlikely. 7000215 means the secret we sent matches none of the app's current secrets. The leads, in order:

1. A secret was deleted or replaced in Entra and the domain's SSO settings in Onetime Secret were never updated.
2. The Secret ID was saved instead of the Value. Entra's full error message names this case and the app ID.
3. On a release up to v0.26.16, the secret contains `+` or `%` and is altered by the Basic-header encoding gap described above. A build with #4764 sends the secret in the body, so this lead does not apply there.

**Preserve the evidence first:** check the secrets currently listed under Certificates & secrets, but do not re-enter or rotate the stored Value before running the operator diagnostics below. Re-saving a known-good value replaces the evidence. Never ask the customer to send the Value.

## Isolation test

Run it twice, once with the secret in the body and once with raw Basic authentication. Test A is the transport a build with #4764 uses for sign-in; test B is what releases up to v0.26.16 sent. These tests use the **client-credentials grant**, not the authorization-code grant used by sign-in. They isolate credential transport for that grant; they do not reproduce the UI or conclusively identify the cause.

**Runs on:** the customer's own machine (macOS, Linux, or Git Bash on Windows). Not on an Onetime Secret host, and not in `bin/console`. It contacts Microsoft with the secret the customer types in.

```bash
ENTRA_TENANT_ID='<Directory (tenant) ID>'
ENTRA_CLIENT_ID='<Application (client) ID>'
printf 'Client secret value: '; read -rs ENTRA_CLIENT_SECRET; echo
TOKEN_URL="https://login.microsoftonline.com/$ENTRA_TENANT_ID/oauth2/v2.0/token"
esc() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }

echo "A (secret in request body):"
curl -s --config - <<EOF | grep -oE '"access_token"|AADSTS[0-9]+' | head -1
url = "$TOKEN_URL"
data-urlencode = "client_id=$(esc "$ENTRA_CLIENT_ID")"
data-urlencode = "client_secret=$(esc "$ENTRA_CLIENT_SECRET")"
data-urlencode = "scope=https://graph.microsoft.com/.default"
data = "grant_type=client_credentials"
EOF

echo "B (secret in Authorization header, as releases up to v0.26.16 sent it):"
curl -s --config - <<EOF | grep -oE '"access_token"|AADSTS[0-9]+' | head -1
url = "$TOKEN_URL"
user = "$(esc "$ENTRA_CLIENT_ID"):$(esc "$ENTRA_CLIENT_SECRET")"
data-urlencode = "scope=https://graph.microsoft.com/.default"
data = "grant_type=client_credentials"
EOF

unset ENTRA_CLIENT_SECRET
```

- The secret is typed in without being shown on screen and stays out of shell history.
- The secret reaches curl through a config file on stdin, never as a command-line argument, so it does not appear in `ps` output or process monitors. `esc` escapes the two characters (`"` and `\`) that curl's config format treats specially.
- Each test prints only `"access_token"` or the error code, so the output is safe to send back to us. The token itself is never printed.
- Neither test touches Onetime Secret.

**How to read the results:**

| A | B | Meaning |
|---|---|---|
| `"access_token"` | `"access_token"` | The supplied secret works both ways for this grant. This does not prove that the stored value differs or that browser sign-in works. Continue with the persisted-credential and strategy diagnostics below. |
| `"access_token"` | `AADSTS7000215` | Client-authentication transport changes the outcome for this grant. On a release up to v0.26.16, investigate lead 3 through the real strategy before attributing the UI failure to it. On a build with #4764, sign-in already uses transport A, so B's failure does not explain a UI failure there. |
| `AADSTS7000215` | `AADSTS7000215` | The value isn't a current secret of this app: a Secret ID, a deleted secret, or a typo (lead 2). |
| any other code | | Ask them to send us the code. |

I checked both commands locally against a capture server, using a fake secret that contains `+`, `%`, `"` and `\`. Test A sends it form-encoded in the body (`client_secret=ab%2Bc%252Fd~e%22q%5Cz`), and the server decodes it back to the original bytes. Test B sends a Basic header that decodes to the raw pair (`cid-456:ab+c%2Fd~e"q\z`), which matches what releases up to v0.26.16 sent, as described in "How Onetime Secret sends the secret". Neither command had the secret in its arguments. I didn't send anything to Microsoft.

## Operator diagnostic: persisted credentials through curl

**Runs on:** production `bin/console` in the affected deployment. Contacts Microsoft with the stored secret. Read-only.

Use `bin/console` in the affected deployment, with the customer's `domain`
already loaded. Do not change the SSO record, prompt for a replacement secret,
or supply credential ENV variables. This reads only the existing persisted
credentials through the model's runtime extraction path.

Paste the following blocks intact; `; nil` prevents IRB from inspecting the
returned objects. Do not inspect `stored`, `options`, errors, or HTTP responses.
Disable HTTP wire/debug logging and console session recording before diagnostics.
The cleanup drops references; it is not secure memory erasure. Exit the console
afterwards. A successful test obtains a real token and creates Entra audit events,
although it does not save SSO settings.

```ruby
require 'open3'
require 'uri'
require 'base64'

stored = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain.identifier); nil

raise "No stored SSO configuration" unless stored
raise "Stored provider is not Entra" unless stored.provider_type == 'entra_id'
```

Then run this as one block. `to_omniauth_options` performs the model's runtime
credential extraction; nothing trims or normalizes the resulting secret.

```ruby
begin
  options = stored.to_omniauth_options
  id = options.fetch(:client_id)
  secret = options.fetch(:client_secret)
  tenant = options.fetch(:tenant_id)

  raise "Stored credentials are incomplete" if [id, secret, tenant].any? { |value| value.nil? || value.empty? }

  token_url = "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token"
  common = {
    'scope' => 'https://graph.microsoft.com/.default',
    'grant_type' => 'client_credentials'
  }

  [
    ['A (stored secret in body)',
     common.merge('client_id' => id, 'client_secret' => secret),
     nil],
    ['B (stored secret in Basic header)',
     common,
     "Authorization: Basic #{Base64.strict_encode64("#{id}:#{secret}")}"]
  ].each do |label, form, header|
    config = "url = #{token_url.dump}\n"
    config += "data = #{URI.encode_www_form(form).dump}\n"
    config += "header = #{header.dump}\n" if header

    output, _stderr, status = Open3.capture3(
      'curl', '--disable', '--silent', '--show-error',
      '--max-time', '30', '--config', '-',
      stdin_data: config
    )

    marker = output[/"access_token"|AADSTS[0-9]+/]
    puts "#{label}: #{marker || "No token or AADSTS code; curl exit #{status.exitstatus}"}"
  end
ensure
  options = id = secret = tenant = config = output = nil
end; nil
```

Credentials go to curl through stdin, not command-line arguments. Neither the
secret nor returned token is deliberately printed.

- **A succeeds, B fails:** the stored/reloaded credential is usable; the difference
  is the client-authentication method. A is the method a build with #4764 uses
  for sign-in; B is what releases up to v0.26.16 used.
- **Both succeed:** the stored credentials work with both methods for this grant.
- **Both fail:** storage/encoding remains a possibility, alongside incorrect
  credentials, tenant, permissions, or grant restrictions.
- **Decryption fails before curl:** the failure is in local credential extraction,
  before contacting Microsoft.

This tests storage → decryption → curl request encoding without replacing the
stored value. It does not test the strategy's HTTP client or browser code flow.

For the next comparison, use the [registered-client probe](./sso-entra-token-exchange-diagnostics.md#operator-diagnostic-registered-strategys-http-client).
It clones the application-registered strategy and injects the persisted tenant
credentials while keeping the `client_credentials` grant. If stored curl B
succeeds but that probe fails, investigate strategy options, tenant injection,
the Ruby HTTP client, or process/network differences before changing the record.

## Operator diagnostic: stored credential character and decoding checks

**Runs on:** production `bin/console`, after the previous section. No network requests. Read-only.

After the persisted-credential A/B diagnostic, use the same `stored` record in
`bin/console`. This check reads through `to_omniauth_options`, makes no network
requests or writes, and reports only character-presence and comparison results.
It checks both the client ID and secret without displaying either value.

Run the entire block, not its intermediate expressions:

```ruby
begin
  require 'uri'

  options = stored.to_omniauth_options

  [:client_id, :client_secret].each do |field|
    value = options.fetch(field)
    raise 'Stored credentials are incomplete' unless value.is_a?(String) && !value.empty?

    decoded_unchanged = begin
      URI.decode_www_form_component(value).b == value.b
    rescue ArgumentError
      'invalid_form_encoding'
    end

    encoded = URI.encode_www_form_component(value)
    round_trip_unchanged =
      URI.decode_www_form_component(encoded).b == value.b

    puts "#{field}: #{{
      contains_plus: value.include?('+'),
      contains_percent: value.include?('%'),
      raw_form_decode_unchanged: decoded_unchanged,
      encoded_round_trip_unchanged: round_trip_unchanged
    }}"
  end
rescue StandardError => error
  puts "Credential inspection stopped: #{error.class.name}"
ensure
  options = value = encoded = decoded_unchanged = round_trip_unchanged = error = nil
end; nil
```

| Result | Meaning |
|---|---|
| `contains_plus: true` | A form-decoder would turn a raw `+` into a space. |
| `contains_percent: true` | Inspect the decoding result: valid `%HH` sequences are decoded; malformed escapes may be rejected. Presence of `%` alone does not establish alteration. |
| `raw_form_decode_unchanged: false` | Applying Ruby's form-decoder directly to the stored value changes its bytes. |
| `raw_form_decode_unchanged: "invalid_form_encoding"` | Ruby's form-decoder rejects the raw value. This does not establish how Entra handles it. |
| `encoded_round_trip_unchanged: true` | Encoding before decoding preserves the value, as expected. |

This **models the suspected transformation**. It does not prove Entra performs
that transformation or that these were the bytes sent by the failing worker.
A local exception is not evidence of a Microsoft credential rejection.

The output reveals limited credential characteristics: keep it in restricted
diagnostic records. Disable console recording and avoid inspecting intermediate
objects. Dropping references is not secure memory erasure; exit the console when
finished.

## Developer check: capture the actual outgoing credential transport

**Runs on:** a development checkout, as spec code with synthetic credentials and a mocked token endpoint. Never in production, and never with a real secret.

The [mounted Entra integration spec](../../apps/web/auth/spec/integration/full/entra_native_claims_spec.rb)
captures the real strategy's token request at a mocked endpoint. Since #4764 it
asserts the request-body transport on every code exchange and on the console
probe, with a stored secret that contains `+` and `%`: the decoded body equals
the stored pair, the secret is percent-encoded on the wire, and the request has
no `Authorization` header. Extend it with further **synthetic credentials only**,
such as `plain-secret`, `secret+suffix`, `secret%2Bsuffix`, and `secret%invalid`,
and exercise special characters in the client ID as well as the secret.

On a build that still sends a Basic header, Base64-decode each captured header's
payload and compare it with both candidate representations. In the test fixture only:

```ruby
raw_pair = "#{client_id}:#{client_secret}"

encoded_pair = [
  URI.encode_www_form_component(client_id),
  URI.encode_www_form_component(client_secret)
].join(':')
```

Do not paste these expressions into a production console: they return credentials.
For special-character fixtures, a payload equal to `raw_pair` but not
`encoded_pair` demonstrates the missing form-encoding step in that installed
client. It does not demonstrate Microsoft's decoding behavior.

The transport contract #4764 chose, and the spec asserts, is
**request-body authentication**: no `Authorization` header is sent, and the
decoded form contains the original client ID and secret. The alternative,
**RFC-compliant Basic** (the decoded Basic payload equals `encoded_pair`, and
form-decoding each component recovers the original fixture bytes), was not
adopted for Entra.

Capture the final request, not just `strategy.options`: options alone do not prove
what the HTTP client sent. Plain credentials cannot distinguish raw Basic from
encoded Basic. Keep the special-character cases as regression coverage, and check
that the authorization-code grant and redirect URI remain unchanged.

## Optional Entra comparison: raw Basic versus encoded Basic

**Runs on:** production `bin/console`, as a variant of the persisted-credential procedure. Contacts Microsoft. Read-only.

To test whether Basic encoding changes Microsoft's response, extend a diagnostic
copy of the persisted-credential A/B procedure with a third transport variant.
This investigates the header hypothesis for releases up to v0.26.16; a build
with #4764 sends no Basic header during sign-in.
Keep the stored values, endpoint, scope, and grant identical across variants:

| Variant | Credential transport |
|---|---|
| A | Form-encoded request body, as in the existing snippet. |
| B | Basic containing raw `id:secret`, as in the existing snippet. |
| B2 | Form-encode the ID and secret **individually** with `URI.encode_www_form_component`, join them with a literal `:`, then Base64-encode the pair with `Base64.strict_encode64`. Send it in the Basic header. |

B2 uses the same `common` form as B, without body credentials. Do not form-encode
the joined pair (that would encode the delimiter), or encode either component
twice. Send the generated header through curl's stdin configuration, as the
existing snippet does—not through argv or console output. Retain its bounded
timeout, marker-only output, and cleanup. This extension is not included in the
original A/B snippet, which remains unchanged.

**A and B2 succeed while B returns 7000215** is strong evidence that Basic
credential encoding determines the result for that grant. If all succeed, the
suspected transformation does not explain a rejection in that probe; it still
does not explain the UI failure. Other errors need separate interpretation.

This comparison still uses `client_credentials`. For UI-level confirmation, each
authorization-code transport variant needs its **own fresh authorization flow and
code**. Never reuse a redeemed code. Changing transport for such a comparison is
an explicit experimental variation, not an unmodified reproduction of the current
sign-in implementation. Preserve the stored credentials throughout.

## Operator diagnostic: real Entra strategy and authorization-code exchange

**Runs on:** production `bin/console` in the affected deployment, plus a browser for the authorization step. Contacts Microsoft with a real sign-in at the IdP. Read-only on our side.

To remove the grant and HTTP-client differences, use a **fresh browser authorization
code** with the application's tenant injection helper and the installed Entra
strategy. A made-up, expired, or already redeemed code cannot establish parity:
Microsoft may reject it before checking the client secret. Never replay the code
from the failed UI attempt, and never redeem one code twice to compare methods.

This procedure runs:

- [`inject_tenant_credentials` → `merge_strategy_options`](../../apps/web/auth/config/hooks/omniauth_tenant.rb), including persisted credential extraction;
- `OmniAuth::Strategies::EntraId#request_phase` to build the authorization URL;
- the real `callback_phase`, including OAuth state checking, and
  `build_access_token` → `EntraId#client` → `OAuth2::Client` for code redemption.

It does **not** run the mounted application's host-resolution middleware, Rodauth
setup hook, tenant session-binding checks, provider registration, or account/login
hooks. The host and record are explicitly selected, and the downstream Rack app
is a no-op. This is a code-path diagnostic, not a full UI reproduction or a way to
sign a user into Onetime Secret. It does not write accounts or SSO settings; it
still contacts Microsoft and can trigger consent and sign-in audit events.

### Prerequisites

1. Use an interactive `bin/console` in the affected deployment with full auth
   initialized and `domain` loaded. Match the running worker's release, bundle,
   datastore, and encryption configuration. Do not enable OmniAuth test mode.
2. Use an authorized test user and the domain's existing registered HTTPS callback
   URI. The example uses the default route `entra`; if the deployment uses another
   route name, change `route` to the one actually used by its sign-in button.
3. In a separate browser window, enable developer-tools **request blocking** for
   the domain's callback path **before** opening the authorization URL. Keep devtools
   open. The callback must never reach the web worker: this console owns the state
   and must be the sole redeemer of the code. If you cannot reliably block and copy
   the callback URL, stop and use the live UI procedure below instead.
4. Do not record the console or export a HAR. The authorization URL contains state;
   the blocked callback URL contains a credential (the code). Paste the latter only
   at the hidden prompt, never as Ruby source, a shell argument, or in a ticket.

Run this entire block. It intentionally binds a synthetic Rack environment to each
strategy instance and invokes the phases directly, rather than disabling request
validation globally. Only the per-instance failure reporter is replaced, to avoid
logging raw OAuth error responses. Credential injection and token transport are
not overridden. HTTP timeouts are bounded; the browser prompt waits for you.

```ruby
begin
  require 'io/console'
  require 'rack/mock'
  require 'omniauth-entra-id'
  require 'uri'

  raise 'Full auth tenant hooks are not loaded' unless defined?(Auth::Config::Hooks::OmniAuthTenant)
  raise 'OmniAuth test mode must be off' if OmniAuth.config.test_mode
  raise 'An interactive terminal is required' unless STDIN.tty?

  route = 'entra'
  callback_url = "https://#{domain.display_domain}/auth/sso/#{route}/callback"
  session = {}
  result = nil
  refusal = Object.new
  refusal.define_singleton_method(:throw_error_status) { |*| raise 'Tenant injection refused' }

  make_strategy = lambda do |url|
    record = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain.identifier)
    raise 'No stored Entra configuration' unless record && record.provider_type == 'entra_id'

    env = Rack::MockRequest.env_for(url)
    env['rack.session'] = session
    env['onetime.display_domain'] = domain.display_domain
    instance = OmniAuth::Strategies::EntraId.new(
      ->(_) { [204, {}, []] },
      name: route, path_prefix: '/auth/sso',
      client_options: { connection_opts: { request: { timeout: 30, open_timeout: 10 } } }
    )
    instance.instance_variable_set(:@env, env)
    env['omniauth.strategy'] = instance
    instance.define_singleton_method(:fail!) do |kind, error = nil|
      result = error&.message.to_s[/AADSTS[0-9]+/] || kind.to_s
      [401, {}, []]
    end
    Auth::Config::Hooks::OmniAuthTenant.inject_tenant_credentials(record, instance.request, refusal)
    raise 'Unexpected callback URI' unless instance.callback_url == callback_url
    instance
  end

  strategy = make_strategy.call(callback_url.delete_suffix('/callback'))
  response = strategy.request_phase
  location = response[1]['location'] || response[1]['Location']
  raise 'No authorization redirect' unless response[0] == 302 && location
  puts "Open privately after enabling callback request blocking:\n#{location}"
  print 'Blocked callback URL (hidden): '
  callback_input = STDIN.noecho(&:gets)
  puts
  raise 'No callback URL supplied' unless callback_input
  callback = URI.parse(callback_input.strip)
  expected = URI.parse(callback_url)
  raise 'Unexpected callback URL' unless [callback.scheme, callback.host, callback.port, callback.path] ==
    [expected.scheme, expected.host, expected.port, expected.path] && !callback.userinfo && !callback.fragment

  strategy = make_strategy.call(callback.to_s)
  strategy.callback_phase
  puts "C (real strategy code flow): #{result || (strategy.access_token ? 'access_token' : 'No token')}"
rescue StandardError => error
  marker = error.message[/AADSTS[0-9]+/]
  puts "C: #{marker || error.class.name}; stopped (raw error suppressed)"
ensure
  session&.clear
  strategy = response = location = callback_input = callback = expected = nil
  make_strategy = refusal = error = nil
end; nil
```

Close the diagnostic browser window, clear the clipboard, remove the callback
block, and exit the console. If C reports a local exception class without an
AADSTS code, it is not evidence that Microsoft rejected the secret. Investigate
locally without printing credential-bearing objects or raw exceptions. If it
reports `csrf_detected`, start again with a fresh URL from this console; do not
turn off state validation.

**Interpretation:**

| Stored A/B | C | Next step |
|---|---|---|
| Both succeed | `AADSTS7000215` | Reproduced through persisted credential injection and the real authorization-code token exchange. Investigate grant/request differences; do not replace the secret yet. |
| Both succeed | `access_token` | Those code paths work in this console. The UI discrepancy is still unresolved: compare the live worker and request context below. |
| Any | Other AADSTS code or local failure | Resolve that failure first. It does not confirm or refute the UI's 7000215. |

The existing [mounted Entra integration spec](../../apps/web/auth/spec/integration/full/entra_native_claims_spec.rb)
runs real routing and strategy code with synthetic tokens and a mocked token
endpoint. It is useful for regression coverage, but cannot establish whether
Microsoft accepts the production credential. The console example above targets
the inspected omniauth-entra-id 3.1.1 / omniauth-oauth2 1.9.0 interfaces; a live
Microsoft exchange has not been validated as part of this documentation change.

## Close the remaining gap: reproduce on the live UI request

**Runs on:** the production web workers that serve the customer's domain. Step 4 is a diagnostic deployment to those workers, not a console procedure.

No isolated console probe can guarantee the UI's result. To eliminate the remaining
context differences, make a fresh sign-in through the affected public hostname,
with the callback block removed, and correlate **that request's** application logs
with its Entra sign-in event. A real sign-in may create/link an account or establish
a session; use an authorized test account and the normal login route, not Connect.

1. Record UTC time, public hostname, provider route, domain ID, and the serving
   instance/release. Confirm which worker handled both initiation and callback;
   compare its deployed gem versions and configuration with the console. A console
   on a different replica is not proof of what this worker loaded.
2. Find `omniauth_tenant_credentials_injecting` for the expected domain on the
   callback, then the `omniauth_failure` that followed on the **same worker PID and
   thread** (the `[pid:thread]` prefix of each log line) with no other callback
   start on that thread in between. The two events share no field: the injection
   line carries `domain_id`, the failure line does not, and both log
   `correlation_id: none`. Timestamp proximity alone is not enough under
   concurrent sign-ins. The injection event is also emitted **before** injection;
   by itself it does not prove the final HTTP client received those credentials.
   Do not equate two adjacent log lines from different requests, or a matching
   tenant/app ID, with proof of identical secret bytes. The step 4 observer ties
   request and response together with its own `probe_id`.
3. Compare the live authorize request's tenant, client ID, scope and redirect URI
   with the console flow, and match Entra's error code, trace/correlation IDs and
   timestamp. Keep full callback URLs, cookies, state, codes and token responses
   out of tickets and diagnostic output.
4. If C succeeds but the UI still fails, collect evidence from the live worker
   **at `build_access_token`**, not another curl run. Follow the
   [live-worker observer deployment and cleanup procedure](./sso-entra-token-exchange-diagnostics.md#install-the-observer-in-the-serving-web-workers)
   with operator approval. It compares the normal callback's outgoing credentials
   with a fresh persisted read as raw Basic, form-encoded Basic, and body
   credentials, and reports endpoint/redirect matches, grant type, code/PKCE
   presence, HTTP status, and AADSTS code. Correlate the request and response by
   worker PID and diagnostic identifier. Do not call `build_access_token` a
   second time: observe the normal exchange once, without copying or replaying codes.

Step 4 requires deployment in the serving workers; loading the helper in
`bin/console` cannot inspect another worker's in-memory strategy. On a build with
#4764 the observer should report `authorization_scheme: "none"` with
`body_client_id_matches_stored` and `body_secret_matches_stored` both true; a
Basic header on the live request means that worker runs a release up to
v0.26.16. A matching raw Basic header plus 7000215 establishes the outgoing
representation and rejection, not Microsoft's internal decoding. Use the A/B/B2
comparison above to investigate that hypothesis.
Until that request-level evidence exists, record **“stored A/B and isolated
strategy succeed; UI failure not yet isolated”**, rather than claiming the secret
is wrong or that the implementation is ruled out. Preserve the record while
collecting this evidence; change transport or rotate credentials only afterwards
as a separately verified fix.

## Suggested explanations that don't fit

Outside research suggested a Single-page application platform, "Allow public client flows", a credential-less first attempt, and an app/tenant mismatch. Microsoft gives the setups it describes their own error codes (see "Error codes").

- **Redirect URI under the "Single-page application" platform:** the [auth code flow page](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#redirect-uris-for-single-page-apps-spas) says the platform "returns an error if you attempt to use a `spa` redirect URI without an `Origin` header." Our token request is server-side and sends no `Origin` header, so it would get that error, not 7000215.
- **The "credential type None" claim:** the research's links are unreadable redirect URLs, and I found no Microsoft wording that backs it.
- **"Restart your backend":** refreshing a cached tenant secret is not the expected fix: the tenant hook reads the domain's SSO settings on each request. That does not rule out a worker running a different release, dependency bundle, datastore configuration, or encryption configuration. Compare those before restarting and losing the failing process context.
- **Its two questions:** we use the authorization code flow for user sign-in, as a confidential client, with the code redeemed server-side. The error is AADSTS7000215.
- **Its curl command is broken.** The scope and `client_secret` got merged into one string (`scope=https://microsoft.com<YOUR_SECRET_VALUE>`). It also uses a plain `-d`, which would itself turn a `+` into a space, the very problem being tested.
- **The "None, then a retry with the secret" theory doesn't apply.** Our app makes one token request per sign-in. omniauth-oauth2 calls `build_access_token` once and only refreshes a token that came back expired; it never retries on an error.
- **An app/tenant mismatch is ruled out.** The sign-in step succeeded at their tenant with that client ID, so the app exists there.

Checking the platform settings costs the customer nothing, but those settings aren't the lead.

## To confirm in production logs

**Runs on:** the production log store. Read-only.

- An `omniauth_tenant_credentials_injecting` line with their `domain_id` confirms the tenant path ran on some callback. An `omniauth_failure` line with `error_type=invalid_credentials` and an `error_message` containing the AADSTS7000215 text and app ID confirms a rejected exchange. The two lines cannot be joined by their fields: the failure line has no `domain_id`, and both log `correlation_id: none`. Match them by worker PID and thread (the `[pid:thread]` log prefix) with no intervening callback on that thread, and treat the match as a lead, not proof. Under concurrent sign-ins a nearby 7000215 can belong to another tenant. Adding `domain_id` to tenant `omniauth_failure` events is proposal 4 in [sso-credential-health.md](./sso-credential-health.md#proposed-not-built).
- `domain_sso_config_updated` events with `client_secret changed: true` show whether anyone re-saved the secret recently.

## Recommendation

**Done:** Entra sends the secret in the request body (`client_options: { auth_scheme: :request_body }`) for both the platform registration and custom-domain tenants, whatever result B gives. That's the form Microsoft documents first, it works with any character in a secret, and the mounted Entra spec pins how the secret is sent. Landed in [#4764](https://github.com/onetimesecret/onetimesecret/issues/4764). A customer on an affected release gets the fix by upgrading; no configuration change is needed. See "How Onetime Secret sends the secret".

**Also done:** the optional `token_endpoint_auth_method` setting for generic OIDC, Part 2 of #4764: per domain under Advanced in the SSO form, and `OIDC_CLIENT_AUTH_METHOD` for the platform provider. The default for generic OIDC is unchanged. Test Connection reports the methods the IdP advertises. See [per-domain-sso.md](../authentication/per-domain-sso.md#token-endpoint-authentication).

**Also done:** Check saved configuration is separate from Test Connection and
checks the saved record. For Entra, it requests a token with the stored client ID
and secret using the client-credentials grant and request-body authentication,
without a user sign-in. Test Connection still tests the form and does not check
the secret. A passing credential check means Entra accepted the saved secret for
that request; only a real sign-in confirms that sign-in works. See
[sso-credential-health.md](./sso-credential-health.md#what-check-saved-configuration-covers)
for the checks and their limits.
