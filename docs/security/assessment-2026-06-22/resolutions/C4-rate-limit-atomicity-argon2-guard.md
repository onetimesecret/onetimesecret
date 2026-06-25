# C4 — Passphrase rate-limit check/record gap + test-cost Argon2 selectable by RACK_ENV

- **Severity:** Low/Medium — **CONFIRMED** in source (bounded over-shoot; config-dependent weak hash)
- **Status:** Proposed fix — **corrected 2026-06-24 (snippet defect fixed in place; see callout)**
- **Affects default config?** Partially — the non-atomic gate affects the default reveal flow under
  concurrency; the Argon2 test-cost only bites a misconfigured `RACK_ENV=test` in production
- **Related:** finding 03 F4; C3 (shared limiter); C1 (the broader non-atomic-consume theme)
- **Primary files:** `lib/onetime/security/passphrase_rate_limiter.rb`,
  `lib/onetime/models/features/passphrase_hashing.rb`,
  `apps/api/v2/logic/secrets/reveal_secret.rb`, `lib/onetime/boot.rb`

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §5 (compile-level defects)).**
> The C4b boot guard below is **incomplete (compile-level defect)**: it keys the test-harness
> signal off `defined?(RSpec)`. This project runs **two** test runners — RSpec **and** Tryouts v3
> (`try/`) — and Tryouts does not load RSpec. Under the Tryouts suite `defined?(RSpec)` is `nil`,
> so `running_under_test_harness?` returns false while `RACK_ENV=test`, and the guard **raises
> `Onetime::Problem` at boot → the entire Tryouts suite dies before any test runs.**
>
> **Correction:** do not gate on `defined?(RSpec)` at boot. Detect test/low-cost mode via a signal
> both runners can set — prefer an explicit env var the harness exports (e.g. `OT_TEST=1`), or a
> runtime check that is true under RSpec *and* Tryouts. The guard's intent (only the real suite gets
> the cheap Argon2 cost) is unchanged; only the harness-detection predicate must be runner-agnostic.
> The snippet at `boot.rb:158-161` is corrected in place below.

## Problem (recap)

Two distinct sub-issues in otherwise-solid passphrase defenses.

### C4a — Non-atomic check-then-record (bounded over-shoot)

The rate-limiter's **increment+expire+lockout** is correctly atomic Lua
(`passphrase_rate_limiter.rb:37-56`, invoked at `:106-110`). The problem is the *surrounding*
sequence: the **gate read** and the **failure record** are two separate round-trips with secret
loading and Argon2 verification between them.

```ruby
# check (read-only): pipelined GET/EXISTS/TTL — does NOT decrement or reserve
def check_passphrase_rate_limit!(secret_identifier)   # :64-92
  is_locked, ttl, current_attempts = redis.pipelined { ... }   # read only
  raise Onetime::LimitExceeded ... if [true, 1].include?(is_locked)
end

# record (atomic, but only AFTER a failed verify): INCR + maybe lockout
def record_failed_passphrase_attempt!(secret_identifier) # :99-117
  redis.eval(RECORD_ATTEMPT_SCRIPT, ...)
end
```

In `RevealSecret`, `check_passphrase_rate_limit!` runs in `raise_concerns` (`reveal_secret.rb:68`)
and `record_failed_passphrase_attempt!` runs much later in `process` (`:194`). A burst of N
concurrent guesses can **all read the gate as "not locked" before any of them records a failure**,
so up to N (not 5) live guesses run in one window. This is a **bounded** over-shoot (the next window
is locked), not an unlimited bypass — but it widens the brute-force throughput exactly when an
attacker parallelises.

### C4b — Argon2 test cost selectable purely by `RACK_ENV`

```ruby
# lib/onetime/models/features/passphrase_hashing.rb:68-74
def argon2_hash_cost
  if ENV['RACK_ENV'] == 'test'
    { t_cost: 1, m_cost: 5, p_cost: 1 }   # 2^5 = 32 KiB, 1 pass  — fast & weak (tests only)
  else
    { t_cost: 2, m_cost: 16, p_cost: 1 }  # 2^16 = 64 MiB, 2 passes — production
  end
end
```

