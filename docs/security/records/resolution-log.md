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
- **Verification:** `AUTHENTICATION_MODE=simple bundle exec rspec
  spec/unit/onetime/utils/strings_spec.rb spec/unit/onetime/initializers/setup_rabbitmq_spec.rb`
  completed with 192 examples and 0 failures.
- **Closure baseline:** `999967a` on 2026-09-09.

### OBS-2026-08-13-RESTRICT-TO — Resolved

- **Finding:** The 2026-08-13 audit recorded domain `restrict_to` enforcement as known and
  tracked rather than filing it as a rated finding.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md)
- **Resolution:** `b74175efdb` enforces `restrict_to` across sign-in surfaces; later changes add
  fail-closed handling and coverage.
- **Closure baseline:** `999967a` on 2026-09-09.
