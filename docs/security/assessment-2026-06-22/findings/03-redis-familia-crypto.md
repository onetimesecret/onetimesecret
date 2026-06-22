# Security Assessment — Redis / Familia / Cryptography

**Scope:** Secret/token generation & predictability, secret encryption at rest, passphrase
hashing, the one-time (reveal/burn) guarantee & TOCTOU, Redis key naming, randomness audit,
Lua/command injection, and DoS.

**Repos:** `/home/user/onetimesecret` (app), `/home/user/familia` (Redis ORM).
**Method:** Read-only source review. No runtime exploitation performed; race conditions are
reasoned from code paths and labeled NEEDS-VALIDATION where a live PoC would be required to
demonstrate the window.

**Status legend:** CONFIRMED = verified directly in source. NEEDS-VALIDATION = strongly
indicated by source but requires runtime confirmation of timing/config.

---

## Summary of findings (by severity)

| # | Title | Severity | Status |
|---|-------|----------|--------|
| F1 | TOCTOU race in reveal/burn defeats the one-time guarantee (no atomic state-check-and-destroy) | HIGH | CONFIRMED (race window); NEEDS-VALIDATION (live double-reveal PoC) |
| F2 | Encryption HKDF salt & BLAKE2b personalization left at shared library default (`'FamilialMatters'`) — no per-deployment domain separation | MEDIUM | CONFIRMED |
| F3 | V1 reveal path has no passphrase rate limiting (brute-force on passphrase-protected secrets) | MEDIUM | CONFIRMED |
| F4 | Passphrase rate-limit check/record is non-atomic + capped Argon2 memory cost | LOW/MEDIUM | CONFIRMED |
| F5 | No application-level cap on secret payload size (storage/DoS) | LOW | CONFIRMED |
| F6 | Legacy v1 encryption key = unsalted single SHA-256 of `site.secret` | LOW (informational) | CONFIRMED |

**Positives (verified safe):** Token generation uses 256-bit CSPRNG entropy; encryption is
AEAD (AES-256-GCM / XChaCha20-Poly1305) with per-message random nonces and HKDF/BLAKE2b key
derivation; passphrases use Argon2id with timing-safe verification; all Lua scripts use
parameterized `KEYS`/`ARGV` binding (no injection); identifiers are sanitized with a strict
allowlist before becoming Redis keys. Details in the "Areas reviewed and found sound" section.

---

## F1 — TOCTOU race in reveal/burn defeats the one-time guarantee (HIGH)

**The crown-jewel guarantee.** A "one-time secret" must be revealable exactly once. The
reveal/burn flow performs a **non-atomic check-then-act**: it reads the in-memory state, and
only later destroys the record, with no lock, `WATCH`, conditional Lua, or atomic `GETDEL`
binding the two together.

### Evidence

State guard + destroy (not atomic):
`/home/user/onetimesecret/lib/onetime/models/secret/features/secret_state_management.rb:60-78`
```ruby
def revealed!
  return unless state?(:new) || state?(:previewed)   # reads in-memory @state (loaded at request start)
  md = load_receipt
  md.revealed! unless md.nil?
  @state      = 'revealed'
  @ciphertext = nil
  destroy!                                            # MULTI/EXEC delete, but NOT conditioned on state
end
```

`destroy!` runs a Redis transaction (MULTI/EXEC) that deletes unconditionally — there is **no
`WATCH` on the hash key and no server-side check that state is still `new`**:
`/home/user/familia/lib/familia/horreum/persistence.rb:558-584` (transaction wraps `delete!`
plus related-field cleanup; nothing aborts if a concurrent client already revealed).

The reveal logic decrypts **before** the destroy, into a local that is returned in the
response regardless of who wins the destroy race:
- V2 RevealSecret: `/home/user/onetimesecret/apps/api/v2/logic/secrets/reveal_secret.rb:95` (`@secret_value = secret.decrypted_secret_value(...)`) then `:189` `secret.revealed!`
- V2 ShowSecret: `/home/user/onetimesecret/apps/api/v2/logic/secrets/show_secret.rb:74` then `:154` (`reveal_secret` → `secret.revealed!`)
- V1 ShowSecret: `/home/user/onetimesecret/apps/api/v1/logic/secrets/show_secret.rb:39` then `:71`
- Burn: `/home/user/onetimesecret/apps/api/v2/logic/secrets/burn_secret.rb:54-74` (`viewable?` check at `:55`, `secret.burned!` at `:74`)

