# C10 — SECRET Lifecycle Safety: Design

> **Status:** Proposed (2026-07-11). This is the "short design first" that
> [work-chunks C10](./install-onboarding-work-chunks.md#c10--secret-lifecycle-safety-qs-6)
> requires before implementation. Source finding: QS-6 in
> [install-onboarding-current-state.md](./install-onboarding-current-state.md).
> Appetite: 2–4 days. Risk class: product code on the crypto path — every
> change here is gated on the proof plan in §6, and the no-rotation-configured
> path must be byte-identical to today's behavior.

## 1. Problem (QS-6)

Two distinct failures, one root cause — nothing binds the running SECRET to
the data it encrypted:

1. **Undetected at boot.** An operator who loses `.env`, regenerates secrets,
   or points the app at a restored Valkey dump gets a clean boot and a
   working-looking site. Every pre-rotation ciphertext is silently
   unrecoverable.
2. **Destructive at reveal.** `Secret#reveal!`
   (`lib/onetime/models/secret/features/secret_state_management.rb:97`)
   persists the atomic claim (`win_reveal_claim!`, CAS `new/previewed →
   revealed`) *before* decrypting. A wrong-key decrypt raises
   `Familia::EncryptionError` after the CAS has committed: the request 500s,
   `consume_after_reveal!` never runs (record and ciphertext survive in
   Valkey), but `state=revealed` is terminal — `viewable?` is false forever.
   Restoring the correct SECRET cannot un-burn it. Each retry on another
   secret burns that one too.

The v1 path (`apps/api/v1/logic/secrets/show_secret.rb:66`) decrypts *before*
its `revealed!` claim, so it is incidentally non-destructive already; v2
`reveal!` — the path everything current uses — is the destructive one. v3
delegates to v2 logic.

## 2. Ground truth this design builds on

- `Onetime::KeyDerivation` (`lib/onetime/key_derivation.rb`) — HKDF-SHA256
  over the root SECRET with purpose-scoped `info` strings (`session`,
  `verifiable-id`, `familia-enc`). The verifier is one more purpose.
- `ConfigureFamilia` (`lib/onetime/initializers/configure_familia.rb`) —
  already versions encryption keys (`v1` legacy SHA-256, `v2` HKDF, writes
  tagged `v2`). Rotation slots into this existing mechanism.
- `win_reveal_claim!` / `consume_after_reveal!` — the ADR-019 at-most-once
  claim. This design does not weaken it (§3.2).
- Boot initializer registry with `@depends_on` / `@provides`
  (`lib/onetime/boot/initializer.rb`) and `FatalBootError` for fatal-in-CLI
  handling (#3189).
- doctor v2 (`bin/setup --doctor`, C9) with contexts and connectivity probes;
  `/health/advanced` sub-checks.

## 3. Design

### 3.1 Boot-time key verifier

**Derivation.** New runtime-only purpose in `KeyDerivation::PURPOSES`:
`key_verifier: { info: 'key-verifier', length: 32 }` (no `env_var`, same
pattern as `familia_enc`). The verifier is one-way and purpose-separated: it
is not equal to any working key, and publishing it reveals nothing about
SECRET beyond an offline-guessing oracle — irrelevant for the 64-random-byte
SECRETs `rake ots:secrets` generates, and no worse than any stored ciphertext
for operator-chosen weak secrets.

**Storage.** Plain Valkey string key `onetime:secret_verifier`, value =
hex-encoded verifier, no TTL, in the models logical DB (Familia default
connection). If the key is flushed along with everything else, there is
nothing left to protect and re-adoption is correct.

**Boot check.** New initializer `check_secret_verifier.rb`,
`@depends_on = [:familia_config]`:

- Key absent → `SET NX` (adopt) and log at info. First boot and
  post-flush both land here.
- Present and equal → debug log.
- Present and different → **mismatch**: multi-line `boot_logger.error`
  naming the two likely causes (SECRET changed under existing data; app
  pointed at another install's datastore) and the fix commands
  (`restore the previous SECRET` / `rake ots:secrets:adopt` if the rotation
  was intentional). Sets `Onetime.secret_verifier_state = :mismatch`.
- Valkey unreachable → `:unavailable`, debug only; connectivity failures are
  doctor's and the connection pool's problem, this check must never add a
  second boot failure for the same cause.

State is exposed as `Onetime.secret_verifier_state`
(`:ok | :adopted | :mismatch | :unavailable`) for the reveal fast-fail
(§3.2), `/health/advanced`, and the rake task.

**Policy knob.** `site.secret_verifier_mode: warn | enforce | off`, default
`warn` (the chunk says warn loudly; halting by default would brick running
deploys on their first upgrade to this code). `enforce` raises
`FatalBootError` on mismatch. `off` skips the check entirely (escape hatch
for exotic multi-tenant datastore setups).

**Surfacing.**
- `/health/advanced` gains a `secret_verifier` sub-check; mismatch degrades
  top-level status. (QS-7's grep-the-whole-body healthcheck bug means the
  container healthcheck won't notice — that stays QS-7's fix, not C10's.)
- doctor v2 gains a check in the app context that shells
  `bundle exec rake ots:secrets:verify` — exit 0 match, 1 mismatch, 2 never
  adopted, 3 datastore unreachable — printing the same fix commands.
- `rake ots:secrets:adopt` re-stamps the verifier after an intentional
  rotation. Destructive-adjacent, so it requires `CONFIRM=yes` and prints
  what data (if any) the old verifier was protecting.

### 3.2 Non-destructive reveal on key mismatch

Two layers, cheapest first:

**Fast-fail before the claim (global signal).** `RevealSecret#raise_concerns`
(and v2 `ShowSecret`'s reveal-capable sibling) raises the new typed error
when `Onetime.secret_verifier_state == :mismatch` — before any CAS. When the
whole install's key is wrong, no secret should pay for the diagnosis.

**Claim rollback (per-secret signal).** For the residual case — verifier
matches but this ciphertext predates an adopted rotation — `reveal!` becomes:

```ruby
def reveal!(passphrase_input: nil, actor_context: nil)
  prior_state = state            # 'new' or 'previewed', read before the CAS
  return unless win_reveal_claim!

  begin
    plaintext = decrypted_secret_value(passphrase_input: passphrase_input)
  rescue Familia::EncryptionError
    # Zero plaintext was produced: returning the claim cannot violate
    # ADR-019's at-most-once display. Only the claim holder can be in
    # :revealed here, so the CAS back cannot race another winner. The CAS
    # is a pure Redis Lua boolean (state_cas.rb) that never touches memory
    # state, so @state must be restored explicitly.
    compare_and_set_state!(prior_state, [:revealed])
    @state = prior_state
    raise Onetime::SecretUndecryptable
  end

  consume_after_reveal!(actor_context: actor_context)
  plaintext
end
```

`Onetime::SecretUndecryptable` (new, in `lib/onetime/errors.rb`) maps through
the ADR-013 wire format to **HTTP 503** with error code
`secret_undecryptable` and an i18n message telling the recipient the link is
intact and the site operator must restore the encryption key. The mapping is
one `router.register_error_handler` registration in
`lib/onetime/application/otto_hooks.rb` — the existing chokepoint for every
typed error, with 503 precedent already there
(`Billing::CircuitOpenError`). 503 is the
honest status: server-side condition, retryable after operator action. The
RevealSecret header comment's warning about non-2xx responses reverting the
UI to click-to-reveal is exactly the behavior we want here — the secret *is*
still revealable.

Best-effort observability: record `reveal_failed_undecryptable` through the
receipt's org-audit fan-out (same rescue-and-log posture as the rest of
`AccessTimeline`).

**Rejected alternatives.**
- *Decrypt before claiming* (v1's ordering): forfeits ADR-019's
  by-construction property that plaintext cannot exist without a won claim.
- *A `quarantined` lifecycle state*: every state consumer (`state_cas`
  allowlists, `viewable?`, safe_dump, frontend state handling) would need to
  learn it, and it buys nothing — rollback already leaves the secret
  claimable again the moment the key is right, with the typed error carrying
  the "something is wrong" signal in the meantime.
- *Wrapping v1 the same way*: v1 is maintenance-only and already
  non-destructive by ordering; leave it.

### 3.3 Rotation and backup story

**Backup (docs).** New operator doc (linked from SUPPORT.md and the
`.env.reference` SECRET entry): what derives from SECRET (the
`key_derivation.rb` tree), what is lost if it is lost (all ciphertext,
permanently; sessions and identifiers merely regenerate), and the guidance —
treat SECRET like the database itself: store a copy in a secret manager,
never regenerate casually, `bin/setup --init` will never overwrite an
existing one.

**Rotation (mechanism, appetite-gated).** `SECRET_PREVIOUS` env var
(comma-separated, decrypt-only). When set, `ConfigureFamilia` registers the
previous secrets' derived keys so old envelopes keep decrypting while new
writes use the current SECRET:

- No `SECRET_PREVIOUS` (the overwhelmingly common case): configuration is
  byte-identical to today — `v1`/`v2` from current SECRET, writes tagged
  `v2`. Zero change, zero risk.
- `SECRET_PREVIOUS` set: `v1`/`v2` map to the *previous* secret's derived
  keys (that is what all existing envelopes were written with); current
  writes move to a content-addressed version tag derived from the current
  verifier (e.g. `:"r<first-8-hex>"`). Content-addressing makes every future
  generation's tag unambiguous with no rotation counter to persist — each
  entry in the `SECRET_PREVIOUS` list registers under its own computed tag.

Runbook: set `SECRET_PREVIOUS` to the old value, install the new SECRET, run
`rake ots:secrets:adopt`, keep the previous secret registered for at least
the longest secret TTL plus receipt TTL, then drop it. Data older than the
registered chain is not lost to a burn — §3.2 quarantine-by-rollback means it
sits unrevealed until the key returns or it expires.

**Implementation checkpoint:** verify familia 2.11 round-trips arbitrary
version symbols in envelopes before committing to content-addressed tags; if
it normalizes them, the fallback is a persisted rotation counter in the same
`onetime:secret_verifier` neighborhood. We own the gem (delano/familia), so
an upstream tweak is available either way.

**Explicit cut line:** if appetite runs out, Part 3 ships docs-only — the
runbook then documents rotation as "old ciphertexts become undecryptable but
are preserved by §3.2 and age out". The verifier (§3.1) and non-destructive
reveal (§3.2) are the non-negotiable core of C10.

## 4. Out of scope

- Re-encryption tooling (walking ciphertexts to the new key) — secrets age
  out in days; the decrypt-only chain covers the window.
- Fixing QS-7 (healthcheck grep) — separate papercut.
- `IDENTIFIER_SECRET` verification-on-read — tracked in #3630.
- Any change to burn (`burned!` never decrypts) or to preview claims.

## 5. Proof plan (from the chunk, made concrete)

**Unit specs** (tryouts alongside the existing secret-state coverage; RSpec
where an existing context file fits):
- `KeyDerivation` verifier purpose: deterministic, ≠ every other purpose's
  output.
- Initializer states against the test Valkey (:adopted on absent, :ok on
  match, :mismatch on differ, :unavailable on connection refused; `enforce`
  raises, `warn` boots).
- Reveal rollback: stub `decrypted_secret_value` to raise
  `Familia::EncryptionError`; assert state returns to the pre-claim value,
  the record and ciphertext survive in Valkey, `SecretUndecryptable`
  propagates, and a subsequent un-stubbed `reveal!` succeeds and consumes.
- Race semantics unchanged: loser still gets nil; winner-then-rollback
  followed by a second caller winning is a legal sequence (zero plaintexts
  were displayed).
- Fast-fail: `secret_verifier_state = :mismatch` → typed error raised in
  `raise_concerns`, no CAS taken.

**Harness lane** — `scripts/test-install/secret-rotation.sh`, wired into the
C7 lane family's CI:
1. Boot clean, create a secret via the API, capture the link.
2. Restart with a regenerated SECRET. Assert the boot log carries the
   mismatch warning and `/health/advanced` reports the degraded sub-check.
3. Attempt the reveal. Assert a 503 with `secret_undecryptable` AND that the
   secret record still exists with its ciphertext.
4. Restore the original SECRET, restart. Assert verifier :ok and the reveal
   now returns the original plaintext exactly once (second attempt 404s).

Step 3+4 is the chunk's stated proof verbatim: boots with a rotated SECRET
and the secret survives a failed reveal.

## 6. Sequencing (2–4 day appetite)

- **Day 1:** §3.1 — verifier purpose, initializer, `ots:secrets:verify` /
  `ots:secrets:adopt`, health + doctor surfacing, unit specs.
- **Day 2:** §3.2 — rollback, typed error, wire mapping, fast-fail, race
  specs.
- **Day 3:** §5 harness lane + CI wiring.
- **Day 4 (buffer):** §3.3 `SECRET_PREVIOUS` chain + rotation runbook; if
  the buffer is consumed by Days 1–3, ship the runbook docs-only per the cut
  line.
