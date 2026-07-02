# Encryption at Rest: DPA Compliance Audit & XChaCha20-Poly1305 Upgrade

*Audit date: 2026-07-02. Scope: the DPA clause "Encryption of Secret
Content" vs. the onetimesecret codebase (familia 2.10.1 in production,
2.11.x pending) and the familia encryption library.*

Companion artifacts:

- `examples/encryption_upgrade_proof/` in the familia repo — a four-phase
  executable proof that envelopes written by the released 2.10.1 gem
  (production today) remain decryptable through the gem upgrade and the
  libsodium enablement, and that new writes automatically become
  XChaCha20-Poly1305.
- `try/features/encryption/algorithm_upgrade_try.rb` in the familia repo —
  in-suite regression coverage for the same contract.

## 1. Claim-by-claim verification

| DPA claim | Verdict | Evidence |
|---|---|---|
| "XChaCha20-Poly1305 ... (with AES-256-GCM as an available alternative)" | **Inverted today; true after this branch ships.** Production has no rbnacl, so *every* envelope is AES-256-GCM; XChaCha20 is not merely non-default, it is unavailable. This branch adds `rbnacl` + libsodium, after which new writes are XChaCha20-Poly1305 and AES-256-GCM remains the read-compatible alternative. | `Gemfile` (rbnacl absent pre-branch); familia `registry.rb` (priority 100 vs 50) |
| "Key Derivation: ... BLAKE2b" | **False for all existing data; true only for XChaCha20 envelopes.** The AES-256-GCM path derives with **HKDF-SHA256** (RFC 5869), not BLAKE2b. BLAKE2b keyed derivation applies only to XChaCha20 envelopes, which don't exist yet. Existing AES data keeps HKDF-SHA256-derived keys forever (until re-encrypted). | familia `aes_gcm_provider.rb#derive_key` (HKDF-SHA256); `xchacha20_poly1305_provider.rb#derive_key` (BLAKE2b); proof phase 2 recomputes both independently |
| "(i) a system-level secret not stored alongside encrypted data" | **True.** Master keys derive from `site.secret` (config/ENV): v1 = SHA-256(secret), v2 = HKDF(secret, info='familia-enc'). Keys live in process config, never in Redis/Valkey. | `lib/onetime/initializers/configure_familia.rb:65-72`, `lib/onetime/key_derivation.rb` |
| "(ii) a context string incorporating the object class and unique identifier" | **True.** KDF context is exactly `"Onetime::Secret:ciphertext:<objid>"` (class, field name, identifier — stronger than claimed: the field name is also bound). | familia `encrypted_field_type.rb#build_context` |
| "Nonce: Randomly generated per encryption operation" | **True.** OS CSPRNG per operation (OpenSSL 12-byte for GCM, libsodium 24-byte for XChaCha). Proof: 500 encryptions → 500 distinct nonces. Note GCM's 96-bit random-nonce collision bound is a non-issue here because keys are per-record (each derived key encrypts ~1 value). | providers' `generate_nonce`; proof phase 2 §5 |
| "AAD: The object class and identifier are bound as AAD" | **True with one caveat.** AAD = `"Onetime::Secret:ciphertext:<objid>"`. Bound on every write: `objid` is realized before `ciphertext=` in every creation path. Caveat: an internal comment claiming the *share domain* is also AAD was false (fixed in this branch — see Finding F6). | `encrypted_field_type.rb#build_aad`; `receipt.rb#spawn_pair` |
| "ciphertext cannot be transplanted between records" | **True.** Both the derived key context and the AAD change with the identifier; transplanting fails authenticated decryption. Proof phase 2 §7 demonstrates transplant, tamper, wrong-AAD, wrong-context, and ConcealedString context-isolation failures. | proof phase 2 §7 |
| "Implementation: Familia encrypted-fields library" | **True.** `encrypted_field :ciphertext`; zero direct `Familia::Encryption.encrypt/decrypt` calls in app code. | `lib/onetime/models/secret.rb:43` |
| "The encryption key is not stored and must be reconstructed" | **True.** Data keys are derived per operation and best-effort wiped; only versioned master-key *inputs* exist, in app config. | familia `manager.rb` (derive + `secure_wipe` per op) |
| "The database server does not hold the key material" | **True** for key material. Caveat for the surrounding at-rest narrative: shipped compose runs Valkey with AOF+RDB on a persistent volume, so *envelopes* of already-revealed/expired secrets persist on disk until AOF rewrite (see F12). | `docker/compose/*.yml` |
| "passphrase ... verified as an access-control gate before decryption" | **True.** argon2id (bcrypt legacy) hash in a separate field; `show/reveal` verify before any `decrypted_secret_value` call; rate-limited (5 attempts/600s, 1800s lockout). Passphrase is not a KDF input (Secret uses no `key_material`). Caveat: **burn** is passphrase-gated but *not* rate-limited (F7). | `passphrase_hashing.rb`; `show_secret.rb`; `passphrase_rate_limiter.rb` |

