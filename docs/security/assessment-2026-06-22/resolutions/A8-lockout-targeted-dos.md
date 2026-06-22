# A8 — Per-account lockout enables targeted victim DoS (~1-day window)

- **Severity:** Medium
- **Status:** Proposed fix
- **Affects default config?** No — gated on auth being enabled (Rodauth full-auth mode). Lockout is on
  in full mode (`AUTH_LOCKOUT_ENABLED`, default enabled, `lockout.rb:7`).
- **Related:** Finding 01 §9. Login timing oracle §15, rate-limiting posture generally. Interacts with
  passwordless paths (magic-link/SSO) and reset, which are **not** lockout-gated.
- **Primary files:**
  - `apps/web/auth/config/features/lockout.rb:15-16` (OTS lockout config — the fix point)
  - fork `rodauth/lib/rodauth/features/lockout.rb:33,42,178-217,263-268` (lockout mechanism)

## Problem (recap)

`max_invalid_logins 5` (`lockout.rb:15`) with the `lockout_expiration_default` override **commented out**
(`lockout.rb:16`) means 5 bad passwords lock an account for the Rodauth default window. Knowing a
victim's email, an attacker submits 5 wrong passwords and locks that account for ~1 day — a cheap,
targeted denial of service against a specific user. Self-service unlock exists (unlock-account email) but
forces a victim email round-trip.

Lockout is keyed on `account_id` and enforced in `before_login_attempt` (fork `lockout.rb:263-268`):

```ruby
def before_login_attempt
  if locked_out?            # true while now < account_lockouts.deadline
    show_lockout_page       # 4xx, blocks the password login attempt
  end
  super
end
```

## Root cause — two issues, one of them a latent config bug

