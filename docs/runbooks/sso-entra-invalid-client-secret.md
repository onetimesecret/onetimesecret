# SSO: Entra AADSTS7000215 (invalid client secret)

**Symptom:** reported 2026-10-12 by a custom-domain customer using tenant
Entra ID SSO, after v0.26.16 fixed the v0.26.15 proxy-trust incident:

> Entra ID returns error AADSTS7000215 ("Invalid client secret provided")
> during the token exchange. The sign-in log also shows "Client credential
> type: None", which suggests the client secret is not being sent or not
> being read correctly after the update.

## Why the release is not the cause

**Why I think so** (from reading the code at v0.26.14, v0.26.15 and v0.26.16, plus the gem source):

1. **Nothing in the secret's path changed between v0.26.14 and v0.26.16.** That path is `SsoConfig#build_entra_id_options` → `inject_tenant_credentials` / `merge_strategy_options` → omniauth-entra-id 3.1.1 `#client` → `OAuth2::Client`. The only changes to `sso_config.rb` in that range were the class reopen (#4220) and the IDN allowlist (#4736). No commits touched the save API or the form, and the omniauth, oauth2 and entra gem versions are the same.
2. **A missing secret can't reach Entra.** omniauth-entra-id raises `ArgumentError` when the secret is nil, so no token request is made. Saving an Entra config with a blank secret is rejected (PUT), or keeps the stored secret (PATCH).
3. **The error shows up under their app in their tenant.** Our token request therefore carried their client ID and tenant ID, which come from the same stored record as the secret. If the callback had taken the platform path (for example, through the untrusted proxy route from the v0.26.15 incident), it would have sent the platform's or placeholder credentials to a different tenant, and the customer would never see the failure.
4. **The error code means a secret was sent.** Microsoft's "no credential sent" error is AADSTS7000218. [Their troubleshooting page](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/confidential-client-application-authentication-error-aadsts7000218) says it happens "because the application doesn't provide the credentials (client secret or assertion) that the token endpoint expects." AADSTS7000215 means a secret arrived and didn't validate. I found no Microsoft wording on what "Client credential type" shows for a rejected secret, so "None" doesn't show that nothing was sent.

## How Onetime Secret sends the secret

Nothing in our codebase describes Entra's "Client credential type" field. I searched tracked files on main, the history of every branch, the worktrees, and the sibling repos including docs.onetimesecret.com. The only matches are about WebAuthn and Stripe credential types.

What the codebase does answer is how we send the secret, and that probably explains the customer's reading.

**We send the secret in the `Authorization: Basic` header, not in the request body.** No code in the repo sets `auth_scheme`, so the oauth2 gem's default (`:basic_auth`) applies. I ran the real omniauth-entra-id 3.1.1 strategy with oauth2 2.0.25 locally:

```
auth_scheme=:basic_auth
body_keys=["grant_type", "code"]
authorization=Basic Y2lkOnNlYytyZXR+eA==   # decodes to "cid:sec+ret~x"
```

