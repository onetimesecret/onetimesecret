# Active Security Risk Register

**Last reviewed:** 2026-09-19 · **Code baseline:** `onetimesecret` @ `2134b86ab` (`feature/4463-browser-specs-release-gate`)

This is the canonical tracker for security work that remains actionable. Dated audits and
historical risk registers preserve evidence; they do not define the current status of a finding.
Source ratings are retained until a new assessment explicitly re-rates a risk.

**Active items:** 19 existing items · 1 open investigation (severity unconfirmed) · **Accepted exceptions:** none recorded

**Targeted update:** 2026-10-03 — added report 4c3c below; existing items were not reassessed.

**Targeted update:** 2026-10-07 — RISK-2026-08-14-M11 moved to the [resolution log](records/resolution-log.md); tracking issues recorded for M01 (#4688) and M02 (#4689). Other items were not reassessed.

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
| RISK-2026-08-14-M01 | P2 / High | Open | Explicitly unverified IdP claims can still enable JIT creation or trusted platform email linking; verify-disabled federation remains a concrete residual. | [Historical M-1](risk-registers/risk-register-2026-08-14.md); decide and enforce a safe policy. Tracking: #4688. |
| RISK-2026-08-14-M02 | P2 / Medium-High | Open | Magic links can retain the Rodauth 24-hour deadline and be reused across resends instead of using the configured 15 minutes. | [Historical M-2](risk-registers/risk-register-2026-08-14.md); enable `set_deadline_values?`. Tracking: #4689. |
| RISK-2026-08-14-M03 | P3 / Medium | Open | `email-login-request` and direct `verify-account-resend` account enumeration. | [Historical M-3](risk-registers/risk-register-2026-08-14.md); remove the response oracle. |
| RISK-2026-08-14-M04 | P3 / Medium | Open | No source/IP limit on `email-login-request`, enabling mailbox bombing and repeated enumeration. | [Historical M-4](risk-registers/risk-register-2026-08-14.md); limit before account lookup. |
| RISK-2026-08-14-M08 | P3 / Medium | Open | CSP nonce in the bootstrap payload weakens nonce-only CSP once an HTML-injection primitive exists. | [Historical M-8](risk-registers/risk-register-2026-08-14.md); remove the client-visible nonce from the bootstrap path. |
| RISK-2026-08-14-M12 | P3 / Medium | Open | Production image fetches `yq` without digest or signature verification. | [Historical M-12](risk-registers/risk-register-2026-08-14.md); mirror the verified `s6` installation pattern. |
| RISK-2026-08-14-M10 | P3 / Medium | Open | Guest receipt and secret capability identifiers in tab-scoped `sessionStorage` widen the XSS blast radius. | [Historical M-10](risk-registers/risk-register-2026-08-14.md); reduce capability persistence. |
| RISK-2026-08-14-M09 | P3 / Medium | Open | Vendored DNS widget injects remote HTML; an XSS remains conditional on a CSP/nonce bypass. | [Historical M-9](risk-registers/risk-register-2026-08-14.md); remove or safely sanitize remote HTML injection. |
| RISK-2026-08-14-L07 | P3 / Medium | Open | Redis TLS is not enforced or asserted at boot. | [Historical L-7](risk-registers/risk-register-2026-08-14.md); require or assert `rediss://` for remote Redis. |
| RISK-2026-08-14-COOKIE-TOSSING | P3 / Medium | Mitigating | `Rack::Protection::CookieTossing` was off; sibling-subdomain cookie control can survive simple-mode login. | [Historical residual](risk-registers/risk-register-2026-08-14.md); configure the application session key and renew the ID on login. Change 2026-09-28 (#4466): `site.middleware.cookie_tossing` defaults on, mounted as `Onetime::Middleware::CookieTossing` (`lib/onetime/middleware/cookie_tossing.rb`), which binds the gem's check to `site.session.key` and gives it per-request state (rack-protection 4.2.1 keeps its bad-cookie list on the middleware instance, so one refused request would refuse every later one). A request with two session cookies is refused with `403` in either order (`spec/integration/full/customer_session_continuation_baseline_spec.rb`, `spec/unit/onetime/middleware/cookie_tossing_spec.rb`). The gem's own cookie clear is host-scoped (an empty cookie with domain = request host, one per path prefix) and would leave a cookie planted with a parent `Domain=` attribute in place; `Onetime::Middleware::CookieTossing#remove_bad_cookies` emits the same clear for every parent domain of the request host with at least two labels, so one refused request clears both the planted cookie and the legitimate one and the next request starts a fresh session (`spec/unit/onetime/middleware/cookie_tossing_spec.rb`). Change 2026-10-03 (PR #4623): mounted inside `Onetime::Middleware::Security`, the refusal ran below `Onetime::Session`, which loaded the first cookie's session and, committing on the way out, set that session's cookie again after the clears; a browser applying them in order kept it, so a planted first cookie naming a live session outlived the refusal (reproduced in `spec/integration/full/customer_session_continuation_baseline_spec.rb`). `MiddlewareStack` now mounts `CookieTossing` directly above `Onetime::Session`, so a refused request loads no session and its `403` carries only the clears, and the clears are scoped to the host `Rack::DetectHost` resolved rather than the `Host` header, so they reach the browser behind a proxy that rewrites `Host`. Still open: the simple-mode login does not renew the ID (`apps/web/core/controllers/authentication.rb`, `perform_authentication`, says it "deliberately does not clear or renew the session"; the full-mode `login_session` and now the MFA completion do). Close when the specs pass in CI and the simple-mode renewal lands. |
| RISK-2026-08-14-L09 | P4 / Low / conditional Medium | Open | Raw emails remain at some log sites. (The raw session id in debug HTTP capture is fixed.) | [Historical L-9](risk-registers/risk-register-2026-08-14.md); redact credentials and email values at every sink. Reviewed [2026-09-19](audits/security-audit-2026-09-19.md): the session-store and sign-in/sign-out lines now log a handle, and since `1e76be0cc` so do the logic-class lines (simple-mode sign-in, password reset, passphrase failure) and every `Auth::Logging` event, which that review had missed. Since `0a1762239` `LOG_HTTP_CAPTURE=debug` records `session_handle` too, so no log site writes a raw session id. Raw emails remain at other sites, which keeps this row open. Rating unchanged. |
| RISK-2026-08-14-L05 | P4 / Low | Open | `brace-expansion` overrides remain below `GHSA-rgw5-rvv9-x895` floors. | [Historical L-5](risk-registers/risk-register-2026-08-14.md); raise pinned versions and correct the rationale. |
| RISK-2026-08-14-L01 | P4 / Low | Open | `RemoveMember` bypasses the entitlement layer and does not confirm that the actor is active. | [Historical L-1](risk-registers/risk-register-2026-08-14.md); use the shared authorization checks. |
| RISK-2026-08-14-M06 | P4 / Low | Open | A domain-scoped member with `audit_logs` can read sibling-domain receipt metadata. | [Historical M-6](risk-registers/risk-register-2026-08-14.md); enforce domain scope on the listing. |
| RISK-2026-08-14-L02 | P4 / Informational | Open | `authorize_domain_incoming!` lacks a domain-scope check while `manage_org` is owner-only. | [Historical L-2](risk-registers/risk-register-2026-08-14.md); add scope enforcement before the role model changes. |
| RISK-2026-08-14-L03 | P4 / Low | Open | The `secret` field accepts an object and persists Ruby `.to_s` rather than enforcing the string schema. | [Historical L-3](risk-registers/risk-register-2026-08-14.md); enforce the request type. |
| RISK-2026-08-14-L08 | P4 / Low | Open | In simple mode, reset-password can burn an arbitrary secret when its identifier is known. | [Historical L-8](risk-registers/risk-register-2026-08-14.md); restrict lookup/burn to reset-password secrets. |
| RISK-2026-08-13-03 | P3 / Low | Open | SMTP2GO client error bodies reach logs and Sentry without redaction. | [2026-08-13 finding 3](audits/security-audit-2026-08-13.md); redact at the logging boundary or omit response bodies from Sentry. |
| RISK-2026-09-19-02 | P4 / Low | Mitigating | Completing the second factor did not renew the session ID; only the password step did. The other establishment paths #4466 names (account switching, impersonation, SSO callbacks, autologin after signup and verification) are not yet proven to rotate. | [2026-09-19 finding 2](audits/security-audit-2026-09-19.md); renew the ID on MFA completion and carry the active-session row and sidecar across it. Change 2026-09-28 (#4466): `after_two_factor_authentication` (`apps/web/auth/config/hooks/two_factor.rb`) calls `Onetime::SessionRotation` (`lib/onetime/session/rotation.rb`), which ends the pending ID through the store (`SessionEnded` marker, blob, sidecar keys, metadata record) and writes the session data back under a fresh ID in the same request; the active-session row survives because it is keyed by `active_session_id_hmac`, which is carried, and the snapshot epoch restarts per ADR-046. The rotation writes the `SessionEnded` marker before touching anything, and a rotation that cannot end the old ID clears the session and refuses the login, so no half-authenticated blob is left readable (review of PR #4600). Covered by `apps/web/auth/spec/integration/full_mfa/mfa_session_rotation_spec.rb`. The row stays open for the remaining establishment paths, each a follow-up to #4466 that can call the same operation. Owner: Unassigned. |

## Open investigations

| ID | Priority / risk | Status | Risk | Source and required action |
|---|---|---|---|---|
| RISK-2026-10-03-4C3C | Unassigned / Unconfirmed | Open | If a browser replays cached Basic API credentials cross-site without an authenticated session, the API CSRF-token exemption could permit unintended account-attributed actions. Browser caching and replay have not been demonstrated or refuted. | [2026-10-03 audit, report 4c3c](audits/security-audit-2026-10-03.md); test real-browser credential caching, automatic cross-site replay, accepted request encoding, and server-side account attribution before rating or closing. A regression spec guarding the unprompted-Basic-challenge invariant was added at `50b203c49a` (audit "Required validation" step 3); it does not close the item — Firefox and WebKit remain untested. Owner: Unassigned. Target: Not scheduled. |

## Historical sources

- [2026-08-14 historical risk register](risk-registers/risk-register-2026-08-14.md)
- [2026-08-13 security audit](audits/security-audit-2026-08-13.md)
- [2026-09-09 follow-up audit](audits/security-audit-2026-09-09.md)
- [2026-09-19 session-consistency package review](audits/security-audit-2026-09-19.md)
- [2026-10-03 Basic-auth API CSRF exemption assessment](audits/security-audit-2026-10-03.md)