The `viewable?`/`receivable?` gate read in `raise_concerns`
(`reveal_secret.rb:64`, `show_secret.rb:49`) is likewise a plain in-memory read of state
loaded by `Onetime::Secret.load` at request start.

### Why this is exploitable

Two (or N) concurrent requests for the same secret identifier each:
1. `Onetime::Secret.load` → both read `state = 'new'`, `viewable? == true`.
2. Both pass `raise_concerns`.
3. Both call `decrypted_secret_value` → both obtain the plaintext.
4. Both call `revealed!` → both pass `return unless state?(:new)` (in-memory, both still `'new'`)
   → both call `destroy!` (the second delete is a harmless no-op).

Result: **the same secret is revealed to two parties**, breaking the core product promise.
The same applies to reveal-vs-burn races (one client reads the plaintext while another burns).

### Contrast — the project already has the right primitives but doesn't use them here

Familia ships a SETNX-based distributed lock and a WATCH+MULTI/EXEC create-if-absent, and the
app uses them elsewhere, just not on the crown-jewel path:
- `Familia::Lock#acquire` / `#release` (atomic Lua delete): `/home/user/familia/lib/familia/data_type/types/lock.rb:16-30`
- `save_if_not_exists!` (WATCH+MULTI/EXEC): `/home/user/familia/lib/familia/horreum/persistence.rb:200-256`
- Used in: `/home/user/onetimesecret/apps/api/organizations/logic/organizations/create_organization.rb:79-84`,
  `/home/user/onetimesecret/apps/api/domains/logic/sender_config/validate_sender_config.rb:79-80`,
  `/home/user/onetimesecret/lib/onetime/operations/provision_sender_domain.rb:82`.

The reveal/burn path uses none of these.

### Impact
Confidentiality breach of the one-time guarantee: a secret can be disclosed to more than one
party, or read after/while being burned. For a product whose entire value proposition is
single-use disclosure, this is high impact.

### Remediation
Make the consume step atomic and authoritative on the server:
- Preferred: a single atomic claim. e.g. a Lua script (or `HGET`+conditional `DEL`/`GETDEL` in
  one server round-trip) that reads `state`, and only if it is `new`/`previewed` deletes the
  key and returns the ciphertext; otherwise returns "already consumed". Decrypt only if the
  claim succeeded. This collapses check-decrypt-destroy into one winner.
- Alternative: `WATCH` the secret key, re-read `state`, and do the state-set + delete inside
  `MULTI/EXEC`; retry/deny on abort. (`save`/`save_fields` already use `transaction`, so the
  machinery exists — it just needs `WATCH` + a state precondition.)
- Or wrap reveal/burn in `Familia::Lock` keyed on the secret identifier.

**Status:** Race window CONFIRMED in source. A live two-request PoC to demonstrate a real
double-reveal is NEEDS-VALIDATION (timing-dependent; widened by passphrase verification cost
and the decrypt happening before destroy).

---

## F2 — Encryption salt/personalization left at shared library default (MEDIUM)

The encrypted-field master key is correctly derived per-deployment from `site.secret` via
HKDF. However, the *second* domain-separation input used inside each provider's own key
derivation (HKDF salt for AES-GCM; BLAKE2b personalization for XChaCha20) is **never set by
the application**, so it falls back to Familia's hardcoded global literal `'FamilialMatters'`.

### Evidence
- App configures only `encryption_keys` and `current_key_version`; it never sets
  `encryption_hkdf_salt` or `encryption_personalization`:
  `/home/user/onetimesecret/lib/onetime/initializers/configure_familia.rb:57-72`.
  (Confirmed: no non-spec assignment of either setting exists anywhere in `lib/`, `etc/`, or `apps/`.)
- Familia defaults both to the same non-empty literal:
  `/home/user/familia/lib/familia/settings.rb:15-16`
  ```ruby
  @encryption_personalization = 'FamilialMatters'.freeze
  @encryption_hkdf_salt       = 'FamilialMatters'.freeze
  ```