The production parameters are reasonable (`m_cost: 16` ⇒ 64 MiB; `t_cost: 2` is on the low side).
The real hazard is that the **test** parameters — deliberately trivial so the suite runs fast — are
chosen by nothing more than `ENV['RACK_ENV'] == 'test'`. If a production process is ever started with
`RACK_ENV=test`, every new passphrase is hashed at 32 KiB / 1 pass, which is brute-forceable offline.
Boot already defaults env to production (`boot.rb:111`: `OT.env = ENV['RACK_ENV'] || 'production'`)
but does **not** refuse to *run* as `test` outside the test suite.

## Root cause

- **C4a:** the authoritative "have we exceeded the limit" decision is split across a read and a
  later write, with no token reserved at gate time — the same check-then-act shape as C1, applied to
  rate limiting.
- **C4b:** a security-critical cost parameter is keyed off an ambient environment variable with no
  guard that the variable is consistent with the actual deployment.

## Prescribed resolution

### C4a — reserve a token atomically *before* verifying

Replace "read gate, verify, maybe record" with "**atomically count this attempt and decide**, then
verify". Move the single atomic Lua to the front and have it return both the new count and the locked
state, so the decision and the increment are one round-trip and concurrent guesses serialize on the
`INCR`.

#### Implementation steps

1. **Extend the Lua to be the gate.** Generalise `RECORD_ATTEMPT_SCRIPT` so a single eval (a)
   refuses immediately if already locked, and (b) otherwise reserves this attempt and reports the
   count. Conceptually:

   ```lua
   -- KEYS[1]=attempts, KEYS[2]=lockout ; ARGV: window, max, lockout_dur
   if redis.call('EXISTS', KEYS[2]) == 1 then
     return {-1, redis.call('TTL', KEYS[2])}        -- locked: caller raises LimitExceeded
   end
   local n = redis.call('INCR', KEYS[1])
   if n == 1 then redis.call('EXPIRE', KEYS[1], tonumber(ARGV[1])) end
   if n >= tonumber(ARGV[2]) then
     redis.call('SETEX', KEYS[2], tonumber(ARGV[3]), '1')
     redis.call('DEL', KEYS[1])
   end
   return {n, 0}                                     -- reserved; n-th attempt this window
   ```

   This makes "am I allowed, and count me" a single atomic step. Concurrent guesses each get a
   distinct `n`; the moment `n >= MAX_ATTEMPTS` the lockout is set, so the (N+1)-th caller is denied
   within the same window instead of all sailing past a stale read.

2. **Reserve before verify in the logic.** In `RevealSecret`/`ShowSecret` (and V1 after C3), call the
   gate-and-reserve *before* `secret.passphrase?`. On a correct passphrase, **refund** the reserved
   attempt via the existing `clear_passphrase_rate_limit!` (`passphrase_rate_limiter.rb:123-130`) so
   a legitimate user who eventually types it right is not penalised. On a wrong passphrase, the token
   is already counted — no second round-trip.

   ```ruby
   # raise_concerns: reserve+gate atomically (raises LimitExceeded if locked)
   reserve_passphrase_attempt!(secret.identifier) if secret.has_passphrase?
   # process: verify
   if correct_passphrase
     clear_passphrase_rate_limit!(secret.identifier)   # refund + reset
   end
   # (no separate record step — the reserve already counted it)
   ```

   This preserves "a wrong passphrase does not consume/burn the secret" (C1) while making the limit
   decision atomic and the over-shoot exactly zero per window.

   **Confirm first (behavioural):** reserving at gate time means an *empty* or absent passphrase
   submission must not consume a token. Mirror the existing V2 guard
   (`show_secret.rb:63` only records when `!passphrase.empty?`) so probing without a passphrase
   doesn't burn the budget. Validate the refund-on-success path against the existing reveal specs.

