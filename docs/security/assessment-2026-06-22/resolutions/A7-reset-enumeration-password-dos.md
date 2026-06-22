# A7 — Password-reset account enumeration + no maximum password length (argon2 DoS)

- **Severity:** Medium (two related hardening gaps on the reset/password-set surface)
- **Status:** Proposed fix
- **Affects default config?** No — gated on auth being enabled (Rodauth full-auth mode). The
  reset-password and create/change-password routes only exist in full-auth mode.
- **Related:** Finding 01 §7 (enumeration) + §8 (no max password length). DoS amplified by synchronous
  email delivery (`config/email/delivery.rb` `fallback: :sync`).
- **Primary files:**
  - `apps/web/auth/config/features/account_management.rb:104` (sets `password_minimum_length`; add max here)
  - `apps/web/auth/config/features/argon2.rb` (hash cost — context for the DoS)
  - fork `rodauth/lib/rodauth/features/reset_password.rb:65-100,178-180` (distinct responses — root cause)
  - fork `rodauth/lib/rodauth/features/email_auth.rb:56-69` (the **uniform** pattern to mirror)
  - fork `rodauth/lib/rodauth/features/login_password_requirements_base.rb:15-16,170-183` (max-length support)

## Problem (recap)

**A7a — Reset-password enumeration.** The `reset_password_request` route returns three
distinguishable responses depending on account state:

```ruby
# fork reset_password.rb:73-99
unless account_from_login(login_param_value)
  throw_error_reason(:no_matching_login, no_matching_login_error_status, ...)  # 401 "no matching login"
end
reset_password_request_for_unverified_account unless open_account?            # -> 403 (below)
...
reset_password_email_sent_response                                            # 200 "email sent"

# reset_password.rb:178-180
def reset_password_request_for_unverified_account
  throw_error_reason(:unverified_account, unopen_account_error_status, ...)    # 403 "unverified"
end
```

Status codes (fork `base.rb`): `no_matching_login_error_status = 401` (`:59`),
`unopen_account_error_status = 403` (`:80`). With `only_json? true` (`base.rb:46`), the attacker reads
status + reason and distinguishes **nonexistent (401)** vs **unverified (403)** vs **valid (200)**.
OTS overrides the *email-auth* request flash but does **not** override the reset flow to be uniform.