- Because the default is **non-empty**, the providers' "fail-closed" guards do NOT trip — the
  weak global salt is used silently:
  - AES-GCM `current_hkdf_salt` only raises on nil/empty: `/home/user/familia/lib/familia/encryption/providers/aes_gcm_provider.rb:113-121`.
  - XChaCha20 `derive_key` only raises on nil/empty: `/home/user/familia/lib/familia/encryption/providers/xchacha20_poly1305_provider.rb:90-101`.
- Familia's own docs flag this exact gap: the default "separates Familia's keys from other
  HKDF users, but NOT one deployment from another"
  (`/home/user/familia/lib/familia/settings.rb:114-117`). The provider comments reference
  issues #310/#311 about removing the global static salt.

### Impact
Reduced HKDF extraction strength / cross-deployment domain separation. Severity is bounded
because the per-field master key is already deployment-unique (derived from `site.secret`,
`/home/user/onetimesecret/lib/onetime/key_derivation.rb:38,66`) and each ciphertext still uses
a fresh random nonce under AEAD, so this is a defense-in-depth weakening, not a direct key
recovery. It does mean all OneTimeSecret installations share the same salt/personalization
constant, removing the per-deployment separation the library intends.

### Remediation
In `configure_familia.rb`, set both to deployment-unique values derived from `site.secret`
(e.g. `Familia.config.encryption_hkdf_salt = KeyDerivation.derive_hex(secret_key, ...)` and a
≤16-byte personalization), and register prior values in `encryption_hkdf_salt_history` so
existing ciphertext keeps decrypting. **Status: CONFIRMED.**

---

## F3 — V1 reveal path has no passphrase rate limiting (MEDIUM)

The passphrase brute-force protection (`PassphraseRateLimiter`,
`/home/user/onetimesecret/lib/onetime/security/passphrase_rate_limiter.rb`, 5 attempts /
10 min → 30 min lockout) is wired only into the **V2** logic
(`reveal_secret.rb:35,68,194`, `show_secret.rb:20,53,69`).

The **V1** `ShowSecret` neither includes the module nor calls the limiter:
`/home/user/onetimesecret/apps/api/v1/logic/secrets/show_secret.rb:26-31` —
`raise_concerns` only checks `viewable?`, and `process` calls `secret.passphrase?(passphrase)`
with no attempt counting or lockout.

### Impact
If the V1 API remains routable, an attacker can brute-force a passphrase-protected secret's
passphrase without lockout (Argon2id cost slows but does not stop offline-style online
guessing; weak passphrases fall quickly). This also undermines the V2 lockout for the same
secret, since V1 attempts are not counted.

### Remediation
Either retire/disable the V1 secrets endpoints, or include
`Onetime::Security::PassphraseRateLimiter` and call `check_passphrase_rate_limit!` /
`record_failed_passphrase_attempt!` in V1 `ShowSecret` exactly as V2 does. **Status: CONFIRMED.**

---

## F4 — Rate-limiter check/record gap + capped Argon2 memory cost (LOW/MEDIUM)

Two sub-issues in the otherwise-good passphrase defenses:

1. **Non-atomic check-then-record.** `check_passphrase_rate_limit!` reads the lockout/attempt
   state, and the failed attempt is recorded separately afterward
   (`reveal_secret.rb:68` then `:194`). The increment+expire+lockout *itself* is atomic Lua
   (`passphrase_rate_limiter.rb:37-56`, `:106-110`) — good — but because the *gate* read and
   the *record* are distinct round-trips with the model load in between, a burst of concurrent
   guesses can all pass the gate before any failure is recorded, yielding more than
   `MAX_ATTEMPTS` (5) live guesses per window. Bounded over-shoot, not an unlimited bypass.
   Evidence: `passphrase_rate_limiter.rb:64-92` (read-only check) vs `:99-117` (record).

