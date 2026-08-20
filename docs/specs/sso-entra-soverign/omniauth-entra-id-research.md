# docs/specs/sso-entra-soverign/omniauth-entra-id-research.md
---

## omniauth-entra-id sovereign cloud research

> **Note:** No `Gemfile.lock` was provided, so findings are based on the latest published version (3.1.1) and public source. Adjust if your lock file pins an older version.

---

### 1. Installed gem — versions and source

The gem lives at [pond/omniauth-entra-id](https://github.com/pond/omniauth-entra-id) (maintained by RIPA Global). Four total versions: [^6]

| Version | Date |
|---|---|
| 3.1.1 | Sep 12, 2025 |
| 3.1.0 | Jun 17, 2025 |
| 3.0.1 | Nov 20, 2024 |
| 3.0.0 | Oct 22, 2024 |

---

### 2. `base_url` — what it does and what it affects

**Option definition:** `base_url` is documented as *"Location of Entra login page, for specialised requirements; default is `OmniAuth::Strategies::EntraId::BASE_URL`."* [^3]

```ruby
BASE_URL = 'https://login.microsoftonline.com'
```
[^1]

The `client` method resolves it from the tenant provider or falls back to `BASE_URL`, then builds URLs: [^1]

```ruby
tenanted_endpoint_base_url = "#{options.base_url}/#{options.tenant_id}"

options.client_options.authorize_url = "#{tenanted_endpoint_base_url}/#{oauth2}/authorize"
options.client_options.token_url     = "#{tenanted_endpoint_base_url}/#{oauth2}/token"
```

Issuer validation in `raw_info` also uses `base_url`: [^1]

```ruby
issuer = "#{options.base_url || BASE_URL}/#{options.tenant_id}/v2.0"
# then: verify_params[:iss] = issuer
```

**Coverage summary:**

| Concern | `base_url` honored? | Notes |
|---|---|---|
| Authorization URL | ✅ Yes | `base_url + tenant_id + /oauth2/v2.0/authorize` |
| Token URL | ✅ Yes | `base_url + tenant_id + /oauth2/v2.0/token` |
| Issuer validation | ✅ Yes | `base_url + tenant_id + /v2.0` — exact string match |
| JWKS / discovery | N/A | Gem does **not** perform OIDC discovery or JWKS fetching; JWT is decoded **without** signature verification (`JWT.decode(…, nil, false)`) |
| Certificate auth (`client_assertion`) | ❌ **Hardcoded** | `client_assertion_claims` hardcodes `https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token` as the `aud` claim regardless of `base_url` |

The certificate auth hardcode is a concrete bug: [^1]

```ruby
def client_assertion_claims(tenant_id, client_id)
  {
    'aud' => "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token",
    # ^^^ always commercial — base_url ignored
    ...
  }
end
```

---

### 3. Upstream sovereign cloud support

**Not intentional, not documented as sovereign support.** The README describes `base_url` only as a "specialised requirements" escape hatch, with no mention of: [^4]

- `authority`
- `azure_environment`
- `sovereign`
- `national cloud`
- `login.microsoftonline.us`
- `login.partner.microsoftonline.cn`

**Changelog:** No version mentions sovereign cloud support. Notable recent changes: [^7] [^7]

- v3.1.1: Fixes `consumers` tenant issuer validation
- v3.1.0: `ignore_tid` option, JWT gem v3 support
- v3.0.1: Fixes AD FS issuer verification bug
- v3.0.0: B2C support, certificate auth, ID token validation overhaul

**Tests:** The spec suite exercises `base_url: 'https://login.microsoftonline.de'` (German cloud) in both static and dynamic provider configurations, confirming the pattern works mechanically. [^2] There are **no tests** for `login.microsoftonline.us` or `login.partner.microsoftonline.cn`. The German cloud tests are the closest proxy for validation confidence.

---

### 4. Microsoft's authoritative sovereign endpoints

Verified from live discovery documents:

| Cloud | Base host | Discovery URL |
|---|---|---|
| Commercial | `login.microsoftonline.com` | `…/common/v2.0/.well-known/openid-configuration` |
| US Government | `login.microsoftonline.us` | `…/common/v2.0/.well-known/openid-configuration` |
| China (21Vianet) | `login.partner.microsoftonline.cn` | `…/common/v2.0/.well-known/openid-configuration` |

**Endpoints and issuer templates (from live discovery docs):**

**US Government** (`login.microsoftonline.us`): [^8]

| Endpoint | URL |
|---|---|
| Authorization | `https://login.microsoftonline.us/common/oauth2/v2.0/authorize` |
| Token | `https://login.microsoftonline.us/common/oauth2/v2.0/token` |
| JWKS | `https://login.microsoftonline.us/common/discovery/v2.0/keys` |
| Issuer template | `https://login.microsoftonline.us/{tenantid}/v2.0` |
| userinfo | `https://graph.microsoft.com/oidc/userinfo` (same as commercial) |

**China** (`login.partner.microsoftonline.cn`): [^9] [^9]

| Endpoint | URL |
|---|---|
| Authorization | `https://login.partner.microsoftonline.cn/common/oauth2/v2.0/authorize` |
| Token | `https://login.partner.microsoftonline.cn/common/oauth2/v2.0/token` |
| JWKS | `https://login.partner.microsoftonline.cn/common/discovery/v2.0/keys` |
| Issuer template | `https://login.partner.microsoftonline.cn/{tenantid}/v2.0` |

Both national cloud endpoints use the same path structure as commercial. The only difference is the host.

Note: `login.microsoftonline.cn` (without `partner.`) is **not** the correct China endpoint. The correct host is `login.partner.microsoftonline.cn`. [^5]

---

### 5. Issuer validation behavior

For a single-tenant sovereign deployment (e.g. US Gov with a specific tenant GUID), the gem constructs:

```ruby
issuer = "#{options.base_url}/#{options.tenant_id}/v2.0"
# => "https://login.microsoftonline.us/your-tenant-guid/v2.0"
```

The token issued by Microsoft will carry:
```
iss: "https://login.microsoftonline.us/your-tenant-guid/v2.0"
```

These **will match** — the gem uses exact string comparison via `JWT::Claims.verify_payload!`. So issuer validation **works correctly** when `base_url` is set to the sovereign host, as long as a specific `tenant_id` is configured (not `common`/`organizations`). [^1]

Caveats:
- `common` or `organizations` tenant → issuer verification is **skipped**. This is the existing behavior for multi-tenant apps.
- `consumers` tenant → issuer is compared against the fixed GUID `9188040d-6c67-4c5b-b112-36a304b66dad`, not a cloud-specific value. For sovereign clouds this would be wrong (though consumers tenants are unlikely in sovereign contexts).

---

### 6. Application-side hardcodes to find

The gem's `base_url` only covers the OmniAuth strategy layer. Your application code likely has additional hardcoded commercial hosts to audit:

**Canonical locations to grep:**

```
login.microsoftonline.com
```

Look in:
- Provider strategy setup (wherever you call `provider :entra_id, …`)
- Any CSP/Content-Security-Policy origin calculation (the `frame-ancestors` or `connect-src` for the login page)
- Connection testing / OIDC discovery fetching (if your app pre-fetches `.well-known/openid-configuration`)
- Callback/issuer validation logic outside the gem (e.g. if you double-verify tokens in a middleware or JWT concern)
- Any `userinfo_endpoint` calls (note: both US Gov and commercial share `graph.microsoft.com/oidc/userinfo` — this one is actually the same)

---

### 7. Conclusion: does `base_url` give you full sovereign support?

**Mostly yes, with two gaps:**

| Area | Status |
|---|---|
| Authorization + token URLs | ✅ Fully honored via `base_url` |
| Issuer validation (single tenant) | ✅ Works — exact match against `base_url + tenant_id + /v2.0` |
| JWKS / signature verification | ✅ N/A — gem skips signature verification entirely |
| Certificate-based client auth (`client_assertion`) | ❌ Hardcodes `login.microsoftonline.com` — **must be patched or monkey-patched** |
| Application-layer hardcodes | ❌ Must audit separately — gem doesn't cover CSP, discovery calls, etc. |

**The answer to the key question:** `base_url` is sufficient for auth code + secret-based flows. A new strategy is **not** needed. You need:

1. Application wiring — expose an `authority`/`base_url` config and pass it through to the provider.
2. Patch `client_assertion_claims` if you use certificate auth — it must use `base_url` instead of the commercial literal.
3. Audit and parameterize all `login.microsoftonline.com` literals in application code (CSP, connection tests, any direct OIDC fetching).
4. Add integration tests covering `base_url: 'https://login.microsoftonline.us'` and `base_url: 'https://login.partner.microsoftonline.cn'` — there are zero upstream tests for these environments.

**References**

[^1]: [lib/omniauth/strategies/entra_id.rb](https://github.com/pond/omniauth-entra-id/blob/master/lib/omniauth/strategies/entra_id.rb) (32%)
[^2]: [spec/omniauth/strategies/entra_id_spec.rb](https://github.com/pond/omniauth-entra-id/blob/master/spec/omniauth/strategies/entra_id_spec.rb) (13%)
[^3]: [pond/omniauth-entra-id: OAuth 2 authentication with ...](https://github.com/pond/omniauth-entra-id) (12%)
[^4]: [README.md](https://github.com/pond/omniauth-entra-id/blob/master/README.md) (11%)
[^5]: [Microsoft Entra authentication & national clouds - Microsoft identity platform | Microsoft Learn](https://learn.microsoft.com/en-us/entra/identity-platform/authentication-national-cloud) (10%)
[^6]: [All versions of omniauth-entra-id | RubyGems.org | your community gem host](https://rubygems.org/gems/omniauth-entra-id/versions) (9%)
[^7]: [CHANGELOG.md](https://github.com/pond/omniauth-entra-id/blob/master/CHANGELOG.md) (6%)
[^8]: [openid-configuration](https://login.microsoftonline.us/common/v2.0/.well-known/openid-configuration) (3%)
[^9]: [openid-configuration](https://login.partner.microsoftonline.cn/common/v2.0/.well-known/openid-configuration) (3%)


---

Summary by GPT-5.6-terra:

The `omniauth-entra-id` gem can support sovereign Entra endpoints for normal client-secret flows through its `base_url` option. A separate strategy is not needed.

- Setting `base_url` changes the authorization URL, token URL, and single-tenant issuer validation together. For example, `https://login.microsoftonline.us` produces the matching US Government issuer format.

- The application still needs code changes: expose a fixed, validated cloud/authority option; pass its host as `base_url`; and replace application-level commercial-host assumptions in CSP and connection testing.

- Do not allow arbitrary authority URLs. Map supported clouds to fixed hosts:
  - Commercial: `login.microsoftonline.com`
  - US Government: `login.microsoftonline.us`
  - China: `login.partner.microsoftonline.cn`

- There is one material gem-level gap: certificate-based client authentication constructs its `aud` claim with the commercial host even when `base_url` is sovereign. Sovereign support therefore requires an upstream patch, local patch, or monkey patch if certificate auth is used.

- The gem does not perform discovery or JWKS signature verification itself. Its issuer comparison works for a specific tenant ID, but validation is skipped for `common` and `organizations`; `consumers` is not appropriate for sovereign use.

- Add application integration coverage for both US Government and China authorities. The research was based on the latest published gem (`3.1.1`); confirm the repository’s locked version before relying on its exact behavior.
