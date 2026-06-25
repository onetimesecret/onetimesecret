# P4 — V1 Basic Auth timing-distinguishable username enumeration

- **Severity:** Low/Medium
- **Status:** Proposed fix — **superseded by re-verification correction (2026-06-24) below**
- **Affects default config?** Conditional — only when API v1 + Basic Auth (`session_auth_enforced?`) is enabled
- **Related:** P5 (log injection on the same code path). Findings 04 #5, §8 "Enumeration — V1 exception".
- **Primary files:** `apps/api/v1/controllers/base.rb:68-71` (the timing-distinguishable path),
  `lib/onetime/application/auth_strategies/basic_auth_strategy.rb:42-91` (the V2/V3 constant-time
  reference to mirror), `lib/onetime/models/customer.rb` (`Onetime::Customer.dummy`, `apitoken?`)

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §4 table row P4).**
> The prescribed fix below is **unsound** — swapping in `Customer.dummy` does not close the timing oracle.
> `Customer.dummy` (`customer.rb:331-341`) sets a dummy `passphrase` but assigns **no `apitoken`**, so
> `apitoken?` short-circuits at `customer.rb:263` (`return false if apitoken.to_s.empty? || value.to_s.empty?`)
> and `secure_compare` is **never reached** for the dummy — the missing-user path stays fast, exactly the
> oracle the fix targets. The "expensive BCrypt comparison" premise is also wrong: `apitoken?` uses
> `Rack::Utils.secure_compare` (`customer.rb:265`, sub-microsecond), not BCrypt.
>
> **Correction:** give the dummy a real token so a wrong guess actually reaches `secure_compare` and the
> compare time is constant. In `Customer.dummy` assign `dummy_cust.apitoken = SecureRandom.hex(32)` before
> `freeze`; then the V1 `target_cust.apitoken?(apitoken)` call runs the constant-time `secure_compare` whether
> or not the user exists. Residual (optional, defense-in-depth): `load_by_extid_or_email` still deserializes on
> a hit vs returns `nil` on a miss — a noise-dominated difference, not the dominant signal.

## Problem (recap)

V1's controller-level `authorized` (`base.rb:68-71`) loads the customer and only runs the (expensive)
BCrypt-backed `apitoken?` check **when the customer exists**:

```ruby
possible = Onetime::Customer.load_by_extid_or_email(custid)
@cust = possible if possible&.apitoken?(apitoken)   # apitoken? only runs when possible != nil
raise OT::Unauthorized, 'Invalid credentials' if cust.nil?
```

For a non-existent username, `possible` is `nil`, the `&.apitoken?` short-circuits, and the expensive
comparison is skipped — so the response returns measurably faster than for an existing username with a
wrong token. The error messages are uniform (`'Invalid credentials'`, `:58,:61,:71,:86`), so this is a
**timing-only** oracle, but it still lets an attacker enumerate valid usernames/emails.

V2/V3 do **not** have this problem: `BasicAuthStrategy` uses a dummy customer with a real BCrypt hash so
the same ~constant-time work runs whether or not the user exists (`basic_auth_strategy.rb:42-91`).

## Root cause

The V1 path uses Ruby's safe-navigation short-circuit (`possible&.apitoken?`) as the existence gate, which
makes the cost of the cryptographic comparison conditional on user existence. V1 predates (and never
adopted) the dummy-customer constant-time mitigation that V2/V3 introduced.

## Prescribed resolution

Mirror the V2/V3 constant-time path in V1: **always** perform the BCrypt token comparison against a real
hash, using a dummy customer when the user doesn't exist, and decide success only afterward.

### Implementation steps

1. **Always run `apitoken?` against a real hash.** Replace the short-circuit with the V2/V3 pattern
   (`basic_auth_strategy.rb:54-60`):

   ```ruby
   # apps/api/v1/controllers/base.rb  (inside the Basic Auth branch, replacing :68-71)
   cust_record = Onetime::Customer.load_by_extid_or_email(custid)

   # Timing-attack mitigation: always perform the expensive BCrypt comparison,
   # using a dummy customer with a real hash when the user does not exist, so
   # the work (and thus the response time) is identical for existing and
   # non-existing usernames. Mirrors BasicAuthStrategy#authenticate.
   target_cust       = cust_record || Onetime::Customer.dummy
   valid_credentials = target_cust.apitoken?(apitoken)

   # Only succeed with a real customer AND valid credentials.
   @cust = cust_record if cust_record && valid_credentials
   raise OT::Unauthorized, 'Invalid credentials' if cust.nil?
   ```

   This keeps the existing uniform error message and the existing `@cust`-nil guard at `base.rb:90`; the
   only change is that the BCrypt comparison now executes on every attempt.

2. **Reuse the exact same `dummy`/`apitoken?` primitives** that V2/V3 already rely on
   (`Onetime::Customer.dummy`, `Customer#apitoken?`) so there is a single constant-time implementation and
   no second dummy hash to keep in sync. Do not introduce a V1-specific comparison.

3. **Confirm `apitoken?` itself is constant-time** for a given hash (it is the same method V2/V3 trust at
   `basic_auth_strategy.rb:57`). The mitigation only holds if `apitoken?` does not itself early-return on a
   malformed/empty token before hashing; the `custid`/`apitoken` empty-string guard already runs earlier
   (`base.rb:61`), so by this point both are non-empty.

### Alternatives considered

- **Deprecate / remove V1 Basic Auth entirely** (Finding §8 suggests this as an option). Valid long-term —
  V2/V3 are the maintained path — but until V1 is removed it still authenticates real requests, so the
  cheap constant-time fix should land regardless. Treat removal as a separate deprecation track.
- **Add an artificial fixed delay (`sleep`) on the not-found path:** fragile and a DoS amplifier (ties up a
  worker per request); a real BCrypt comparison is the correct constant-work approach and matches V2/V3.
- **Normalize only the error message/status:** already done (uniform `'Invalid credentials'`); it does not
  address the timing side channel, which is the actual gap here.

## Test / verification

- Timing parity: with auth enabled, send Basic Auth for (a) a known-existing username with a wrong token
  and (b) a definitely-non-existent username, many iterations; the response-time distributions should be
  statistically indistinguishable (both incur the BCrypt cost). Before the fix, (b) is consistently faster.
- Functional regression: valid `custid` + valid apitoken → authenticated (`@cust` set), unchanged; valid
  `custid` + wrong token → `Unauthorized`; non-existent `custid` → `Unauthorized`; all return the same
  `'Invalid credentials'` message and status.
- Anonymous and `disabled_response` paths (`base.rb:65,75-87`) unchanged.

## Effort & risk

- **Effort:** Low — a few lines in one method, reusing existing `Customer.dummy`/`apitoken?`.
- **Risk:** Low — behaviour-preserving for all valid/invalid outcomes; the only change is that every
  attempt now pays the BCrypt cost (intended). Confirm `Customer.dummy` is available in the V1 runtime
  (it is loaded for V2/V3) and that the per-request BCrypt cost is acceptable for V1 throughput — pair with
  P3 so the constant-cost path can't be abused for CPU exhaustion.
