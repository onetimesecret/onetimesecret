# Risk Register

**Assessment date:** 2026-08-14 · **Assessment target:** `onetimesecret` @ `21c3f6a`

**Revalidated:** 2026-09-09 · **Current baseline:** `onetimesecret` @ `949d948` (v0.26.12)

**Exploitability** — how hard is it to actually do?
`Trivial` (unauthenticated, single request) · `Easy` (needs a low-privilege account or a session) ·
`Moderate` (needs a specific configuration or a chained precondition) · `Hard` (needs privileged
position or an unlikely precondition)

**Business impact** — what happens if it succeeds?
`Severe` (core product promise broken / total tenant compromise) · `High` (material data or money
loss) · `Moderate` (degraded trust or availability) · `Low` (hygiene)

---

## Priority 1 — fix now

No open Priority 1 risks remain at the revalidation baseline. H-1, H-2, and H-3 are resolved below.

---

## Resolved since this assessment

| ID | Finding | Resolution |
|---|---|---|
| H-1 | Any org member can harvest colleagues' secret bearer tokens | Resolved: shared receipt listings require `audit_logs` and redact all non-owner capability fields. |
| H-2 | Non-owner member reaches the org's Stripe Customer Portal | Resolved: the portal handler requires ownership of the resolved organization before creating a Stripe portal session. |
| H-3 | Tenant SSO `allowed_domains` never runs | Resolved: every tenant callback validates the asserted email through `SsoConfig#valid_email_domain?` and fails closed. |
| M-5 | Stripe invoice PDFs / hosted bearer URLs exposed to any org member | Resolved: invoice listing requires organization ownership. |
| M-7 | Unauthenticated Redis exhaustion — no rate limit on secret creation | Resolved: anonymous secret creation is rate-limited before receipt creation across V1/V2/V3. |
| L-4 | `isValidInternalPath` accepts `/\evil.com` | Resolved: raw and percent-decoded backslashes are rejected. |
| L-6 | `actions/*` pinned by mutable tag while others are SHA-pinned | Resolved: the cited actions are now pinned by SHA. |
| M-13 | `claude-code-action@beta` mutable ref holds `CLAUDE_CODE_OAUTH_TOKEN` + `id-token: write` | Resolved: both Claude Code workflows pin `anthropics/claude-code-action` to commit `28f83620103c48a57093dcc2837eec89e036bb9f`. |
| M-14 | "Remove session" reports success but the session keeps working; no absolute session lifetime | Resolved in v0.26.12: full-mode authenticated requests verify the active-session row, and configured inactivity and absolute deadlines are enforced on every request. |

---

## Retired after revalidation

- **§4 — blanket `/auth/sso/*` CSRF prefix exemption / forgeable connect intent.** The current
  baseline refutes the reported cross-site scenario: OAuth state is bound through the single
  `session['omniauth.state']` slot, connect intents are account-bound and consumed once, and the
  auth profile checks `HttpOrigin`. The token-CSRF prefix exemption remains a defense-in-depth
  observation for requests without an `Origin` header, not a rated current risk.

---

## Priority 2 — fix this cycle

| # | ID | Finding | Exploitability | Impact | Risk | Effort |
|---|---|---|---|---|---|---|
| 1 | M-1 | An explicit unverified IdP email claim only withholds the local verified stamp; it does not reject JIT creation or trusted platform email auto-linking | Moderate (config-dependent) | Severe | **High** | Small |
| 2 | M-2 | Magic links live 24h instead of the configured 15 min, and one token is reused across resends | Moderate (needs link interception) | High | **Medium-High** | Trivial — `set_deadline_values? true` |
| 3 | M-11 | `sqlite3` 2.9.5 use-after-free (GHSA-mwm8-39rw-8826) | Hard | Moderate | **Medium** | Trivial — lockfile bump only |

---

## Priority 3 — schedule

| # | ID | Finding | Exploitability | Impact | Risk | Effort |
|---|---|---|---|---|---|---|
| 4 | M-3 | Account enumeration on `email-login-request` / direct `verify-account-resend` | Easy (CSRF token required first) | Moderate | Medium | Small |
| 5 | M-4 | No source/IP rate limit on `email-login-request` → mailbox bombing of eligible accounts and repeated enumeration | Easy | Moderate | Medium | Small |
| 6 | M-8 | CSP nonce published in the bootstrap payload, weakening the nonce-only policy when an HTML-injection primitive exists | Hard | High | Medium | Trivial |
| 7 | M-12 | `yq` installed into production images without digest or signature verification | Hard | Severe | Medium | Trivial — mirror the s6 block |
| 8 | M-10 | Up to 25 guest receipt and secret capability identifiers in tab-scoped `sessionStorage` widen an XSS blast radius | Hard (needs XSS) | High | Medium | Medium |
| 9 | M-9 | Vendored DNS widget injects remote HTML; XSS is conditional on a CSP/nonce bypass | Hard | High | Medium | Small |
| 10 | L-7 | Redis TLS is not enforced or asserted at boot; remote plaintext Redis exposes credentials, session bearer values, and traffic | Moderate (remote/untrusted network) | High | Medium | Small |
| 11 | — | `Rack::Protection::CookieTossing` ships off; a sibling-subdomain cookie can survive the default simple-mode login flow | Moderate (sibling-subdomain control) | High | Medium | Medium — configure the application session key and renew the ID on login |

---

## Priority 4 — hygiene backlog

| # | ID | Finding | Risk |
|---|---|---|---|
| 12 | L-9 | `request_logger.rb` logs the raw session cookie value under `LOG_HTTP_CAPTURE=debug`; raw emails remain in three log sites | Low for emails; Medium conditional on debug/trace capture and log access for session bearer values |
| 13 | L-5 | `brace-expansion` overrides remain one patch below GHSA-rgw5-rvv9-x895; the "false positive" comment is stale | Low |
| 14 | L-1 | `RemoveMember` skips the entitlement layer and the actor's `active?` check | Low |
| 15 | M-6 | A domain-scoped member with `audit_logs` can read sibling-domain receipt metadata; non-owner capability fields are redacted | Low |
| 16 | L-2 | `authorize_domain_incoming!` omits the domain-scope check; latent while `manage_org` remains owner-only | Informational |
| 17 | L-3 | `secret` field accepts a JSON object and stores its Ruby `.to_s` — request schema not type-enforced | Low |
| 18 | L-8 | Default simple mode: reset-password burns an arbitrary secret by identifier (destruction only) | Low |

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
