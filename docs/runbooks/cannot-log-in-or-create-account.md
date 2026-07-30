# docs/runbooks/cannot-log-in-or-create-account.md

---

# How to triage "can't login / can't create account"?

For this stack (Rodauth full mode), the real causes cluster into six buckets:

1. Account state — exists but unverified (never clicked the link), closed, locked out (Rodauth lockout is enabled), or Customer↔auth-account drift (sync_auth_accounts exists precisely because this happens).
2. Rate limiting — Valkey-side login_rate_limiter, reset_request_rate_limiter, etc. (lib/onetime/security/) blocking before Rodauth ever sees the attempt.
3. Email delivery — verification/reset email never sent, bounced, or suppressed at the provider.
4. Surface config — they're on a custom domain with signin/signup default-OFF (the v0.26.2 regression was exactly this) or restrict_to: 'sso'; or wrong region entirely.
5. Client-side — CSP blocking form-action (#3848/#3836 were real), cookie dropped behind TLS proxy (#3837), JS errors.
6. Policy rejection — password requirements, MFA/webauthn challenge failures.

Triage playbook with today's tools

| Step | Question                                                 | Tool that exists now                                                                                                                                                            |
| :--- | :------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1    | Which surface? Canonical or custom domain, which region? | Ask the user / feedback metadata. Custom domain → check SigninConfig first; it's the highest-prior cause                                                                        |
| 2    | Account state, not just existence                        | `ots customers show <email>` (verified flag, rodauth_account_id), `ots customers doctor <email>` (index integrity). Lockout/verification-key state: raw SQL against authdb only |
| 3    | What did their auth attempts actually do?                | account_authentication_audit_logs — Rodauth audit_logging is enabled and has been writing per-account auth events all along. Nothing reads it — no Colonel page, no CLI         |
| 4    | Rate limited?                                            | `ots ratelimit list` / `ots ratelimit inspect --kind login ...` (emits valkey-cli commands)                                                                                     |
| 5    | Did the verification email go out?                       | Colonel email provider status/rates, `ots email test/validate`. Per-recipient send log doesn't exist                                                                            |
| 6    | Client-side failure?                                     | Sentry (diagnostics sentry CLI, MCP) — filter to /auth routes; but scrubbing removes the email, so you search by route+time, not user                                           |
| 7    | Sessions                                                 | Colonel per-customer sessions sidecar                                                                                                                                           |