2. **Argon2 memory cost is low.** Production cost is `{ t_cost: 2, m_cost: 16, p_cost: 1 }`
   (`/home/user/onetimesecret/lib/onetime/models/features/passphrase_hashing.rb:68-74`).
   `m_cost: 16` is the log2 exponent → 2^16 KiB = **64 MiB**, which is reasonable; `t_cost: 2`
   is on the low side. The bigger note is the test cost `{ t_cost: 1, m_cost: 5, p_cost: 1 }`
   (2^5 = 32 KiB) selected purely by `ENV['RACK_ENV'] == 'test'` — ensure production never runs
   with `RACK_ENV=test`.

### Impact
Slightly-elevated online brute-force throughput against passphrases under concurrency; weak
hashing if the test branch is ever active in production.

### Remediation
Record the attempt (or perform an atomic "consume one token") *before* verifying, or move the
limit decision into the same Lua/transaction as the verification gate. Consider raising
`t_cost`. Add a boot guard that refuses to start with `RACK_ENV=test` in production.
**Status: CONFIRMED.**

---

## F5 — No application-level cap on secret payload size (LOW, DoS)

`ConcealSecret`/`BaseSecretAction` validate TTL, passphrase length, recipient, and domain, but
never bound the size of the secret value itself:
`/home/user/onetimesecret/apps/api/v2/logic/secrets/conceal_secret.rb:21-31` (only rejects
*empty* values); `/home/user/onetimesecret/apps/api/v2/logic/secrets/base_secret_action.rb`
has no value-size check (confirmed: only `passphrase` length and `memo`/`MEMO_MAX_LENGTH` are
bounded). The plaintext is encrypted and stored as a Redis hash field with a TTL.

