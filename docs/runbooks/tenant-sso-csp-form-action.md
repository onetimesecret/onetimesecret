# Custom-domain SSO button does nothing (CSP `form-action`)

## Symptom

On a custom domain, clicking the tenant SSO button appears to do nothing. The
visitor's browser console reports a Content-Security-Policy violation naming
`form-action`. Chromium-family browsers (Chrome, Edge) enforce `form-action`
across the whole redirect chain; Firefox only checks the initial same-origin
form target, so the same account signs in fine there. Nothing is logged
server-side by the request itself — the POST is never sent.

## What normally happens

The sign-in page POSTs to `/auth/sso/{provider}`, which 302s to the domain's
IdP. `Onetime::Middleware::TenantCspExtras` resolves the display domain's
enabled SSO config on the way out of each HTML response and adds that config's
IdP origin to `form-action`, for that domain's response only:

| Tenant `provider_type` | Origin added                                      |
| :--------------------- | :------------------------------------------------ |
| `oidc`                 | Origin of the SSO config's `issuer`               |
| `entra_id`             | `https://login.microsoftonline.com` (static)      |

No environment configuration is involved. The origin follows the stored
per-domain SSO config automatically (#4173).

## Log signals

Grep the app log for `TenantCspExtras`. Three lines matter:

**1. Tenant SSO is on, but its origin was rejected** — the button renders and
the redirect is blocked. This is the operator-actionable one:

```
[TenantCspExtras] tenant SSO is available but its IdP origin failed validation
for "secrets.example.com" (provider_type="oidc", issuer="…"); form-action not widened
```

The tenant's issuer is present but did not survive validation: not `http(s)`,
not a parseable URL, or a CSP-hostile host. Fix the `issuer` on the domain's
SSO config (`GET/PUT /api/v2/domains/:extid/sso`, or the domain's SSO settings
screen). The issuer is echoed truncated to 100 characters and escaped — it is
tenant-supplied, so read it as data, not as a trustworthy value.

Warned **once per custom domain per process**. A restart re-arms it; absence of
the line in a long-running process does not mean the condition cleared.

**2. The resolution itself blew up** — degraded to no widening for that
response:

```
[TenantCspExtras] skipping CSP widening for "secrets.example.com": <ErrorClass>: <message>
```

Usually a datastore blip during the SSO-config read. Transient and
self-healing; if it persists, treat it as a datastore problem, not an SSO
problem. Frequently paired with:

```
[TenantSsoResolution] datastore error resolving domain_id for domain=secrets.example.com: <ErrorClass>
```

**Silence is the normal state** for every other miss: no custom domain, no SSO
config, SSO disabled or not permitted for the domain, and a blank issuer. Those
paths are not misconfigurations that CSP can observe, so they log nothing —
do not read a quiet log as "the widening worked".

## Verify from outside

```bash
curl -sI https://secrets.example.com/signin | grep -i content-security-policy
```

The `form-action` directive should list `'self'` plus the domain's IdP origin.
Compare against the canonical host's `/signin`, which should NOT carry the
tenant origin — the widening is per-domain by design, and seeing a tenant IdP
on the canonical host means someone widened it globally with
`SSO_FORM_ACTION_ORIGINS`.

If the header carries no `form-action` at all, check
`site.security.csp.enabled` before going further.

## Resolve by cause

| Cause                                                                                   | Fix                                                                                                                                                        |
| :-------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sovereign-cloud Entra configured as `provider_type: entra_id`                            | Reconfigure the domain as `oidc` with the sovereign issuer (e.g. `https://login.microsoftonline.us/{tenant_id}/v2.0`). Tenant `entra_id` always redirects to the commercial cloud; no env override changes that. See `docs/authentication/per-install-sso.md`. |
| OIDC issuer origin ≠ `authorization_endpoint` origin (split endpoints, v1-style issuers) | Add the **authorization endpoint's** origin to `SSO_FORM_ACTION_ORIGINS`. CSP checks the destination, the derivation reads the issuer.                       |
| Bad/typo'd issuer (signal 1 above)                                                        | Correct the issuer on the domain's SSO config. No restart needed — resolution is per request.                                                               |
| Datastore unreachable while rendering (signal 2 above)                                    | Restore the datastore. `SSO_FORM_ACTION_ORIGINS` is the manual fallback only where this availability risk must not block sign-in.                            |
| Domain has SSO configured but not enabled/permitted                                       | Nothing to fix in CSP — the button should not be rendering either. Check the domain's SSO config `enabled` flag and its entitlement.                         |

`SSO_FORM_ACTION_ORIGINS` is process-wide: it widens CSP for every page, every
tenant, and the canonical host. Use it only for a named exception, with the
exact origin:

```bash
SSO_FORM_ACTION_ORIGINS="https://auth.example.gov"
```

## Not this runbook

A `403` with `attack prevented by Rack::Protection::HttpOrigin` on
`POST /auth/sso/{provider}` is a different failure: `HttpOrigin` validates the
request's **source**, CSP `form-action` validates the IdP **destination**. See
the custom-domain 403 section in `docs/authentication/per-domain-sso.md`
(#4170).
