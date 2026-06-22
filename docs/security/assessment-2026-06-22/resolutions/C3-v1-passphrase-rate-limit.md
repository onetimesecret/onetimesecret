# C3 — V1 reveal path has no passphrase rate limiting

- **Severity:** Medium — **CONFIRMED** in source
- **Status:** Proposed fix
- **Affects default config?** **Yes, if the V1 API is mounted** — V1 secret routes are wired in
  `apps/api/v1/controllers/index.rb` and remain routable
- **Related:** finding 03 F3; finding 03 F4 / C4 (the rate-limiter's own check/record gap);
  C1 (atomic reveal — the same V1 path is also non-atomic)
- **Primary files:** `apps/api/v1/logic/secrets/show_secret.rb`,
  `apps/api/v1/controllers/index.rb`,
  `lib/onetime/security/passphrase_rate_limiter.rb`,
  `apps/api/v2/logic/secrets/{reveal_secret,show_secret}.rb` (the reference implementation)

## Problem (recap)

The per-secret passphrase brute-force protection — `Onetime::Security::PassphraseRateLimiter`
(5 attempts / 10 min → 30 min lockout, `lib/onetime/security/passphrase_rate_limiter.rb:28-34`) —
is wired only into the **V2** logic. Both V2 entry points include the module and call it:

- `RevealSecret` includes it (`reveal_secret.rb:35`), checks before verifying
  (`:68`), and records on failure (`:194`).
- `ShowSecret` includes it (`show_secret.rb:20`), checks (`:53`), records/clears (`:66-70`).

The **V1** `ShowSecret` does **neither**. It does not include the module, and `process` calls
`secret.passphrase?(passphrase)` with no attempt counting or lockout:

```ruby
# apps/api/v1/logic/secrets/show_secret.rb:26-31
def raise_concerns
  raise OT::MissingSecret if secret.nil? || !secret.viewable?
end

def process
  @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
  ...
```

There **is** a coarse read-rate-limit at the controller level
(`check_rate_limit!(:show_secret, V1_RATE_LIMIT_MAX_READS)`, `index.rb:154`), but that is a
per-caller (IP/session) read throttle, **not** a per-secret passphrase lockout. It does not lock the
*secret* after N wrong passphrases, and it does not share state with the V2 limiter.

### Why this is exploitable

If V1 is mounted (it is, by default — `index.rb:157` constructs
`V1::Logic::Secrets::ShowSecret`), an attacker can brute-force a passphrase-protected secret through
V1 with no per-secret lockout: Argon2id (`passphrase_hashing.rb:48-62`) slows each guess but does
not stop online guessing, and weak passphrases fall quickly. Worse, **V1 attempts do not count
against the V2 lockout**, so even a deployment that relies on V2's protection is bypassable by
pointing the guesses at V1.

## Root cause

Passphrase rate limiting was added to the V2 logic only; the older V1 `ShowSecret` (a separate class,
`V1::Logic::Base` subclass) was never retrofitted. The protection lives in the logic layer, so any
API version that does not include the mixin is unprotected — and the limiter keys on the **secret
identifier**, so all versions should share one bucket but only V2 currently writes to it.

## Prescribed resolution

Pick one of two paths. **Both are acceptable; prefer (B) if V1 still has real consumers, (A) if it
can be sunset.**

### Option A (preferred if feasible) — retire / disable the V1 secrets endpoints

If V1 is deprecated, the cleanest long-term fix is to stop routing it. Gate the V1 secret actions
(`show_secret`, `burn_secret`, `conceal_secret`, `generate_secret` in `index.rb`) behind a config
flag (default off) or remove the routes, returning `410 Gone`/`404`. This eliminates the unprotected
path entirely rather than maintaining parallel protection.

**Confirm first:** check telemetry/access logs for live V1 secret traffic and any first-party
clients (CLI, integrations) pinned to V1 before disabling. If V1 is in active use, take Option B.

### Option B — wire the same limiter into V1 `ShowSecret`

Mirror the V2 implementation exactly so the two paths share the **same** Redis bucket (the limiter
keys on `secret.identifier`, `passphrase_rate_limiter.rb:134-139`, via
`Onetime::Secret.dbclient`, `:144-146` — so it is self-contained and needs no `redis` helper from
the host class).

#### Implementation steps

1. **Require + include** the mixin (matching `reveal_secret.rb:5,35`):

   ```ruby
   # top of apps/api/v1/logic/secrets/show_secret.rb
   require 'onetime/security/passphrase_rate_limiter'

   class ShowSecret < V1::Logic::Base
     include Onetime::Security::PassphraseRateLimiter
   ```

2. **Check before verifying**, in `raise_concerns` (mirrors `reveal_secret.rb:68` /
   `show_secret.rb:53`). The check must run *before* `process` calls `passphrase?`:

   ```ruby
   def raise_concerns
     raise OT::MissingSecret if secret.nil? || !secret.viewable?
     check_passphrase_rate_limit!(secret.identifier) if secret.has_passphrase?
   end
   ```

3. **Record on failure / clear on success**, in `process`. V1's `process` computes
   `@correct_passphrase` at line 31; branch on it the way V2's `show_secret.rb:63-71` does:

   ```ruby
   @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)

   if secret.has_passphrase? && !passphrase.to_s.empty?
     if correct_passphrase
       clear_passphrase_rate_limit!(secret.identifier)
     else
       record_failed_passphrase_attempt!(secret.identifier)
     end
   end
   ```

4. **Surface the lockout.** `check_passphrase_rate_limit!` raises `Onetime::LimitExceeded`
   (`passphrase_rate_limiter.rb:79-83`). Confirm the V1 controller path renders that as a 4xx (the
   V1 controller wraps logic in `authorized(...)`; verify `LimitExceeded` maps to the standard
   limit response rather than a 500). If V1 has no handler, add one mirroring V2.

#### Critical: one shared bucket across V1/V2/V3

The whole point is that **an attacker cannot reset or sidestep the lockout by switching API
versions**. Because the limiter keys on `secret.identifier` and reads `Onetime::Secret.dbclient`
directly, V1, V2 (`RevealSecret`, `ShowSecret`), and V3 (`apps/api/v3/logic/secrets.rb:135`
subclasses V2's `ShowSecret`) all hit `passphrase:attempts:{id}` / `passphrase:locked:{id}`
automatically once V1 includes the mixin. **Do not introduce a V1-specific key prefix** — that would
re-open the bypass. Add a regression test that interleaves V1 and V2 failed attempts against the same
identifier and asserts a single 5-strike lockout governs both.

> Note the interaction with C4: the gate-read and failure-record are still two round-trips, so the
> small concurrency over-shoot described in C4 applies here too. Fix C4 once and both V1 and V2
> benefit (the limiter is shared code).

## Test / verification

- **V1 lockout regression:** create a passphrase secret; via the V1 `ShowSecret` path submit 5 wrong
  passphrases → assert the 6th raises `LimitExceeded` and the controller returns the limit response,
  not the secret.
- **Cross-version bucket:** 3 wrong attempts via V1 + 2 via V2 against the same identifier → the next
  attempt (either version) is locked. This is the key anti-bypass assertion.
- **Clear on success:** wrong, wrong, then correct → lockout state cleared; subsequent reveal works
  (subject to the one-time consume, see C1).
- **Option A path (if chosen):** assert V1 secret routes return 410/404 (or are absent) when the
  flag is off, and that the V2 path is unaffected.

## Effort & risk

- **Effort:** Low. Option B is ~10 lines mirroring V2; Option A is a routing/flag change.
- **Risk:** Low. Option B reuses proven, already-deployed code and adds protection without changing
  the happy path. Option A is only risky if a live consumer depends on V1 — hence "Confirm first".
- **Priority:** High — second after C1. An unprotected brute-force path against passphrase secrets
  undercuts the V2 lockout for the same secrets.