### Impact
A client can store very large secrets, inflating Redis memory. Mitigated by the per-secret TTL
(secrets expire) and any upstream web-server/Rack body limit (none found in-repo — relies on
the deployment's proxy). Without an app-level cap, memory pressure / cost amplification is
possible, especially for anonymous creation.

### Remediation
Enforce a maximum byte size on the secret value (and ideally tie it to plan limits) in
`BaseSecretAction`/`ConcealSecret`, returning a form error above the limit. **Status: CONFIRMED.**

---

## F6 — Legacy v1 encryption key is unsalted SHA-256 of `site.secret` (LOW, informational)

`/home/user/onetimesecret/lib/onetime/initializers/configure_familia.rb:65`
```ruby
v1_key = Base64.strict_encode64(Digest::SHA256.digest(secret_key))
```
The v1 key version is a single, unsalted SHA-256 of `site.secret`. `current_key_version` is
`:v2` (HKDF-derived), so **new writes use v2**; v1 exists only to decrypt legacy data. This is
acceptable as a read-only migration key, but a plain hash of the root secret is weaker than the
v2 HKDF derivation and should be retired once all v1 ciphertext is re-encrypted/expired.

### Remediation
Plan removal of the v1 key after the v1→v2 data window (the model already carries
`with_migration_fields`/`*_migration_fields` for this). **Status: CONFIRMED.**

---

## Areas reviewed and found sound (with evidence)

### Token / secret identifier generation — STRONG
- `Onetime::Secret`/`Onetime::Receipt` identifiers use
  `Familia::VerifiableIdentifier.generate_verifiable_id`
  (`/home/user/onetimesecret/lib/onetime/models/secret.rb:15-16`,
  `/home/user/onetimesecret/lib/onetime/models/receipt.rb:13-14`).
- That method's random component is `generate_id(16)` →
  `_generate_secure_id(bits: 256, base: 16)` → `SecureRandom.hex(32)` = **256 bits of CSPRNG
  entropy** (`/home/user/familia/lib/familia/verifiable_identifier.rb:91`,
  `/home/user/familia/lib/familia/secure_identifier.rb:35-37,148-150`). Not guessable/enumerable.
- The appended 64-bit HMAC-SHA256 tag is for stateless authenticity/forgery resistance
  (keyed by `VERIFIABLE_ID_HMAC_SECRET`), verified with `OpenSSL.secure_compare`
  (`verifiable_identifier.rb:108-128,161-185`). The HMAC secret has **no committed default** —
  it raises if unset (`:45-54`), preventing forged identifiers.
- `Familia.generate_id` (Secret/Receipt `generate_id` class method,
  `secret_state_management.rb:17`) defaults to 256-bit base-36 as well.

### Encryption at rest — STRONG
- AEAD providers: AES-256-GCM (`aes_gcm_provider.rb:29-31`) and XChaCha20-Poly1305
  (`xchacha20_poly1305_provider.rb:36-38`), selected by priority
  (`Registry.default_provider`).
- **Per-message random nonce from a CSPRNG** every encrypt:
  `OpenSSL::Random.random_bytes(12)` (`aes_gcm_provider.rb:71-73`) and
  `RbNaCl::Random.random_bytes(24)` (`xchacha20_poly1305_provider.rb:75-77`). No nonce reuse:
  a fresh nonce is generated on every `encrypt` call (`manager.rb:17-23`) — no static/counter IV.
- Per-record key derivation via HKDF-SHA256 (AES) / BLAKE2b-keyed (XChaCha20), keyed by a
  per-field context `Class:field:identifier` (`encrypted_field_type.rb:183-185`,
  `manager.rb:130-167`).
- AAD binds ciphertext to record context (`encrypted_field_type.rb:206-220`); v2 envelopes are
  self-describing so adding AAD fields later doesn't break old data (`:144-160`).
- Cross-context misuse is detected on read (`belongs_to_context?`,
  `encrypted_field_type.rb:88-94`).
- Key rotation supported (`key_version`, salt-history decrypt loop `manager.rb:71-87`).
- Caveat: see F2 (salt/personalization left at default).

### Passphrase hashing — STRONG (see F3/F4 caveats)
- Argon2id for new hashes; bcrypt only for legacy verification
  (`passphrase_hashing.rb:33-34,48-62`). Verification uses the libraries' constant-time
  comparators (`Argon2::Password.verify_password`, `BCrypt::Password#==`).

### Lua / command injection — SAFE
- All `eval`/`evalsha` calls pass user data via bound `keys:`/`argv:`, never string
  interpolation: rate limiter (`passphrase_rate_limiter.rb:106-110`), `Counter#incr_if_lt`
  (`/home/user/familia/lib/familia/data_type/types/counter.rb:25`), `Lock#release`
  (`/home/user/familia/lib/familia/data_type/types/lock.rb:28-29`), migration scripts
  (`/home/user/familia/lib/familia/migration/script.rb:140`). Script bodies are static literals.

### Randomness audit — SAFE
- Every security-sensitive random value uses a CSPRNG: `SecureRandom.*`,
  `OpenSSL::Random.random_bytes`, `RbNaCl::Random.random_bytes`. No `Kernel#rand`, `Random.new`,
  `Random.rand`, or `srand` in security contexts across `/home/user/onetimesecret/lib` or
  `/home/user/familia/lib`.
- The deterministic external-identifier derivation deliberately avoids Mersenne-Twister and
  uses SHA-256/HMAC instead, with an explicit comment about the removed MT weakness
  (`/home/user/familia/lib/familia/features/external_identifier.rb:308-333`).

### Redis key naming / enumeration — LOW RISK
- Keys are prefixed (`prefix :secret`, `prefix :receipt`) and keyed by the 256-bit
  unguessable identifier, so direct enumeration via guessing is infeasible.
- The identifier sanitizer enforces a strict allowlist `[^a-zA-Z0-9_-]` before any value is
  used as/within a key, preventing Redis key/glob injection (no `:`, `*`, `?`, whitespace, or
  newlines survive): `/home/user/onetimesecret/lib/onetime/security/input_sanitizers.rb:34,53-55`.
- Note (operational, not a code bug): the rate-limiter keys embed the raw secret identifier
  (`passphrase:attempts:{id}`, `passphrase:locked:{id}`,
  `passphrase_rate_limiter.rb:134-139`); anyone with Redis `KEYS`/`SCAN` access could enumerate
  which secrets are under attack. Restrict direct Redis access in production.

---

## Suggested remediation priority
1. **F1** — make reveal/burn atomic (single-winner consume). Highest priority; it is the
   product's core guarantee.
2. **F3** — rate-limit (or retire) the V1 reveal path.
3. **F2** — set per-deployment `encryption_hkdf_salt` / `encryption_personalization`.
4. **F4 / F5 / F6** — harden rate-limit ordering, cap payload size, retire the v1 key.