## 2. Why the upgrade is safe (envelope contract)

Every stored value is a self-describing JSON envelope:
`{algorithm, nonce, ciphertext, auth_tag, key_version, encoding,
envelope_version, aad_fields?}`.

- **Write path** picks the highest-priority *available* provider →
  installing rbnacl flips new writes to XChaCha20-Poly1305, zero app changes.
- **Read path** picks the provider from the **envelope's** `algorithm` and
  derives the key with *that provider's* KDF and the envelope's own
  `key_version` → old AES data decrypts forever, regardless of the default.

Proven end-to-end (61 checks, including against the released 2.10.1 gem's
actual bytes) in `examples/encryption_upgrade_proof/`.

## 3. Findings

Severity is for our deployment context, not abstract.

**F1 (high, compliance): the DPA overstates BLAKE2b.** All existing Secret
Content is AES-256-GCM with HKDF-SHA256 derivation. Options: (a) reword the
clause — e.g. "keys are derived from a system-level secret and a
class/identifier context string using BLAKE2b (XChaCha20-Poly1305) or
HKDF-SHA256 (AES-256-GCM)"; (b) rely on Secret TTLs: every Secret expires
(≤30 days cap) or is destroyed on reveal/burn, so within one max-TTL window
after enabling libsodium the claim becomes true for all *Secret Content*
organically. Note (b) does not cover `MailerConfig#api_key` /
`SsoConfig#client_id/client_secret`, which never expire — but those are not
"Secret Content" under this clause. If they're covered elsewhere,
re-encrypt them post-upgrade (`re_encrypt_fields!` + save).

**F2 (high, operational): the upgrade is a one-way door, twice.**
(a) Once any XChaCha20 envelope exists, every reader needs libsodium;
readers without it fail cleanly (`EncryptionError: Unsupported algorithm`)
but fail. (b) Subtler: familia ≥2.11 changes the default AES HKDF salt from
the 2.10.x hardcoded `'FamiliaEncryption'` to `'FamilialMatters'` — 2.11
*decrypts* old data via a fallback list, but AES data *written* by 2.11
under the new default cannot be read by 2.10.x (which has no fallback
loop). Mitigations in this branch: rbnacl + libsodium ship in the same
image as the familia upgrade (no AES-writes-under-new-salt window in
practice), and we pin `encryption_hkdf_salt = 'FamiliaEncryption'`
(Finding F3) so any AES write remains 2.10.x-compatible. Deploy the whole
fleet in one rollout; do not run mixed old/new nodes longer than necessary.

**F3 (high, latent): domain-separation inputs were implicit.** We never set
`encryption_personalization` (XChaCha BLAKE2b) or `encryption_hkdf_salt`
(AES HKDF), inheriting library defaults. The personalization has **no
rotation/history mechanism** — changing it bricks every XChaCha envelope
(proof phase 2 §9). Fixed in this branch: both are now pinned explicitly in
`configure_familia.rb` (`'FamilialMatters'` / `'FamiliaEncryption'`), with
comments marking the personalization as permanent. Improvement filed for
familia: add `encryption_personalization_history` analogous to the salt
history, and/or record a personalization identifier in the envelope.

**F4 (medium, security): envelope-lookalike plaintext is stored verbatim.**
A user-supplied secret whose content is valid envelope JSON (correct five
keys, registered algorithm, correctly-sized base64 nonce/tag, existing
key_version) is treated as already-encrypted by the field setter and
persisted **unencrypted**. Impact: that value (attacker-chosen) sits
plaintext-at-rest, and the recipient gets a decryption error. It violates
the unconditional "Secret Content is encrypted at rest" claim, even though
only the submitter's own content is affected. Fix direction (familia):
distinguish the DB-hydration path from user assignment instead of
duck-typing (e.g. an explicit `from_storage` wrap), or at minimum
authenticate rehydrated envelopes against the record context before
accepting them. Pinned as a documented-hazard check in the proof suite.

**F5 (medium, correctness): legacy v1 `value`/`value_encryption` fields.**
The v0.24.5 migration carried pre-Familia encrypted payloads into plain
deprecated fields with no decryption path in the current codebase, and
familia logs deserialization failures of legacy unquoted strings at ERROR
level *including the full raw value* — so migrated records can spray legacy
ciphertext into application logs on every load. Decide: drop the fields, or
add a migration that re-encrypts them into `ciphertext`, and gate familia's
raw-value error logging (filed upstream, F10).

