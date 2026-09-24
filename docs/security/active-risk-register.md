# Active Security Risk Register

**Last reviewed:** 2026-09-09 · **Code baseline:** `onetimesecret` @ `999967a`

This is the canonical tracker for security work that remains actionable. Dated audits and
historical risk registers preserve evidence; they do not define the current status of a finding.
Source ratings are retained until a new assessment explicitly re-rates a risk.

**Active items:** 20 open · **Accepted exceptions:** none recorded

## How to use this register

- `Open` means remediation or an explicit acceptance decision is required.
- The `ID` is stable across future audits. Source-local labels such as M-1 are retained only for
  traceability.
- A row moves to the [resolution log](records/resolution-log.md) only after a fix or other
  disposition is verified at a named baseline.
- See the [security documentation standard](security-documentation-standard.md) for the complete
  lifecycle and status vocabulary.

## Open risks

| ID | Priority / risk | Status | Risk | Source and required action |
|---|---|---|---|---|
| RISK-2026-08-14-M01 | P2 / High | Open | Explicitly unverified IdP claims can still enable JIT creation or trusted platform email linking; verify-disabled federation remains a concrete residual. | [Historical M-1](risk-registers/risk-register-2026-08-14.md); decide and enforce a safe policy. |
| RISK-2026-08-14-M02 | P2 / Medium-High | Open | Magic links can retain the Rodauth 24-hour deadline and be reused across resends instead of using the configured 15 minutes. | [Historical M-2](risk-registers/risk-register-2026-08-14.md); enable `set_deadline_values?`. |
| RISK-2026-08-14-M11 | P2 / Medium | Open | `sqlite3` 2.9.5 use-after-free (`GHSA-mwm8-39rw-8826`). | [Historical M-11](risk-registers/risk-register-2026-08-14.md); update the lockfile. |
| RISK-2026-08-14-M03 | P3 / Medium | Open | `email-login-request` and direct `verify-account-resend` account enumeration. | [Historical M-3](risk-registers/risk-register-2026-08-14.md); remove the response oracle. |
| RISK-2026-08-14-M04 | P3 / Medium | Open | No source/IP limit on `email-login-request`, enabling mailbox bombing and repeated enumeration. | [Historical M-4](risk-registers/risk-register-2026-08-14.md); limit before account lookup. |
| RISK-2026-08-14-M08 | P3 / Medium | Open | CSP nonce in the bootstrap payload weakens nonce-only CSP once an HTML-injection primitive exists. | [Historical M-8](risk-registers/risk-register-2026-08-14.md); remove the client-visible nonce from the bootstrap path. |
| RISK-2026-08-14-M12 | P3 / Medium | Open | Production image fetches `yq` without digest or signature verification. | [Historical M-12](risk-registers/risk-register-2026-08-14.md); mirror the verified `s6` installation pattern. |
| RISK-2026-08-14-M10 | P3 / Medium | Open | Guest receipt and secret capability identifiers in tab-scoped `sessionStorage` widen the XSS blast radius. | [Historical M-10](risk-registers/risk-register-2026-08-14.md); reduce capability persistence. |
| RISK-2026-08-14-M09 | P3 / Medium | Open | Vendored DNS widget injects remote HTML; an XSS remains conditional on a CSP/nonce bypass. | [Historical M-9](risk-registers/risk-register-2026-08-14.md); remove or safely sanitize remote HTML injection. |
| RISK-2026-08-14-L07 | P3 / Medium | Open | Redis TLS is not enforced or asserted at boot. | [Historical L-7](risk-registers/risk-register-2026-08-14.md); require or assert `rediss://` for remote Redis. |
| RISK-2026-08-14-COOKIE-TOSSING | P3 / Medium | Open | `Rack::Protection::CookieTossing` is off; sibling-subdomain cookie control can survive simple-mode login. | [Historical residual](risk-registers/risk-register-2026-08-14.md); configure the application session key and renew the ID on login. |
| RISK-2026-08-14-L09 | P4 / Low / conditional Medium | Open | Debug HTTP capture can log a raw session cookie; raw emails remain at other log sites. | [Historical L-9](risk-registers/risk-register-2026-08-14.md); redact credentials and email values at every sink. |
| RISK-2026-08-14-L05 | P4 / Low | Open | `brace-expansion` overrides remain below `GHSA-rgw5-rvv9-x895` floors. | [Historical L-5](risk-registers/risk-register-2026-08-14.md); raise pinned versions and correct the rationale. |
| RISK-2026-08-14-L01 | P4 / Low | Open | `RemoveMember` bypasses the entitlement layer and does not confirm that the actor is active. | [Historical L-1](risk-registers/risk-register-2026-08-14.md); use the shared authorization checks. |
| RISK-2026-08-14-M06 | P4 / Low | Open | A domain-scoped member with `audit_logs` can read sibling-domain receipt metadata. | [Historical M-6](risk-registers/risk-register-2026-08-14.md); enforce domain scope on the listing. |
| RISK-2026-08-14-L02 | P4 / Informational | Open | `authorize_domain_incoming!` lacks a domain-scope check while `manage_org` is owner-only. | [Historical L-2](risk-registers/risk-register-2026-08-14.md); add scope enforcement before the role model changes. |
| RISK-2026-08-14-L03 | P4 / Low | Open | The `secret` field accepts an object and persists Ruby `.to_s` rather than enforcing the string schema. | [Historical L-3](risk-registers/risk-register-2026-08-14.md); enforce the request type. |
| RISK-2026-08-14-L08 | P4 / Low | Open | In simple mode, reset-password can burn an arbitrary secret when its identifier is known. | [Historical L-8](risk-registers/risk-register-2026-08-14.md); restrict lookup/burn to reset-password secrets. |
| RISK-2026-08-13-02 | P3 / Low | Open | MFA-incomplete sessions can access account JSON and session-management routes. | [2026-08-13 finding 2](audits/security-audit-2026-08-13.md); require full authentication except for `mfa-status`. |
| RISK-2026-08-13-03 | P3 / Low | Open | SMTP2GO client error bodies reach logs and Sentry without redaction. | [2026-08-13 finding 3](audits/security-audit-2026-08-13.md); redact at the logging boundary or omit response bodies from Sentry. |

## Historical sources

- [2026-08-14 historical risk register](risk-registers/risk-register-2026-08-14.md)
- [2026-08-13 security audit](audits/security-audit-2026-08-13.md)
- [2026-09-09 follow-up audit](audits/security-audit-2026-09-09.md)
