# API bearer tokens (PASETO v4.public)

Short-lived signed bearer tokens for the v3 API, issued by `POST /api/v3/token`
and presented as `Authorization: Bearer v4.public...`. Opt-in per deployment.
Tracked in [#2427](https://github.com/onetimesecret/onetimesecret/issues/2427).

## What it is

A [PASETO](https://paseto.io) v4.public token is a signed, unencrypted JSON
payload with a fixed cryptographic suite (Ed25519 over the Pre-Authentication
Encoding of header, payload, footer and implicit assertion). There is no
algorithm field to negotiate and nothing to downgrade, which is why it was
chosen over JWT. The token is readable by anyone who holds it: it carries no
secret, only claims the server checks after verifying the signature.

Each token says:

| Claim   | Value |
| ------- | ----- |
| `sub`   | the customer external ID (`ur…`), never an internal ID |
| `aud`   | `onetimesecret:api:v3`; a verifier for another surface refuses it |
| `iss`   | the issuing deployment's `site.host` |
| `iat` / `nbf` / `exp` | RFC 3339 UTC; `exp` is `iat` plus the configured lifetime |
| `jti`   | 128 random bits, for logs |
| `scope` | `["*"]`, the only grant today; anything else is refused |

The footer carries `{"kid": "…"}`, the identifier of the signing key, so a
deployment mid-rotation can pick the right key before verifying.

## Enabling it

Off by default. V3's stable surface accepts browser sessions and the explicit
guest routes only; turning this on is an operator decision that adds a third
credential to the authenticated v3 secret routes.

```bash
PASETO_ENABLED=true          # auth.yaml: paseto.enabled
PASETO_TOKEN_TTL=3600        # auth.yaml: paseto.token_ttl (60..86400 seconds)
```

The flag is read per request, so it takes effect on the next request after a
config reload. While it is off:

- `POST /api/v3/token` answers `403` with `code: BEARER_TOKENS_DISABLED`;
- a `Bearer` header on any v3 route is ignored, exactly as before the feature
  existed (the route answers with its session refusal).

No key material to generate or back up. The Ed25519 signing seed is derived
from `SECRET` with HKDF (`Onetime::KeyDerivation`, purpose `paseto_signing`),
like the session, identifier and Familia encryption keys. Nothing is written to
`.env` or the datastore.

## Using it

Obtain a token from a browser session (the web UI sends its CSRF token) or
from an existing Basic auth API key:

```bash
curl -u 'user@example.com:APITOKEN' -X POST https://us.onetimesecret.com/api/v3/token
```

```json
{
  "record": {
    "token": "v4.public.eyJzdWIiOiJ1c…",
    "token_type": "Bearer",
    "expires_in": 3600,
    "expires_at": 1761600000,
    "issued_at": 1761596400,
    "kid": "e08a57e05421d6d3",
    "scope": ["*"]
  },
  "details": { "subject": "ur…", "audience": "onetimesecret:api:v3", "issuer": "us.onetimesecret.com" }
}
```

Then present it on the authenticated v3 secret routes and `/api/v3/version`:

```bash
curl -H 'Authorization: Bearer v4.public.eyJzdWIiOiJ1c…' https://us.onetimesecret.com/api/v3/receipt/recent
```

A bearer request carries no cookie, so no CSRF token is needed. A request
that carries both a valid session cookie and a bearer header is answered as
the session's (and must send the CSRF token), the same rule Basic auth
follows.

A bearer token cannot mint another token: `POST /api/v3/token` accepts a
session or an API key only, so a leaked token expires on schedule instead of
renewing itself.

## Refusals

A presented token that is rejected answers `401` with the credential code pair
(see [customer-session-failure-matrix.md](./customer-session-failure-matrix.md))
and an RFC 6750 `WWW-Authenticate: Bearer` challenge:

| `code` | Why | Challenge |
| --- | --- | --- |
| `api_token_expired` | signature valid, `exp` has passed | `Bearer realm="onetimesecret", error="invalid_token", error_description="The access token expired"` |
| `api_token_invalid` | anything else: not a v4.public token, unknown `kid`, bad signature, wrong `aud`/`iss`, unsupported `scope`, unknown subject, or a token issued before the account's last password change | `Bearer realm="onetimesecret", error="invalid_token"` |
| `suspended_credentials` | valid token, suspended account | `Bearer realm="onetimesecret", error="invalid_token"` |

One code covers the whole non-expiry family on purpose: the message tells a
client no more than that the token was rejected. The precise reason is in the
server's debug log with the token's `kid` and `jti`, never the token itself.

A request with no `Authorization` header, or with another scheme, is not a
bearer refusal: the rest of the route's chain answers it.

## Revocation and rotation

Tokens are stateless, so revocation works through what the verifier checks on
every request:

- **Expiry.** The default lifetime is one hour; the ceiling is one day.
- **Password change.** A token issued at or before `Customer#last_password_update`
  is refused, the same watermark that retires sessions after a credential
  change. Changing the password revokes every outstanding token. A token
  requested in the same second as the change is issued one second past the
  watermark, so it works at once instead of being refused for its whole life.
- **Suspension.** A suspended account's tokens are refused on the next request.
- **Account deletion.** The subject no longer resolves.

Key rotation rides the existing SECRET rotation
([docs/runbooks/secret-rotation.md](../runbooks/secret-rotation.md)): every
entry in `SECRET_PREVIOUS` derives a verification-only key, so tokens signed
before the rotation keep verifying until they expire, while new tokens are
signed with the key derived from the current `SECRET`. Since tokens live at
most a day, a previous SECRET kept for the window the runbook already requires
covers them with room to spare.

## Implementation

| Piece | Where |
| --- | --- |
| Token format (sign, parse, verify, PAE) | `lib/onetime/paseto/v4_public.rb` |
| Keys from `SECRET` and `SECRET_PREVIOUS` | `lib/onetime/paseto/keyring.rb`, `Onetime::Initializers::SetupPasetoKeys` |
| Claims: issue and verify | `lib/onetime/paseto/access_token.rb` |
| Route strategy (`auth=pasetoauth`) | `lib/onetime/application/auth_strategies/paseto_auth_strategy.rb` |
| Exchange endpoint | `apps/api/v3/logic/auth.rb` (`V3::Logic::Auth::GenerateToken`) |
| Operator flag | `etc/defaults/auth.defaults.yaml` (`paseto`), `Onetime::AuthConfig#paseto_enabled?` |
| Official test vectors | `spec/fixtures/paseto/v4.json`, `spec/unit/onetime/paseto/v4_public_spec.rb` |

The codec is in-tree rather than a gem: v4.public is Ed25519 (OpenSSL,
already a dependency) plus a length-prefixed encoding, and the official
vectors pin it byte for byte. The one Ruby PASETO gem that implements v4 has
a single maintainer and pulls `sorbet-runtime` and `zeitwerk` into the
runtime bundle for a few dozen lines of use.
