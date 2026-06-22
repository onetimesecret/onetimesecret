# Resolutions — index

One prescribed-fix document per finding from the 2026-06-22 assessment. Each doc states severity,
default-config applicability, root cause, a principled long-term fix (with code-level guidance,
alternatives, tests, and effort/risk), and back-compat/migration notes. See `../risk-register.md` for
the ranked finding list and `../findings/00-EXECUTIVE-REPORT.md` for the synthesis.

> These are **prescriptions**, not applied changes. Implement behind the existing feature flags, with
> the tests each doc specifies. The maintainer's guidance: take the revisions/stacked PRs needed to get
> it right.

## The Critical and its tie to issue #3499

The Critical (**A1**, SSO email-match account takeover) is **not** a standalone patch — it belongs in the
already-open work of **#3499 "Support SSO accounts when IdP omits the email claim."** #3499 already
defines the right surface: a single `resolve_omniauth_email` helper and an explicit **IdP claim
trust-tier** model, and it explicitly names the takeover vector ("writing an unverified … claim into
[`accounts.email`] could link an SSO identity to the wrong account"). A1 extends that rule from *which
claim populates the column* to *the linking decision itself*: require a verified Tier-1 email and never
silently merge an SSO identity into a pre-existing password account. SSO is not yet in production, so this
can be designed into the feature rather than retrofitted. See `A1-sso-account-linking.md`.

**Recommended stacked-PR sequence for the SSO cluster:**
1. **PR-1 = #3499 Phase 1** — `resolve_omniauth_email`, Tier-1/verified-only email.
2. **PR-2 = A1 + A4 + A2** on top — secure linking (no silent merge), domain allowlist on the linking
   path, and no MFA bypass for SSO.

## Suggested overall ordering

1. **Now / default-config:** `C1` (atomic one-time consume) · `S1` + `S2` (secure-header defaults) ·
   `D1` (oauth2 bump).
2. **Before SSO ships:** `A1` · `A2` · `A4` · `A3-P2` (host-header trust) · `P1` (cookie-auth CSRF).
3. **Hardening:** `C2` · `C3` · `P3` · `AZ1` · `AZ2` · `A5` · `A6` · `A7` · `A8` · `D3` · `D4` · `D5`.
4. **Cleanup / pre-emptive:** `C4` · `C5` · `C6` · `AZ3` · `AZ4` · `AZ5` · `AZ6` · `AZ7` · `AZ8` ·
   `AZ9` · `P4` · `P5` · `S3` · `S4` · `S5` · `D2` · `OBS1`.

## All resolutions

### Critical
- [A1 — SSO email-match account takeover (secure account linking)](A1-sso-account-linking.md)

### High
- [C1 — One-time reveal/burn is not concurrency-safe (atomic consume)](C1-one-time-reveal-atomicity.md) · *default config; PoC-confirmed*
- [A2 — SSO bypasses MFA unconditionally](A2-sso-mfa-bypass.md)
- [A3 / P2 — Host-header trust (poisoned auth-email links & host injection)](A3-P2-host-header-trust.md)
- [A4 — SSO domain allowlist not enforced on linking](A4-sso-domain-allowlist.md)
- [P1 — CSRF bypassed for cookie-authenticated API mutations](P1-csrf-cookie-auth-api.md)
- [S1 — CSP disabled by default](S1-csp-default-on.md) · *default config*
- [S2 — Clickjacking / HSTS / security headers off by default](S2-security-headers-default-on.md) · *default config*
- [D1 — `oauth2` 2.0.18 bearer-token leak CVE](D1-oauth2-cve.md)

### Medium
- [C2 — Encryption HKDF salt/personalization left at shared library default](C2-encryption-domain-separation.md)
- [C3 — V1 reveal path has no passphrase rate limiting](C3-v1-passphrase-rate-limit.md)
- [C4 — Passphrase rate-limit check/record non-atomic + test Argon2 cost guard](C4-rate-limit-atomicity-argon2-guard.md)
- [P3 — Rate-limiting gaps (login, secret creation)](P3-rate-limiting-gaps.md)
- [AZ1 — RemoveMember authorization inconsistency](AZ1-remove-member-entitlement-gate.md)
- [AZ2 — Organization safe_dump leaks internal/cross-tenant data](AZ2-organization-safe-dump-minimization.md)
- [AZ3 — Organization.create! open splat (mass assignment)](AZ3-organization-create-allowlist.md) · *needs-validation*
- [AZ4 — change_role! accepts `owner`](AZ4-change-role-reject-owner.md) · *needs-validation*
- [AZ5 — Organization external id uses plain SHA-256 (no keyed HMAC)](AZ5-organization-extid-keyed-hmac.md) · *needs-validation*
- [A5 — Recovery codes stored plaintext](A5-recovery-codes-plaintext.md)
- [A6 — WebAuthn RP-ID/origin derived from request.host](A6-webauthn-rpid.md)
- [A7 — Reset enumeration + no max password length (Argon2 DoS)](A7-reset-enumeration-password-dos.md)
- [A8 — 1-day per-account lockout (targeted DoS)](A8-lockout-targeted-dos.md)
- [D2 — `form-data` 4.0.5 via axios (browser, mitigated)](D2-form-data-axios-cve.md)
- [D3 — Production source maps shipped/served](D3-production-source-maps.md)
- [D4 — Caddy proxy image runs as root / unpinned](D4-caddy-image-hardening.md)
- [D5 — Unauthenticated Redis + host-exposed; RabbitMQ guest:guest](D5-datastore-default-credentials.md)
- [S3 — Revealed secret not cleared from SPA memory](S3-clear-revealed-secret-from-memory.md)

### Low / Info
- [C5 — No secret payload size cap (Redis DoS)](C5-secret-payload-size-cap.md)
- [C6 — Legacy v1 unsalted SHA-256 encryption key (retire)](C6-legacy-v1-encryption-key-retirement.md)
- [AZ6 — Receipt safe_dump exposes creator owner_id](AZ6-receipt-safe-dump-owner-id.md)
- [AZ7 — show_invite discloses inviter email + account oracle](AZ7-show-invite-minimize-disclosure.md)
- [AZ8 — Customer.create! has no allowlist](AZ8-customer-create-allowlist.md) · *needs-validation*
- [AZ9 — No rate limit on anonymous incoming /secret (emails)](AZ9-incoming-submit-rate-limit.md) · *needs-validation*
- [P4 — V1 Basic-Auth username enumeration via timing](P4-v1-basicauth-timing-enumeration.md)
- [P5 — Log injection of Basic-Auth username](P5-v1-log-injection-username.md)
- [S4 — v-html in GlobalBroadcast (hardening)](S4-global-broadcast-vhtml-hardening.md)
- [S5 — DNS widget script injected without CSP nonce](S5-dns-widget-script-nonce.md)
- [OBS1 — SessionDebugger dumps Set-Cookie when enabled](OBS1-session-debugger-header-dump.md)

_38 resolution documents covering every finding in the risk register._
