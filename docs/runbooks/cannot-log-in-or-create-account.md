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
`orphaned_auth_account`, `suspended`, `authdb_unavailable`,
`evidence_incomplete`, `not_found`). An
identifier with no customer is still probed against the authdb — by email,
extid, or numeric account id — so orphans and "not in this region" come back as
findings, not 404s. Exit code 1 = nothing found; loop it across regions.

`authdb_unavailable` outranks everything else: the auth database did not answer,
so no account state could be read and existence is unknown. Stop triaging the
account and go look at the database — while it is unreachable every password
login fails. It is NOT the same as simple auth mode (no authdb by design), which
reports no finding at all.

`evidence_incomplete` means the diagnosis is PARTIAL: at least one source — the
customer record, a Rodauth sidecar table, or the login rate limiter — did not
answer, so every condition not flagged is unproven rather than ruled out. The
finding lists each unreadable section with the error it returned; that reason is
what tells you which datastore to look at. Sections degrade one at a time, so
this fires while everything else still reads clean (a dropped or ungranted
table, a statement timeout, a Valkey WRONGTYPE on one limiter key). States where
nothing is actually wrong do NOT raise it: simple auth mode, no accounts row to
read, a whole-authdb failure (that is `authdb_unavailable`), and an identifier
with no address to rate-limit (an orphan looked up by extid or account id).

## Failure buckets

1. **Account state** — unverified, closed, locked out, Customer↔auth drift. → diagnose
2. **Rate limiting** — Valkey limiters block before Rodauth sees the attempt. → diagnose
3. **Email delivery** — verification/reset email never sent, bounced, suppressed.
4. **Surface config** — custom domain with signin/signup default-OFF (v0.26.2 regression) or `restrict_to: 'sso'`; wrong region.
5. **Client-side** — CSP blocking form-action (#3848/#3836), cookie dropped behind TLS proxy (#3837), JS errors.
6. **Policy rejection** — password requirements, MFA/webauthn failures.

## When diagnose is clean

Clean means an EMPTY findings list. A result carrying `evidence_incomplete` is
NOT clean: the reads it names never happened, so a server-side cause has not
been ruled out. Clear those sources and re-run before working this table —
otherwise you are here on the strength of evidence that was never collected.

| Question                             | Tool                                                                                      |
| :----------------------------------- | :---------------------------------------------------------------------------------------- |
| Which surface/region? Custom domain? | Ask the user. Custom domain → check SigninConfig first                                    |
| Did the verification email go out?   | Colonel email provider status/rates; `ots email test/validate`. No per-recipient send log |
| Client-side failure?                 | Sentry, filtered to /auth routes by time (email is scrubbed)                              |
| Index integrity?                     | `ots customers doctor <email>`                                                            |
