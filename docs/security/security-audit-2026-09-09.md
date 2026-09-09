# Security & Code Audit — 2026-09-09

- **Repo:** onetimesecret/onetimesecret
- **Baseline:** `999967a` (the risk-register revalidation baseline `949d948` is an ancestor; the only later changes are documentation)
- **Method:** Targeted follow-up of the unresolved items in the 2026-08-14 application-security risk register and the findings/explicit residuals from the 2026-08-13 security audit. Current source was read for the cross-audit items. `AUTHENTICATION_MODE=simple bundle exec rspec spec/unit/onetime/utils/strings_spec.rb spec/unit/onetime/initializers/setup_rabbitmq_spec.rb` passed: 192 examples, 0 failures.
- **Scope limit:** This is a disposition audit, not a fresh broad source or dependency audit. It preserves the 2026-08-14 ratings without re-ranking them; it is the current tracker for the findings carried forward from that historical register.

---

## Bottom line

The 2026-08-13 **High** RabbitMQ TLS finding is resolved. `RABBITMQ_VERIFY_PEER` now uses strict boolean parsing: valid case- and whitespace-insensitive truthy/falsey tokens work as expected, unset defaults to peer verification, and an unrecognized token raises rather than disabling verification.

The 2026-08-13 **Low** MFA-incomplete-session and SMTP2GO error-body findings remain open. The 18 unresolved findings from the 2026-08-14 register are carried forward below, making this document their active tracker. Its M-1 residual also remains directly supported by current source.

No new finding is filed by this targeted review.

---

## Resolved since the cited audits

### 1. RESOLVED — `RABBITMQ_VERIFY_PEER` no longer fails open

**Source:** 2026-08-13 finding 1 (High)

**Fix:** `4b27b3c0dc` (2026-08-14, `Standardize boolean config parsing; fix RABBITMQ_VERIFY_PEER failing open (#4160)`)

`Onetime::Jobs::QueueConfig.tls_options` now calls
`Onetime::Utils::Strings.strict_bool!('RABBITMQ_VERIFY_PEER', ..., default: true)` for
`amqps://` URLs. The shared parser accepts the documented token vocabulary after trimming
and lowercasing, preserves the secure default when the variable is unset/blank, and raises
`Onetime::ConfigError` for an unrecognized value. The dedicated queue-config specs cover
`TRUE`, padded `True`, `1`, `yes`, falsey tokens, and an invalid token; the utility specs
cover the full vocabulary and non-disclosure of rejected values.

This removes the prior misconfiguration path where a spelling such as `TRUE`, `1`, or `yes`
silently set `verify_peer: false`.

### 2. RESOLVED — domain `restrict_to` is server-enforced

**Source:** 2026-08-13 “Known and tracked — deliberately not re-filed”

**Fix:** `b74175efdb` (2026-08-11, `feat(auth): enforce restrict_to as access control on every sign-in surface`), with subsequent fail-closed and coverage follow-ups.

`Auth::RestrictTo` now rejects restricted-away Rodauth pre-auth routes at `before_rodauth`.
The hook also covers the multi-phase magic-link dispatch path. Tenant OmniAuth setup checks
both request and callback phases, and the policy module documents separate handling for the
app-owned SSO linking routes and simple-mode login. A blocked method receives the shared
404 shape; an unreadable policy raises to the configured 503 path instead of being treated as
unrestricted.

---

## Outstanding findings from the 2026-08-13 audit

### 1. LOW — MFA-incomplete sessions can still call account JSON and session-management routes

`apps/web/auth/routes/active_sessions.rb`, `account.rb`, `identities.rb`, and
`webauthn_credentials.rb` continue to authorize their relevant routes with
`rodauth.logged_in?`. That is true after first-factor completion, while the separate
`session['awaiting_mfa']` flag remains true. In particular, the routes still allow a
partially authenticated caller to list or remove active sessions, remove all sessions except
its current session, read account posture, list SSO identities, and list passkey identifiers.

`GET /auth/mfa-status` must remain available in this state for the challenge UI. The other
routes need a full-authentication gate, preferably at a shared router helper, before this
finding can be closed.

### 2. LOW — SMTP2GO client error bodies still reach logs and Sentry without redaction

`Onetime::Mail::Smtp2goClient#handle_response` still attaches raw response bodies to
`APIError` for invalid JSON, 2xx error envelopes, and non-2xx responses.
`Onetime::Mail::Delivery::Smtp2go#log_error` copies `error.response_body` into both the
structured log message and Sentry `smtp2go_error` context without calling `redact_emails`.

The delivery-layer errors raised for per-recipient failures are redacted, but that does not
cover errors raised by the client. Apply redaction at `log_error` before emitting either sink,
or remove response bodies from the Sentry context, before closing this finding.

### 3. TRACKED RESIDUAL — unverified federated-subscription claims in verify-disabled deployments

