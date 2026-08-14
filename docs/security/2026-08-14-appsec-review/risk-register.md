# Risk Register

**Date:** 2026-08-14 · **Target:** `onetimesecret` @ `21c3f6a`

**Exploitability** — how hard is it to actually do?
`Trivial` (unauthenticated, single request) · `Easy` (needs a low-privilege account or a session) ·
`Moderate` (needs a specific configuration or a chained precondition) · `Hard` (needs privileged
position or an unlikely precondition)

**Business impact** — what happens if it succeeds?
`Severe` (core product promise broken / total tenant compromise) · `High` (material data or money
loss) · `Moderate` (degraded trust or availability) · `Low` (hygiene)

---

## Priority 1 — fix now

| # | ID | Finding | Exploitability | Impact | Risk | Effort |
|---|---|---|---|---|---|---|
| 1 | H-2 | Non-owner member reaches the org's Stripe Customer Portal (can cancel the subscription, change payment method, read billing history) | Easy | High | **Critical** | Trivial — one `require_owner: true` |
| 2 | H-1 | Any org member harvests every colleague's secret bearer tokens and reveals their secrets | Easy | Severe | **Critical** | Small — redact non-owned identifiers, raise the entitlement |
| 3 | H-3 | Tenant SSO `allowed_domains` never runs; operators believe an access control exists that does not | Moderate (needs a tenant OIDC config) | Severe | **High** | Small — call the method, both paths, fail closed |

**Why these three first.** Each one is an authorization gap that is cheap to close, and each defeats
a control the product explicitly advertises. H-2 has the lowest effort-to-risk ratio in the whole
register. H-1 breaks the core product promise from inside the tenant. H-3 is the most dangerous kind
of finding — a security control that exists in the UI, the API, and the docs, but not at runtime.

---

## Priority 2 — fix this cycle

| # | ID | Finding | Exploitability | Impact | Risk | Effort |
|---|---|---|---|---|---|---|
| 4 | M-14 | "Remove session" reports success but the session keeps working; no absolute session lifetime | Hard (needs an already-compromised session) | High | **High** | Medium |
| 5 | M-1 | `email_verified` never checked; nOAuth-class takeover if a trust flag + `ENTRA_TENANT_ID=common` are set | Moderate (config-dependent) | Severe | **High** | Small |
| 6 | M-7 | Unauthenticated Redis exhaustion — no rate limit on secret creation | **Trivial** | Moderate (full outage) | **High** | Small — add a limiter to the existing registry |
| 7 | M-5 | Stripe invoice PDFs / hosted bearer URLs exposed to any org member | Easy | High | **High** | Trivial |
| 8 | M-2 | Magic links live 24h instead of the configured 15 min, and one token is reused across resends | Moderate (needs link interception) | High | **Medium-High** | Trivial — `set_deadline_values? true` |
| 9 | M-6 | Domain-scoped SSO member reads a sibling domain's receipts (chains into H-1) | Easy | High | **Medium-High** | Trivial |
| 10 | M-11 | `sqlite3` 2.9.5 use-after-free (GHSA-mwm8-39rw-8826) | Hard | Moderate | **Medium** | Trivial — lockfile bump only |
| 11 | M-13 | `claude-code-action@beta` mutable ref holds `CLAUDE_CODE_OAUTH_TOKEN` + `id-token: write` | Hard (needs upstream compromise) | Severe | **Medium** | Trivial — SHA-pin |

---

## Priority 3 — schedule

| # | ID | Finding | Exploitability | Impact | Risk | Effort |
|---|---|---|---|---|---|---|
| 12 | M-3 | Account enumeration on `email-login-request` / `verify-account-resend` | Easy (CSRF token required first) | Moderate | Medium | Small |
| 13 | M-4 | No rate limit on `email-login-request` → mailbox bombing + unbounded enumeration | Easy | Moderate | Medium | Small |
| 14 | M-8 | CSP nonce published in the bootstrap payload, weakening the nonce-only policy | Hard (needs an HTML-injection primitive) | High | Medium | Trivial |
| 15 | M-12 | `yq` installed into production images with no checksum | Hard | Severe | Medium | Trivial — mirror the s6 block |
| 16 | M-10 | Secret bearer tokens in `sessionStorage` (widens XSS blast radius) | Hard (needs XSS) | High | Medium | Medium |
| 17 | M-9 | Vendored DNS widget injects unsanitized remote HTML (CSP is the only thing stopping it) | Hard | High | Medium | Small |
| 18 | §4 | Blanket `/auth/sso/*` CSRF prefix exemption; connect-intent nonce forgeable cross-site | Moderate | Moderate | Medium | Small |

---

## Priority 4 — hygiene backlog

| # | ID | Finding | Risk |
|---|---|---|---|
| 19 | L-9 | `request_logger.rb:97` logs `sid.public_id` — the raw session cookie value — under `LOG_HTTP_CAPTURE=debug`; raw emails in 3 log sites | Low-Medium |
| 20 | L-5 | `brace-expansion` overrides one patch below GHSA-rgw5-rvv9-x895; the "false positive" comment is now stale and misleading | Low |
| 21 | L-1 | `RemoveMember` skips the entitlement layer and the actor's `active?` check | Low |
| 22 | L-4 | `isValidInternalPath` accepts `/\evil.com` (latent open redirect — no reachable sink today) | Low |
| 23 | L-7 | Redis TLS neither enforced nor asserted at boot; no ACL requirement documented | Low |
| 24 | L-6 | `actions/*` pinned by mutable tag while others are SHA-pinned | Low |
| 25 | L-2 | `authorize_domain_incoming!` omits the domain-scope check (latent) | Low |
| 26 | L-3 | `secret` field accepts a JSON object and stores its Ruby `.to_s` — request schema not type-enforced | Low |
| 27 | L-8 | Simple mode: reset-password burns an arbitrary secret by identifier (destruction only) | Low |
| 28 | — | `Rack::Protection::CookieTossing` ships off; pre-auth session fixation via a sibling-subdomain cookie | Low |

---

## Notes on what is *not* in this register

Four claims that read as Critical from source alone were empirically refuted against the running
application and are **not** risks: predictable session IDs, missing `HttpOnly`, session id accepted
from request params, and missing cookie `Path`. See `findings.md` §5 for the verification output.
They are recorded there specifically so a future review does not re-open them.

The core product invariant — burn-after-reading — was tested under concurrency and **holds**
(1 of 10 simultaneous reveals returned plaintext). Passphrase brute-force protection **holds**,
including against `X-Forwarded-For` rotation. These are the two controls the product most depends on,
and both are sound.