**A7b — No maximum password length → argon2 CPU/memory DoS.** `account_management.rb:104` sets
`password_minimum_length 8` but there is **no** `password_maximum_length`/`password_maximum_bytes`
(fork default `nil`, `login_password_requirements_base.rb:15-16`). The raw password is fed to argon2id
(`argon2.rb`, production `t_cost=2, m_cost=16` = 64 MiB) on every signup/reset/change. Argon2 has no
inherent input truncation (unlike bcrypt's 72 bytes), so multi-megabyte passwords multiply CPU/memory
per hash — a cheap DoS, amplified by synchronous email send on the same request.

## Root cause

- **A7a:** OTS relies on Rodauth's *default* reset-request behavior, which is enumeration-revealing by
  design (it tells the user "no such login" / "unverified"). The matching email-auth (magic-link) flow
  was already hardened to always look like "email sent" (fork `email_auth.rb:60-68`: it attempts the
  request only for an open account but **always** redirects to the email-sent response with a generic
  flash). Reset was never given the same treatment.
- **A7b:** No upper bound on password size is configured, so untrusted input length directly drives
  argon2 work.

## Prescribed resolution

### A7a — Make the reset-request response uniform (mirror the email-auth flow)

The fix is to make `reset_password_request` always return the same generic "if an account exists, an
email has been sent" 200 response, regardless of whether the login exists or is verified — exactly the
shape email-auth already uses. The email is still sent only for a valid, open account; the *response* no
longer discloses which case occurred.

#### Implementation steps

1. **Suppress the distinguishing errors and force a uniform success response.** Override the two
   error-raising seams so they no longer differ from the success path, and override the request-error
   flash to the generic message. In `apps/web/auth/config/features/account_management.rb` (or a small
   dedicated `reset_password` config module mirroring `features/email_auth.rb`):

   ```ruby
   # Generic, non-enumerating copy for ALL reset-request outcomes.
   auth.reset_password_request_error_flash \
     'If an account with that email exists, a password reset link has been sent.'
   auth.reset_password_email_sent_notice_flash \
     'If an account with that email exists, a password reset link has been sent.'

   # Do NOT reveal "no matching login": treat a missing account as a no-op that
   # still returns the email-sent response (mirrors fork email_auth.rb:60-68).
   auth.no_matching_login_message 'If an account with that email exists, a password reset link has been sent.'

   # Do NOT 403 on unverified accounts during reset-request: swallow the
   # unverified branch so it produces the same uniform response.
   auth.reset_password_request_for_unverified_account do
     # no-op: fall through to the standard email-sent response without an email
     # (or send the verify-account email instead — see step 3). Crucially, do not
     # throw :unverified_account / 403 here.
     nil
   end
   ```

   The cleanest structural option (preferred): override the `reset_password_request` route body to follow
   the email-auth shape — attempt key generation + send **only** when `account_from_login && open_account?`,
   and **always** end with `reset_password_email_sent_response` and a 200. This removes both the 401 and
   403 branches in one place rather than patching each message/status. If overriding the route is too
   invasive, the value-method overrides above achieve the same externally observable result (uniform 200,
   generic message, no distinguishing reason/status).

2. **Normalize status codes too, not just flashes.** Because `only_json? true`, the attacker reads the
   HTTP status. Ensure the no-match and unverified paths no longer emit 401/403 — overriding
   `reset_password_request_for_unverified_account` to a no-op and routing the no-match case through the
   email-sent response yields a uniform 200. Verify the JSON body's `reason`/`field-error` are also
   generic (no `:no_matching_login`/`:unverified_account` leak).

3. **Decide the unverified-account behavior deliberately.** Two acceptable options, both
   non-enumerating: (a) silently no-op (send nothing) — simplest; or (b) send the *verify-account* email
   instead of a reset email, so a real-but-unverified user gets a useful next step. Either way the
   *response* is identical to the account-exists case. Document the choice.

4. **Keep timing uniform-ish.** Reset already does a DB lookup for all cases; the dominant time
   difference is the email send. Since email is `fallback: :sync`, only sending in the valid case adds
   latency. Prefer enqueuing email asynchronously (or adding a constant small delay) so response timing
   does not re-introduce the oracle the status/flash change just closed. (Cross-ref the login timing
   oracle, finding 01 §15 — same class of issue.)

### A7b — Cap password length before hashing

The fork already supports the cap; it is simply unset.

#### Implementation steps

1. **Set `password_maximum_bytes` in `apps/web/auth/config/features/account_management.rb`** next to
   the existing minimum:

   ```ruby
   auth.password_minimum_length 8
   auth.password_maximum_bytes 1024   # reject inputs >1 KiB before argon2 runs
   ```

   `password_maximum_bytes` is validated in `password_meets_length_requirements?`
   (`login_password_requirements_base.rb:177`: `password_maximum_bytes < password.bytesize`) which runs
   **before** `set_password`/argon2, so oversized inputs are rejected with a 422-class field error rather
   than hashed. Prefer `password_maximum_bytes` over `password_maximum_length` so multibyte/unicode
   passwords are bounded by actual byte size (the argon2 cost driver), not character count.

2. **Pick the cap deliberately.** 1024 bytes comfortably exceeds any legitimate passphrase while
   bounding argon2 work. The finding suggested 256–4096; 1024 is a reasonable middle. NIST allows long
   passwords, so do not set it too low (≥64 chars recommended minimum upper bound); 1024 bytes preserves
   long passphrases while stopping megabyte payloads.

3. **Verify the cap applies on every password-setting path** — create-account, reset-password, and
   change-password all funnel through `password_meets_requirements?`, so a single config covers all
   three. (Reset: fork `reset_password.rb:133`; create/change use the same base check.)

4. **Defense-in-depth:** keep email delivery async (above) and confirm a request-body size limit at the
   edge/middleware so multi-megabyte POST bodies are rejected before reaching the handler at all.

### Alternatives considered

- **A7a — only change the flash text, keep 401/403 statuses:** rejected — with `only_json?` the status
  code itself is the oracle; the statuses must also collapse to a uniform 200.
- **A7a — return 200 but still send distinct internal reasons in the JSON body:** rejected — the body
  is attacker-readable; reasons must be generic.
- **A7b — truncate the password to N bytes instead of rejecting:** rejected — silent truncation creates
  surprising behavior and a weak-password footgun; an explicit length error is clearer and safer.
- **A7b — rely on argon2 cost tuning alone:** rejected — cost tuning bounds per-hash work at a fixed
  input size but does nothing about unbounded input length; the byte cap is the actual control.

## Test / verification

Add to `apps/web/auth/spec/`:

1. **A7a uniformity:** POST reset-request for (a) a nonexistent email, (b) an existing **unverified**
   account, (c) an existing **verified** account → all three return the **same** HTTP status (200) and
   the **same** generic flash/JSON body; assert no `:no_matching_login`/`:unverified_account` reason
   leaks. Confirm an email is sent only in case (c) (and/or a verify email in (b) per the chosen policy).
2. **A7a timing:** assert response timing for (a)/(b)/(c) is not separable (email is async / constant
   delay), so the status fix is not undone by a timing oracle.
3. **A7b length cap:** POST a password of `password_maximum_bytes + 1` bytes to create-account,
   reset-password, and change-password → each rejected with the too-many-bytes field error **before**
   argon2 runs (assert argon2 is not invoked, e.g. via a hashing spy / no measurable hash latency).
4. **A7b happy path:** a long-but-reasonable passphrase (e.g. 200 bytes) still succeeds.
5. **Regression:** existing valid reset and password-change flows still succeed end to end.

## Effort & risk

- **Effort:** Small. A7b is a one-line config (`password_maximum_bytes`). A7a is a handful of value-method
  overrides (or one route override) mirroring the existing email-auth pattern + making email async.
- **Risk:** Low. A7a is externally a UX copy change (users now always see "if an account exists…");
  ensure support docs reflect that reset no longer says "no such account." A7b could reject pathological
  legitimate inputs only above the chosen cap — 1024 bytes avoids any realistic false positive.
