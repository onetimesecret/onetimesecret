# Security & Code Audit — 2026-09-09

- **Repo:** onetimesecret/onetimesecret
- **Baseline:** `999967a` (the risk-register revalidation baseline `949d948` is an ancestor; the only later changes are documentation)
- **Method:** Targeted follow-up of the unresolved items in the 2026-08-14 application-security risk register and the findings/explicit residuals from the 2026-08-13 security audit. Current source was read for the cross-audit items. `AUTHENTICATION_MODE=simple bundle exec rspec spec/unit/onetime/utils/strings_spec.rb spec/unit/onetime/initializers/setup_rabbitmq_spec.rb` passed: 192 examples, 0 failures.
- **Scope limit:** This is a disposition audit, not a fresh broad source or dependency audit. It preserves the 2026-08-14 ratings without re-ranking them.

> **Historical record.** This report records the 2026-09-09 review. The [active security risk register](../active-risk-register.md) is the canonical status of every actionable finding.

---

## Bottom line

The 2026-08-13 **High** RabbitMQ TLS finding is resolved. `RABBITMQ_VERIFY_PEER` now uses strict boolean parsing: valid case- and whitespace-insensitive truthy/falsey tokens work as expected, unset defaults to peer verification, and an unrecognized token raises rather than disabling verification.

The 2026-08-13 **Low** MFA-incomplete-session and SMTP2GO error-body findings remained open at this baseline. The 18 unresolved findings from the 2026-08-14 register and these two audit findings were migrated to the [active security risk register](../active-risk-register.md). Its M-1 residual also remained directly supported by current source.

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

## Current disposition

At this baseline, the unresolved August 14 risks and the two open August 13 findings were
migrated to the [active security risk register](../active-risk-register.md). The register retains
the original ratings and stable source references; this report remains the historical evidence for
this review.

---

## Rational follow-up updates

1. **Current status is maintained in the active register.** The August 14 register and this audit
   are historical records and link there for every carried-forward finding.
2. **When the MFA and SMTP2GO findings are fixed, add focused regression coverage before
   recording closure:** a first-factor-only session must be rejected by every account/session
   route except `mfa-status`; client-originated SMTP2GO response text containing an address
   must be masked in both the log message and Sentry context.
3. **Keep the RabbitMQ closure in this dated audit rather than adding it to the August 14
   register.** It originated in the August 13 audit and was not one of the register’s entries.