- The token request body has no `client_secret` and no `client_id`. Anyone looking for a `client_secret` field in the request will find none and read that as "not sent." Whether Entra logs a header-borne secret as "None" is my guess; I have no source for it.
- Microsoft supports this. The [auth code flow reference](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#request-an-access-token-with-a-client_secret) says: "The Basic auth pattern of instead providing credentials in the Authorization header, per RFC 6749 is also supported."
- This hasn't changed between v0.26.14 and v0.26.16 (same gems, no override), so it isn't the regression.

**There is a latent encoding gap.** [RFC 6749 §2.3.1](https://datatracker.ietf.org/doc/html/rfc6749#section-2.3.1) says the client ID and secret are form-urlencoded before they go into the Basic header. oauth2 2.0.25 skips that step and sends the raw `id:secret`. Microsoft also says the secret "must be URL-encoded before being sent." If Entra form-decodes Basic credentials, a secret containing `+` (decoded as a space) or `%` would arrive changed, and Entra would answer with AADSTS7000215. A secret without those characters is unaffected.

**Our tests don't check how the secret is sent.** `apps/web/auth/spec/integration/full/entra_native_claims_spec.rb` captures the real token request but only checks `grant_type`, `code` and `redirect_uri`.

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
3. The secret contains `+` or `%` and is altered by the Basic-header encoding gap described above.

**What to ask the customer:** check the secrets currently listed under Certificates & secrets, re-enter the current Value in that domain's SSO settings, and tell us whether that Value contains `+` or `%`.

## Isolation test

Run it twice, once with the secret sent the standard way and once exactly the way Onetime Secret sends it. Comparing the two results tells 2 and 3 apart.

**For the customer** (macOS, Linux, or Git Bash on Windows):

```bash
export ENTRA_TENANT_ID='<Directory (tenant) ID>'
export ENTRA_CLIENT_ID='<Application (client) ID>'
printf 'Client secret value: '; read -rs ENTRA_CLIENT_SECRET; echo
TOKEN_URL="https://login.microsoftonline.com/$ENTRA_TENANT_ID/oauth2/v2.0/token"

echo "A (secret in request body):"
curl -s "$TOKEN_URL" \
  --data-urlencode "client_id=$ENTRA_CLIENT_ID" \
  --data-urlencode "client_secret=$ENTRA_CLIENT_SECRET" \
  --data-urlencode "scope=https://graph.microsoft.com/.default" \
  -d grant_type=client_credentials | grep -oE '"access_token"|AADSTS[0-9]+' | head -1

echo "B (secret in Authorization header, as Onetime Secret sends it):"
curl -s "$TOKEN_URL" -u "$ENTRA_CLIENT_ID:$ENTRA_CLIENT_SECRET" \
  --data-urlencode "scope=https://graph.microsoft.com/.default" \
  -d grant_type=client_credentials | grep -oE '"access_token"|AADSTS[0-9]+' | head -1

unset ENTRA_CLIENT_SECRET
```

- The secret is typed in without being shown on screen and stays out of shell history.
- Each test prints only `"access_token"` or the error code, so the output is safe to send back to us. The token itself is never printed.
- Neither test touches Onetime Secret.

**How to read the results:**

| A | B | Meaning |
|---|---|---|
| `"access_token"` | `"access_token"` | The secret works both ways, so the value saved in Onetime Secret is different. Re-enter it (lead 2). |
| `"access_token"` | `AADSTS7000215` | The way we send the secret breaks it. This is our bug (lead 3). |
| `AADSTS7000215` | `AADSTS7000215` | The value isn't a current secret of this app: a Secret ID, a deleted secret, or a typo (lead 2). |
| any other code | | Ask them to send us the code. |

I checked both commands locally, using a fake secret that contains `+` and `%`. Test A sends it encoded (`ab%2Bc%252Fd~e`). Test B sends it raw (`cid-456:ab+c%2Fd~e`), which matches what our app sends, as the probe in "How Onetime Secret sends the secret" showed. I didn't send anything to Microsoft.

## Suggested explanations that don't fit

Outside research suggested a Single-page application platform, "Allow public client flows", a credential-less first attempt, and an app/tenant mismatch. Microsoft gives the setups it describes their own error codes (see "Error codes").

- **Redirect URI under the "Single-page application" platform:** the [auth code flow page](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#redirect-uris-for-single-page-apps-spas) says the platform "returns an error if you attempt to use a `spa` redirect URI without an `Origin` header." Our token request is server-side and sends no `Origin` header, so it would get that error, not 7000215.
- **The "credential type None" claim:** the research's links are unreadable redirect URLs, and I found no Microsoft wording that backs it.
- **"Restart your backend":** this doesn't apply to us. We read the domain's SSO settings on every request and don't cache tokens.
- **Its two questions:** we use the authorization code flow for user sign-in, as a confidential client, with the code redeemed server-side. The error is AADSTS7000215.
- **Its curl command is broken.** The scope and `client_secret` got merged into one string (`scope=https://microsoft.com<YOUR_SECRET_VALUE>`). It also uses a plain `-d`, which would itself turn a `+` into a space, the very problem being tested.
- **The "None, then a retry with the secret" theory doesn't apply.** Our app makes one token request per sign-in. omniauth-oauth2 calls `build_access_token` once and only refreshes a token that came back expired; it never retries on an error.
- **An app/tenant mismatch is ruled out.** The sign-in step succeeded at their tenant with that client ID, so the app exists there.

Checking the platform settings costs the customer nothing, but those settings aren't the lead.

## To confirm in production logs

- On the callback request, an `omniauth_tenant_credentials_injecting` line with their `domain_id` confirms the tenant path ran. It should be followed by `omniauth_failure` with `error_type=invalid_credentials`, and its `error_message` should contain the AADSTS7000215 text and app ID.
- `domain_sso_config_updated` events with `client_secret changed: true` show whether anyone re-saved the secret recently.

## Recommendation

**My recommendation:** switch Entra to sending the secret in the request body (`auth_scheme: :request_body`) whatever result B gives. That's the form Microsoft documents first, it works with any character in a secret, and it's a small change plus a spec pinning how the secret is sent.

Test Connection doesn't check the client secret, so they can only confirm the fix with a real sign-in. A possible follow-up, not urgent: have Test Connection verify the saved Entra secret by requesting a token with it, which needs no user sign-in. [sso-credential-health.md](./sso-credential-health.md) covers what such a probe does and does not prove, and the other checks that keep SSO credentials healthy.
