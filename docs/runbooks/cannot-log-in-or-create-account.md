# How to triage "can't login / can't create account"

## Start here

```bash
bin/ots customers diagnose <email|extid|account-id>   # --json, --full, --audit-limit N
```

Or Colonel → customer detail → **Account Diagnostics** panel
(`GET /api/colonel/users/:user_id/diagnostics`). No SSH needed.

One call covers account state, lockout/login failures, verification and reset
keys, MFA, active sessions, the Rodauth auth audit log, and the login rate
limiter. Findings name the blocking condition (`locked_out`, `rate_limited`,
`unverified`, `verification_stale`, `email_drift`, `no_password`, `sso_only`,
`orphaned_auth_account`, `suspended`, `not_found`). An email with no customer
is still probed against the authdb — orphans and "not in this region" come
back as findings, not 404s. Exit code 1 = nothing found; loop it across
regions.

## Failure buckets

1. **Account state** — unverified, closed, locked out, Customer↔auth drift. → diagnose
2. **Rate limiting** — Valkey limiters block before Rodauth sees the attempt. → diagnose
3. **Email delivery** — verification/reset email never sent, bounced, suppressed.
4. **Surface config** — custom domain with signin/signup default-OFF (v0.26.2 regression) or `restrict_to: 'sso'`; wrong region.
5. **Client-side** — CSP blocking form-action (#3848/#3836), cookie dropped behind TLS proxy (#3837), JS errors.
6. **Policy rejection** — password requirements, MFA/webauthn failures.

## When diagnose is clean

| Question                             | Tool                                                                                      |
| :----------------------------------- | :---------------------------------------------------------------------------------------- |
| Which surface/region? Custom domain? | Ask the user. Custom domain → check SigninConfig first                                    |
| Did the verification email go out?   | Colonel email provider status/rates; `ots email test/validate`. No per-recipient send log |
| Client-side failure?                 | Sentry, filtered to /auth routes by time (email is scrubbed)                              |
| Index integrity?                     | `ots customers doctor <email>`                                                            |
