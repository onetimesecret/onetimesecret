# C1 — One-time reveal/burn is not concurrency-safe (atomic consume)

- **Severity:** High — **PoC-confirmed** (12/12 parallel processes obtained the same secret's plaintext)
- **Status:** Proposed fix
- **Affects default config?** **Yes** (anonymous secret sharing)
- **Related:** finding 03 F1; reproduction in `../poc/race_reveal_model.rb`, `../poc/_reveal_worker.rb`,
  evidence `../evidence/race_poc_output.md`
- **Primary files:** `lib/onetime/models/secret/features/secret_state_management.rb`,
  `apps/api/v2/logic/secrets/reveal_secret.rb`, `apps/api/v1/logic/secrets/show_secret.rb`,
  `apps/api/v2/logic/secrets/burn_secret.rb`, `familia/lib/familia/horreum/{persistence,database_commands}.rb`

## Problem (recap)

The reveal/burn flow is a non-atomic check-then-act. Each request: loads the secret, checks
`viewable?`/in-memory `state`, decrypts, then calls `revealed!`/`burned!` which calls `destroy!`
unconditionally. Nothing binds the state check to the delete, so two concurrent requests for the same
identifier each pass the gate, each decrypt, and each return the plaintext — defeating the single-use
guarantee (and its tamper-evidence: a victim still sees a successful one-time reveal even though an
interceptor already read it).

```ruby
# secret_state_management.rb:60+
def revealed!
  return unless state?(:new) || state?(:previewed)   # in-memory @state, loaded at request start
  md = load_receipt; md&.revealed!
  @state = 'revealed'; @ciphertext = nil
  destroy!                                            # DEL — not conditioned on current state
end
```

`destroy!` wraps deletes in `MULTI/EXEC` but **without `WATCH`** and **without a state precondition**
(`familia/.../persistence.rb:558`, `database_commands.rb:252`).

### Why a single MRI process hid it (and production won't)

Within one MRI process the GIL serialises the CPU-bound decrypt/routing, so the first request usually
finishes `destroy!` before others load (natural PoC = 1/1). Production runs **clustered Puma (multiple
worker processes)** and typically a network Redis; two simultaneous requests for the same link run on two
processes with no shared GIL, and the load→check→decrypt→destroy window (several Redis round-trips, plus
Argon2 for passphrase secrets) is wide. The multi-process PoC reproduced **12/12**.

## Root cause

The authoritative "this secret has been consumed" decision lives in application memory, not in a single
atomic server-side operation. The check (`viewable?`/`state?`) and the mutation (`destroy!`) are separate
round-trips with no optimistic-lock or conditional delete between them.

## Prescribed resolution

Collapse **check → claim → destroy** into one atomic, single-winner server-side operation, and only
decrypt/return the value to the winner. The codebase already ships the right primitives —
`Familia::Lock` (SETNX+Lua) and `atomic_write(watch_keys:, pre_check:)` (WATCH+MULTI/EXEC) — and uses
them for org/domain creation; apply the same discipline to the crown-jewel path.

### Option A (preferred) — atomic claim via Lua (`HGETALL`+`DEL` conditioned on state)

Add a model method that atomically reserves-and-removes the secret, returning the encrypted payload only
to the caller that wins:

```ruby
# Onetime::Secret — runs server-side; exactly one caller gets the fields, the rest get nil.
CONSUME_LUA = <<~LUA
  local st = redis.call('HGET', KEYS[1], 'state')
  if st == 'new' or st == 'previewed' then
    local data = redis.call('HGETALL', KEYS[1])
    redis.call('DEL', KEYS[1])
    return data
  end
  return nil
LUA

def consume!            # returns the field hash if this caller won, else nil
  raw = dbclient.eval(CONSUME_LUA, keys: [dbkey])
  return nil if raw.nil? || raw.empty?
  Hash[*raw]            # winner only
end
```

Caller flow (reveal):

```ruby
fields = secret.consume!                       # atomic single-winner
raise OT::MissingSecret unless fields          # lost the race / already consumed
# rebuild ciphertext from fields, then decrypt — only the winner reaches here
@secret_value = decrypt_from(fields)
update_receipt_and_counters(fields)            # md.revealed!, secrets_shared, etc.
```

Passphrase-protected secrets: verify the passphrase **before** `consume!` using a read-only load (the
existing `PassphraseRateLimiter` still applies); only `consume!` on correct passphrase + `continue`.
This keeps "wrong passphrase doesn't burn the secret" behaviour while making the actual reveal atomic.

### Option B — `WATCH` + `MULTI/EXEC` with a state precondition

Use the existing `atomic_write(watch_keys: [dbkey], pre_check: -> { reload; state new/previewed })`
machinery: WATCH the key, re-read state, and inside MULTI set `state=revealed` + delete; retry/deny on
abort. Functionally equivalent; Option A is one round-trip and simpler to reason about.

### Option C — `Familia::Lock` around reveal/burn

Wrap the consume in `Familia::Lock` keyed on the identifier. Correct, but adds a lock key + failure modes
(stale locks); prefer A unless a lock is needed for broader invariants.

### Cross-cutting

- Apply identically to **burn** (`burned!`) and the **v1/v3** reveal paths — all funnel through the same
  non-atomic model methods, so fixing `consume!`/`revealed!`/`burned!` covers every API version.
- Keep "decrypt happens only after a successful claim" — never decrypt-then-claim.
- Receipt/owner counter updates move to the winner, after the claim.

## Test / verification

- Add a concurrency regression test driven by the multi-process PoC harness
  (`../poc/_setup_secret.rb` + `_reveal_worker.rb`): N independent processes reveal the same id; assert
  **exactly one** returns the plaintext and the rest get `MissingSecret`.
- Unit test `consume!`: two threads/fibers against a stubbed/real Redis → one hash, one nil.
- Regression for passphrase secrets: wrong passphrase does **not** consume; correct + `continue` consumes once.

## Effort & risk

- **Effort:** Medium. New `consume!` (model + familia eval), refactor of `reveal_secret.rb` /
  `show_secret.rb` / `burn_secret.rb` to claim-then-decrypt.
- **Risk:** Low/medium — touches the core path, so cover with the concurrency test above and the existing
  reveal/burn specs. Behaviour is unchanged for the single-request happy path.
- **Priority:** highest — it is the product's defining guarantee and affects the default deployment.