**Cross-reference:** 2026-08-14 risk register M-1; 2026-08-13 known-and-tracked residual.

The standard signup path sets `require_verification` from
`Onetime.auth_config.verify_account_enabled?`. When account verification is disabled, an
unverified signup can still claim a matching pending federated subscription. The current
implementation records a structured security-audit event rather than blocking the claim,
because `verified?` cannot become true in that configuration and an unconditional block would
disable federation there.

The platform trusted-provider email-linking exception remains separately operator-gated; this
review did not find evidence that it turns an explicit IdP `email_verified: false` claim into a
rejection. M-1 therefore remains open as rated in the risk register.

---

## Carried-forward risks from the 2026-08-14 register

This is the active tracker for every finding that was unresolved at `949d948`. The original
ratings and priorities are retained without re-assessment. `git diff --name-status
949d948..999967a` contains only `CHANGELOG.rst` and the risk-register document itself, so no
post-revalidation implementation change supports closing any of them.

| ID | Outstanding risk | Original priority / risk | Required disposition |
|---|---|---|---|
| M-1 | Explicitly unverified IdP claims can still enable JIT creation or trusted platform email linking; verify-disabled federation remains a concrete residual. | P2 / High | Open; product/security policy decision and enforcement. |
| M-2 | Magic links can retain the Rodauth 24-hour deadline and be reused across resends instead of using the configured 15 minutes. | P2 / Medium-High | Open; enable `set_deadline_values?`. |
| M-11 | `sqlite3` 2.9.5 use-after-free (`GHSA-mwm8-39rw-8826`). | P2 / Medium | Open; update the lockfile. |
| M-3 | `email-login-request` and direct `verify-account-resend` account enumeration. | P3 / Medium | Open; remove the response oracle. |
| M-4 | No source/IP limit on `email-login-request`, enabling mailbox bombing and repeated enumeration. | P3 / Medium | Open; apply a source/IP limiter before account lookup. |
| M-8 | CSP nonce in the bootstrap payload weakens nonce-only CSP once an HTML-injection primitive exists. | P3 / Medium | Open; remove the client-visible nonce from the bootstrap path. |
| M-12 | Production image fetches `yq` without digest or signature verification. | P3 / Medium | Open; mirror the verified `s6` installation pattern. |
| M-10 | Guest receipt and secret capability identifiers in tab-scoped `sessionStorage` widen the XSS blast radius. | P3 / Medium | Open; reduce capability persistence. |
| M-9 | Vendored DNS widget injects remote HTML; an XSS remains conditional on a CSP/nonce bypass. | P3 / Medium | Open; remove or safely sanitize remote HTML injection. |
| L-7 | Redis TLS is not enforced or asserted at boot. | P3 / Medium | Open; require or assert `rediss://` for remote Redis. |
| — | `Rack::Protection::CookieTossing` is off; sibling-subdomain cookie control can survive simple-mode login. | P3 / Medium | Open; configure the application session key and renew the ID on login. |
| L-9 | Debug HTTP capture can log a raw session cookie; raw emails remain at other log sites. | P4 / Low / conditional Medium | Open; remove or redact credential and email values at every sink. |
| L-5 | `brace-expansion` overrides remain below `GHSA-rgw5-rvv9-x895` floors. | P4 / Low | Open; raise the pinned versions and correct the rationale. |
| L-1 | `RemoveMember` bypasses the entitlement layer and does not confirm the actor is active. | P4 / Low | Open; use the shared authorization checks. |
| M-6 | A domain-scoped member with `audit_logs` can read sibling-domain receipt metadata. | P4 / Low | Open; enforce domain scope on the listing. |
| L-2 | `authorize_domain_incoming!` lacks a domain-scope check while `manage_org` is owner-only. | P4 / Informational | Open; add scope enforcement before the role model changes. |
| L-3 | The `secret` field accepts an object and persists Ruby `.to_s` rather than enforcing the string schema. | P4 / Low | Open; enforce the request type. |
| L-8 | In simple mode, reset-password can burn an arbitrary secret when its identifier is known. | P4 / Low | Open; restrict lookup/burn to reset-password secrets. |

The [August 14 register](2026-08-14-appsec-review/risk-register.md) is now a historical
assessment and points here for each carried-forward item.

---

## Rational follow-up updates

1. **No additional risk-register move is needed.** The August 14 register is historical and
   links to this active tracker for every carried-forward finding.
2. **When the MFA and SMTP2GO findings are fixed, add focused regression coverage before
   recording closure:** a first-factor-only session must be rejected by every account/session
   route except `mfa-status`; client-originated SMTP2GO response text containing an address
   must be masked in both the log message and Sentry context.
3. **Keep the RabbitMQ closure in this dated audit rather than adding it to the August 14
   register.** It originated in the August 13 audit and was not one of the register’s entries.