**F6 (medium, fixed here): stale security-contract comment.**
`Receipt.spawn_pair` documented the share domain as an AAD input; it never
was (`ciphertext_domain` is a transient field nobody reads). The comment
now states the real AAD binding. If domain-binding is actually desired,
note that AAD inputs must be reproducible at decrypt time — the domain
would have to be persisted or derivable; `aad_fields` on v2 envelopes are
self-describing, so adding it later only affects new writes.

**F7 (medium, security): burn is not rate-limited.** `show`/`reveal`
include `PassphraseRateLimiter`; v1/v2 `BurnSecret` do not, so a
passphrase-protected secret's passphrase can be brute-forced through the
burn endpoint (each correct guess destroys the secret; each wrong guess is
a free oracle). Recommend including the same limiter in burn.

**F8 (medium, product): the one-time guarantee is not atomic.** Reveal
does load → check `viewable?` → decrypt → `destroy!` with no WATCH/Lua/lock;
two concurrent requests inside the window can both receive plaintext.
Milliseconds-wide and requires the link (+passphrase), but a "viewable
exactly once" statement in legal/marketing copy should say "best-effort
single view" or the reveal path should take an atomic claim (e.g.
`GETDEL`-style state transition or a Lua guard) before decrypting.

**F9 (low, hardening): `site.secret` entropy is unenforced.** Only
nil/"CHANGEME" are rejected; a weak operator-chosen secret weakens every
derived key (v1 is a bare unsalted SHA-256 of it). Recommend a minimum
length check at boot and documenting 32+ random bytes. (Generated installs
already use `SecureRandom.hex(64)`.)

**F10 (upstream, familia): logging hygiene.** (a) `EncryptedData.valid?`
debug-logs the fully parsed candidate value — i.e. *plaintext being
assigned*, whenever the plaintext parses as a JSON hash — under
`FAMILIA_DEBUG=1`; (b) `deserialize_value` failure logs the complete raw
stored value at ERROR, ungated (see F5). Both should truncate/redact.

**F11 (upstream, familia): envelope `encoding` is unauthenticated.** The
only envelope field whose tampering has a silent effect: decrypt succeeds
and the plaintext gets an attacker-chosen encoding tag (or an invalid name
becomes a per-record decrypt DoS). Requires DB write access (who could
anyway corrupt ciphertext), so low practical impact; still, validate the
name against a known list, and consider binding envelope metadata into the
AAD in a future envelope_version 3. Related nits filed with it:
`encryption_info` calls a nonexistent `current_provider` (dead code);
`encrypted_fields_status` checks a nonexistent `concealed?` predicate and
mis-reports live fields; the `algorithm:` per-field option documented in
`encryption.rb`'s comment is not implemented (and one try file asserts the
ignored behavior).

**F12 (low, deployment): disk persistence of envelopes.** Shipped compose
runs Valkey with `appendonly yes` on a persistent volume, no `requirepass`;
revealed/burned/expired secrets' *envelopes* persist in the AOF until
rewrite. They are ciphertext, so the at-rest claim holds, but volume
backups and `site.secret` must live in separate trust domains (the config
already advises offsite backup of the secret — keep them apart).

**F13 (info): session crypto is a separate, hand-rolled AES-256-GCM**
(HKDF subkeys, HMAC, no AAD) in `lib/onetime/session.rb`, duplicated
inline in `confirm_email_change.rb`. Outside this DPA clause's scope, but
two copies of bespoke crypto is drift risk; consolidate or migrate to
familia encrypted fields eventually.

## 4. Upgrade runbook (this branch)

1. **Ships in this branch**: `rbnacl` gem (top-level — `BUNDLE_WITHOUT`
   excludes `optional`!), `libsodium23` in both runtime image stages,
   explicit `encryption_personalization`/`encryption_hkdf_salt` pins,
   corrected spawn_pair contract comment.
2. **Bare-metal/self-hosted installs** need the libsodium shared library
   (`apt install libsodium23` / `apk add libsodium` / `brew install
   libsodium`). Without it, `require 'rbnacl'` fails to find the library
   and boot fails — which is preferable to silently staying on AES.
3. **Deploy fleet-wide in one rollout** (F2). Verify post-deploy:
   `Familia::Encryption.status[:default_algorithm] == 'xchacha20poly1305'`.
4. **Rollback window**: removing rbnacl/libsodium after deploy makes
   secrets created since the deploy unreadable (clean errors). Rolling the
   familia gem back below 2.11 additionally requires the hkdf_salt pin from
   this branch to have been active for any AES writes (it is).
5. **Long-lived credentials** (`MailerConfig`, `SsoConfig`): optionally
   re-encrypt after the deploy (`re_encrypt_fields!` + save per record) to
   move them to XChaCha20; otherwise they stay AES-256-GCM indefinitely
   (still compliant as the "available alternative").
6. **Secret Content converges by itself**: max TTL is 30 days, so ≤30 days
   after deploy, all live Secret ciphertext is XChaCha20-Poly1305.
