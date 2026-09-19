# Security Resolution Log

This append-only log records verified closure of public security findings. Historical audits retain
the original evidence; each entry here identifies the fix and the baseline used to verify closure.

## 2026-09-09

### RISK-2026-08-13-01 — Resolved

- **Finding:** `RABBITMQ_VERIFY_PEER` failed open when an operator supplied any value other than
  the exact string `true`, disabling AMQPS certificate verification.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md)
- **Resolution:** `4b27b3c0dc` routes the setting through
  `Onetime::Utils::Strings.strict_bool!` with a default of `true`.
- **Verification:** `tests/lanes/run simple --only spec/unit/onetime/utils/strings_spec.rb
  --only spec/unit/onetime/initializers/setup_rabbitmq_spec.rb` completed with 192 examples and
  0 failures.
- **Closure baseline:** `999967a` on 2026-09-09.

### OBS-2026-08-13-RESTRICT-TO — Resolved

- **Finding:** The 2026-08-13 audit recorded domain `restrict_to` enforcement as known and
  tracked rather than filing it as a rated finding.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md)
- **Resolution:** `b74175efdb` enforces `restrict_to` across sign-in surfaces; later changes add
  fail-closed handling and coverage.
- **Closure baseline:** `999967a` on 2026-09-09.

## 2026-09-19

### RISK-2026-08-13-02 — Resolved

- **Finding:** A session that had presented a password but not its second factor could read
  `/auth/account`, list and remove active sessions (including every other session of the
  account), and list SSO identities and passkey identifiers, because those routes tested only
  `rodauth.logged_in?`.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md), finding 2;
  carried as open by the [2026-09-09 audit](../audits/security-audit-2026-09-09.md).
- **Resolution:** `a99a07fb27` (merged to `main` in #4483) gates the `/auth` router on the shared
  customer-session verdict. An `awaiting_mfa` session reaches only the second-factor completion
  routes, logout and `GET /auth/mfa-status`; everything else is answered `401` before any route
  runs. The gate is an allowlist, so routes added later (such as the #4419 re-authentication
  pair) are refused by default.
- **Verification:** `295038d24` adds the every-route example the 2026-09-09 audit asked for to
  `apps/web/auth/spec/integration/full_mfa/customer_session_evaluator_mfa_pending_spec.rb`.
  `tests/lanes/run full-mfa` completed with 17 examples and 0 failures. Details in the
  [2026-09-19 review](../audits/security-audit-2026-09-19.md).
- **Closure baseline:** `295038d24` (`feature/4451-auth-session-consistency`) on 2026-09-19.