3. Keep `MAX_ATTEMPTS`/`ATTEMPT_WINDOW`/`LOCKOUT_DURATION` unchanged
   (`passphrase_rate_limiter.rb:28-34`).

#### Alternatives considered

- **Wrap check+verify+record in a Familia lock keyed on the identifier.** Correct but heavier (lock
  key + stale-lock handling) than a single atomic Lua. The reserve-before-verify approach needs no
  lock.
- **Leave it; the over-shoot is bounded.** Rejected on "get it right" grounds — the fix is small and
  removes a real parallel-guessing amplifier.

### C4b — boot guard against running as `test` in production

Add a fail-fast guard at boot that refuses to start a non-test process under `RACK_ENV=test`. Boot
already resolves env at `boot.rb:111` and `configure_familia.rb:44-46` already sets the precedent of
a hard `raise` when the test environment is misconfigured (it refuses any Redis URI that isn't port
2121 under `RACK_ENV=test`). Add the inverse guard:

```ruby
# in boot!, right after `OT.env = ENV['RACK_ENV'] || 'production'` (boot.rb:111)
# A production/staging process must never run with the test-tier Argon2 cost
# (passphrase_hashing.rb:68-74). The test suite sets OT.testing? via its own harness;
# a deployed process must not claim RACK_ENV=test.
if ENV['RACK_ENV'] == 'test' && !running_under_test_harness?
  raise Onetime::Problem,
        'Refusing to boot: RACK_ENV=test outside the test suite would select weak ' \
        'Argon2 parameters (32 KiB/1 pass). Unset RACK_ENV or set it to production.'
end
```

`running_under_test_harness?` should be a positive signal that the test runner is in control, **not**
merely `RACK_ENV=test` — otherwise the guard would tautologically pass. The goal is: only the real
test suite gets the cheap cost; everything else fails loudly.

```ruby
def running_under_test_harness?
  # corrected 2026-06-24: must be true under BOTH runners. This project uses RSpec AND
  # Tryouts v3 (try/); `defined?(RSpec)` is nil under Tryouts, so a sole RSpec check would
  # false-negative and the boot guard above would kill the whole Tryouts suite at boot.
  # Use an explicit env signal the harness exports, recognised by either runner.
  ENV['OT_TEST'] == '1' || defined?(RSpec) || defined?(Tryouts)
end
```

The harness (RSpec `spec_helper` and the Tryouts runner) sets `OT_TEST=1`; the `defined?` checks are
belt-and-suspenders for either runner being loaded. The key fix is that the predicate is **not**
keyed on RSpec alone.

Optionally, also raise `t_cost` for production from 2 toward 3–4 if a quick benchmark on target
hardware keeps per-verify latency acceptable; this is a tuning improvement, not required for the
guard.

## Test / verification

- **C4a concurrency:** spin N concurrent wrong-passphrase reveals against one identifier; assert at
  most `MAX_ATTEMPTS` verifications are attempted before lockout and the (MAX+1)-th is denied
  *within the same window* (today this over-shoots to N).
- **C4a refund:** wrong, wrong, correct → assert attempts/lockout keys are cleared and no spurious
  lockout remains.
- **C4a no-passphrase probe:** submit with empty/absent passphrase repeatedly → assert no tokens
  consumed (no lockout).
- **C4b guard:** boot with `RACK_ENV=test` but without the test-harness signal → assert it raises;
  boot under the real suite → assert it proceeds and uses the test cost; boot as production →
  assert the 64 MiB cost is selected.

## Effort & risk

- **Effort:** Medium for C4a (Lua change + reorder reserve/verify in the logic, shared across
  versions via the mixin), Low for C4b (one boot guard).
- **Risk:** Low/medium. C4a touches the reveal path's gating, so cover with the concurrency + refund
  tests; the happy path (correct first try) is unchanged thanks to the refund. C4b is purely
  defensive and cannot affect the legitimate test suite if the harness signal is correct.
- **Priority:** Medium — bundle with C3 (same limiter) and after C1.