1. **The lockout window is far too long for a per-account control.** The intended duration knob is
   `account_lockouts_deadline_interval`, whose fork default is **1 day** (`lockout.rb:42`:
   `auth_value_method :account_lockouts_deadline_interval, {:days=>1}.freeze`). A multi-hour hard lock
   keyed on a value an attacker fully controls (the victim's email/account) trades brute-force
   resistance for a trivially weaponizable DoS.

2. **The commented-out override would not have worked anyway — wrong method name.**
   `lockout.rb:16` references `auth.lockout_expiration_default 3600`, but **no such method exists** in
   this Rodauth fork (verified by grep over `/home/user/rodauth`; the only duration method is
   `account_lockouts_deadline_interval`). So even if that line were uncommented, it would be a no-op (or
   raise), and the 1-day default would still apply. Any shortening must target
   `account_lockouts_deadline_interval`.

> **Confirm first:** Verify there is no app-level shim aliasing `lockout_expiration_default` to the
> deadline interval before relying on the above. Grep found none in the fork; confirm none exists in
> `apps/web/auth` overrides. The prescription uses the real `account_lockouts_deadline_interval`.

## Prescribed resolution

Shift from a long hard per-account lock toward **layered, attacker-cost-asymmetric** controls: a short
account lock + IP/global rate limiting + the existing email-unlock escape, so a single account is not
trivially DoS-able by a remote actor while brute-force resistance is preserved.

### Implementation steps

1. **Shorten the lockout window with backoff.** Replace the long default with a short base window. Rodauth
   accepts a callable for `account_lockouts_deadline_interval`, which enables exponential backoff keyed on
   the failure count (so repeated, sustained attacks still escalate, but a one-off 5-fail burst clears
   quickly):

   ```ruby
   # apps/web/auth/config/features/lockout.rb
   auth.max_invalid_logins 5

   # Short base window with exponential backoff. The block can read the current
   # failure count to scale the window: e.g. 15 min, then 30, 60, ... capped.
   auth.account_lockouts_deadline_interval do
     fails  = account_login_failures_ds.get(account_login_failures_number_column).to_i
     extra  = [fails - max_invalid_logins, 0].max          # 0 at first lockout
     minutes = [15 * (2 ** extra), 240].min                # 15m -> 30 -> 60 -> ... cap 4h
     { seconds: minutes * 60 }
   end
   ```

   This caps a casual targeted DoS at ~15 minutes for the common case while preserving escalation against
   a persistent brute-force attacker. (If a callable form is not supported in this fork's version for
   this method, set a short fixed interval, e.g. `{ minutes: 15 }`, and rely on IP throttling below for
   sustained-attack coverage — **confirm the method's accepted argument types first**.)

2. **Add IP/network rate limiting in front of the login route.** A per-account lock can always be abused
   for DoS; the real brute-force defense should be **IP/global throttling**, which targets the attacker's
   vantage rather than the victim's account. Apply request-rate limits on the login + reset + unlock
   routes (OTS already has rate-limiting infrastructure — reuse it, or add a Rack throttle keyed on
   resolved client IP via the otto trusted-proxy resolution referenced in `A3-P2-host-header-trust.md`).
   With IP throttling carrying the brute-force load, the per-account lock can be safely short.

3. **Add CAPTCHA / proof-of-work step-up after N failures (optional).** Before/at the lock threshold,
   require a CAPTCHA on subsequent login attempts for that login. This raises attacker cost without
   locking the legitimate user out, further reducing reliance on the hard lock.

4. **Keep email-unlock as the escape, and ensure it's non-enumerating + rate-limited.** The
   unlock-account-request flow (`lockout.rb:70-97`) already gates resend (`unlock_account_skip_resend_email_within`,
   300s). Confirm it does not leak account existence on the no-match branch (it currently sets
   `:no_matching_login`, `lockout.rb:91-93` — align with the uniform-response approach in
   `A7-reset-enumeration-password-dos.md`).

5. **Preserve the safe properties already present.** Passwordless paths (magic-link/SSO) and reset are
   **not** gated by lockout — keep it that way so a locked-out legitimate user retains recovery routes;
   this also means lockout must not be the *only* brute-force control (hence steps 2–3).

### Balancing brute-force vs DoS (rationale)

- A 64-MiB argon2 hash (production cost) makes online password brute force inherently slow; the lock's
  job is to stop sustained guessing, not to be the sole barrier. A **15-minute** base window after 5
  fails caps online guessing to a low rate while making targeted DoS self-healing within minutes.
- Exponential backoff means a *persistent* attacker against one account still hits escalating delays
  (up to the 4-hour cap), so sustained brute force is not rewarded — but a drive-by 5-fail lock no
  longer costs the victim a full day.
- IP throttling (step 2) is what actually scales against distributed/credential-stuffing attacks, since
  it does not depend on the target account at all.

### Alternatives considered

- **Keep the 1-day hard lock:** rejected — it is the DoS primitive; an attacker who knows an email can
  deny that user access for a day with 5 requests.
- **Permanent lock until manual/admin unlock:** rejected — worst DoS profile and a support burden.
- **No lockout, rely solely on IP throttling:** rejected — removes a useful per-credential signal and
  weakens defense against low-and-slow guessing from rotating IPs; keep a *short* account lock plus IP
  throttling (defense-in-depth).
- **Uncomment `lockout_expiration_default 3600`:** rejected — that method does not exist in this fork
  (root cause #2); it would be a no-op. Use `account_lockouts_deadline_interval`.

## Test / verification

Add to `apps/web/auth/spec/`:

1. **Short window:** trigger 5 failed logins → account locked; advance clock past the new base window
   (e.g. 15 min) → `locked_out?` is false and login succeeds (fork auto-unlocks on expiry,
   `lockout.rb:149-160`). Assert the lock did **not** last ~1 day.
2. **Backoff escalation:** repeated lock cycles produce increasing deadlines up to the cap (assert the
   computed interval grows then plateaus).
3. **Config-bug regression guard:** assert the effective deadline derives from
   `account_lockouts_deadline_interval` (not a no-op `lockout_expiration_default`); a unit test asserting
   the configured/overridden value catches future reintroduction of the dead method name.
4. **IP throttling:** N rapid login attempts from one IP across *different* accounts are throttled
   (brute-force/credential-stuffing coverage independent of any single account lock).
5. **Recovery paths unaffected:** a locked-out account can still use magic-link/SSO/reset (these are not
   lockout-gated); unlock-account email still works and its request response is non-enumerating
   (cross-ref A7).

## Effort & risk

- **Effort:** Small for the window/backoff change (config in `lockout.rb`); Medium if IP throttling /
  CAPTCHA step-up are newly added (reuse existing rate-limit infra where possible).
- **Risk:** Low. Shortening the window strictly reduces DoS exposure; the main consideration is ensuring
  IP throttling (step 2) is in place so the shorter account lock does not weaken brute-force resistance.
  Validate the `account_lockouts_deadline_interval` callable form against the fork version before relying
  on backoff; fall back to a short fixed interval otherwise.
