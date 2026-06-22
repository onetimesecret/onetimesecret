# C6 — Legacy v1 encryption key is unsalted SHA-256 of `site.secret`

- **Severity:** Low (informational) — **CONFIRMED** in source (read-compat only; not used for writes)
- **Status:** Proposed fix (planned retirement, not an urgent patch)
- **Affects default config?** Yes, but only as a *decryption fallback* — all new writes already use
  v2 HKDF
- **Related:** finding 03 F6; C2 (same initializer, the inner-KDF domain separation); the
  v1→v2 migration features on `Onetime::Secret`
- **Primary files:** `lib/onetime/initializers/configure_familia.rb`,
  `lib/onetime/key_derivation.rb`,
  `lib/onetime/models/secret.rb`,
  `lib/onetime/models/secret/features/migration_fields.rb`,
  `familia/lib/familia/encryption/manager.rb`

## Problem (recap)

The v1 encryption key version is a single, **unsalted** SHA-256 of the root secret:

```ruby
# lib/onetime/initializers/configure_familia.rb:65
v1_key = Base64.strict_encode64(Digest::SHA256.digest(secret_key))
```

It is registered alongside the v2 key, and `current_key_version` is `:v2`
(`configure_familia.rb:68-72`), so **new writes use v2** (HKDF-derived,
`key_derivation.rb:38,52,66`). The v1 entry exists only so that data written before the HKDF scheme
can still be decrypted — Familia selects the key by the `key_version` recorded in each ciphertext
envelope (`manager.rb:30,137,176`).

This is acceptable as a read-only migration key, but a plain unsalted hash of the root secret is a
weaker derivation than v2's HKDF (no salt, no `info` domain separation, single hash invocation), and
it keeps a second copy of a root-secret-derived key in the configured keyset indefinitely.

## Root cause

The v1 key is a compatibility shim retained from before the HKDF migration. Nothing forces it to be
removed once the data it decrypts is gone, so it lingers. The model already carries the machinery to
know when it is safe to drop — it just is not being acted on.

## Why it is low risk today

- v1 is **never used to encrypt** — `current_key_version = :v2` (`configure_familia.rb:72`), and the
  manager encrypts with `current_key_version` (`manager.rb:30,186-188`).
- A v1 ciphertext only decrypts under the v1 key when its own envelope says `key_version: v1`; an
  attacker cannot downgrade a v2 ciphertext to v1, because the version is read from the
  (authenticated) stored envelope, not chosen at decrypt time.
- The weakness is the *derivation quality* of a key that protects only already-existing legacy data,
  whose confidentiality still rests on `site.secret` staying secret.

So this is informational hygiene: retire the weaker key once it has no data to read, shrinking the
attack surface and the key inventory.

## Prescribed resolution

Plan and execute the removal of the v1 key after the v1→v2 re-encryption / expiry window. The model
already has the features to drive and verify this.

### Implementation steps

1. **Inventory remaining v1 ciphertext.** Use the migration feature already on `Onetime::Secret`:
   `Secret.encryption_stats` returns `{ version => count }` by reading each secret's
   `value_encryption` field (`migration_fields.rb:48-59`), and `encryption_version` maps `'1' → :v1`
   (`:146-154`). Run it to confirm how many `:v1` secrets remain.

   **Confirm first:** the v1 key decrypts *value* ciphertext written under the old scheme. Verify
   that `value_encryption` reliably reflects the envelope `key_version` for the data in your store
   (the migration notes at `migration_fields.rb:10-15` say v1→v2 **preserves** encryption rather than
   re-encrypting, so old records keep `value_encryption: 1`). The count must reach zero through
   **expiry** (secrets are TTL-bounded — default 7 days, max 30, `base_secret_action.rb:113,127`) or
   an explicit re-encryption pass, before the key can be dropped.

2. **Wait out the window (preferred) or re-encrypt.** Because secrets expire within ≤30 days, the
   simplest path is time: once no secret predates the v2 cutover by more than the max TTL, no `:v1`
   ciphertext can exist. If you cannot wait, add a one-off re-encryption task that loads each `:v1`
   secret, decrypts under v1, and re-saves (which re-encrypts under v2 via the normal write path).
   Either way, re-run `encryption_stats` and require `stats['1'] == 0` (and no `:v1` in any retained
   record) as the gate.

3. **Remove the v1 key from the keyset.** Once the inventory is zero, delete the v1 derivation and
   registration in `configure_familia.rb`:

   ```ruby
   # delete:
   v1_key = Base64.strict_encode64(Digest::SHA256.digest(secret_key))
   # and change:
   Familia.config.encryption_keys = { v1: v1_key, v2: v2_key }
   # to:
   Familia.config.encryption_keys = { v2: v2_key }
   ```

   After removal, any stray `:v1` ciphertext fails closed: `Manager#get_master_key` raises
   `"No key for version: v1"` (`manager.rb:176-177`) rather than silently mis-decrypting — which is
   the correct, loud failure mode if step 1's inventory was wrong.

4. **Retire the migration features when fully done.** Once v1 is gone and the owner-id migration is
   complete, the `with_migration_fields` / `secret_migration_fields` features
   (`secret.rb:29-30`, `migration_fields.rb`) can also be dropped per their own removal note
   (`migration_fields.rb:17`). This is a follow-on cleanup, not required for key removal.

### Sequencing with C2

C2 changes the *inner* KDF salt/personalization for the **current** (v2) provider path and does not
touch the v1 master key, so the two are independent. Do C2 first (it improves the live path); do C6
on its own schedule once the data window closes. Removing the v1 key has no effect on C2's
salt-history (that is a v2/AES-GCM decrypt concern).

### Alternatives considered

- **Strengthen the v1 derivation in place.** Rejected: v1 must continue to decrypt *existing* v1
  ciphertext, so its derivation cannot change without breaking that data. The only safe improvement
  is removal after the data is gone.
- **Leave it forever.** Rejected on hygiene grounds — it keeps a weaker root-secret-derived key in
  the configured set with no remaining purpose, exactly the kind of latent surface the assessment
  flags.

## Test / verification

- **Inventory gate:** assert `Secret.encryption_stats['1'] == 0` (and no retained `:v1` record)
  before allowing the key removal change to merge — encode this as a guard in the migration/runbook.
- **Post-removal fail-closed:** with the v1 key removed, attempt to decrypt a synthetic `:v1`-tagged
  ciphertext → assert `EncryptionError "No key for version: v1"` (`manager.rb:177`), never a silent
  wrong-plaintext.
- **v2 unaffected:** full encrypt/decrypt round-trip on a new secret after removal still works
  (only `:v2` in the keyset).
- **Regression:** existing reveal specs pass unchanged after removal (no v1 data left to read).

## Effort & risk

- **Effort:** Low code (a few lines in the initializer) but gated on an **operational** window —
  most of the work is confirming the inventory is empty and waiting out / running the migration.
- **Risk:** Low if the inventory gate is honoured; **data-loss if removed prematurely** (any
  surviving `:v1` ciphertext becomes permanently undecryptable). The fail-closed behaviour makes a
  mistake loud rather than silent, but the gate in step 1 is mandatory.
- **Priority:** Lowest of the batch — informational hygiene, do after C2/C3/C4/C5 and only when the
  data window has closed.
