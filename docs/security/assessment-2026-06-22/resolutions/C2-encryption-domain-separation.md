# C2 — Encryption HKDF salt & BLAKE2b personalization left at the shared library default

- **Severity:** Medium — **CONFIRMED** in source (defense-in-depth weakening, not direct key recovery)
- **Status:** Proposed fix
- **Affects default config?** **Yes** — every OneTimeSecret deployment that does not set these knobs
  (i.e. all of them) shares the same `'FamilialMatters'` salt/personalization
- **Related:** finding 03 F2; Familia issues #310 (per-deployment HKDF salt) / #311 (separate AES vs
  XChaCha20 inputs); C6 (v1 key retirement) touches the same initializer
- **Primary files:** `lib/onetime/initializers/configure_familia.rb`,
  `lib/onetime/key_derivation.rb`, `familia/lib/familia/settings.rb`,
  `familia/lib/familia/encryption/providers/{aes_gcm_provider,xchacha20_poly1305_provider}.rb`,
  `familia/lib/familia/encryption/manager.rb`

## Problem (recap)

Encrypted fields (`Secret#ciphertext`) are protected with a master key that **is** correctly
per-deployment — it is HKDF-derived from `site.secret`
(`lib/onetime/key_derivation.rb:38,52`, used at `configure_familia.rb:66`). But each provider's
**inner** key-derivation step takes a *second* domain-separation input that the application never
sets, so it silently falls back to Familia's hardcoded global literal:

```ruby
# familia/lib/familia/settings.rb:15-16
@encryption_personalization = 'FamilialMatters'.freeze   # BLAKE2b `personal` (XChaCha20 provider)
@encryption_hkdf_salt       = 'FamilialMatters'.freeze   # HKDF salt        (AES-GCM provider)
```

The app's Familia configuration sets only `encryption_keys` and `current_key_version`
(`configure_familia.rb:68-72`); it never assigns `encryption_hkdf_salt` or
`encryption_personalization` (confirmed: no non-spec assignment of either exists in `lib/`, `etc/`,
or `apps/`). Because the default is **non-empty**, the providers' fail-closed guards do not trip:

- AES-GCM `current_hkdf_salt` raises only on nil/empty
  (`familia/.../aes_gcm_provider.rb:113-121`).
- XChaCha20 `derive_key` raises only on nil/empty
  (`familia/.../xchacha20_poly1305_provider.rb:90-101`).

So the weak global salt is used silently. Familia's own settings doc names this exact gap: the
default "separates Familia's keys from other HKDF users, but NOT one deployment from another"
(`familia/.../settings.rb:114-117`).

## Root cause

Domain separation for the providers' inner KDF is **opt-in** in Familia (it ships a deliberately
permissive shared default so the library "just works"), and the OneTimeSecret initializer never
opts in. The result is that the per-record key derivation
(`Class:field:identifier` context, `manager.rb:130-167`) is salted/personalized with a constant
that is identical across every OneTimeSecret installation in the world.

## Bounded impact (read this before prioritising)

This is **defense-in-depth weakening, not a break**:

- The master key is already deployment-unique (HKDF of `site.secret`,
  `key_derivation.rb:38,52,66`), so an attacker cannot derive another deployment's keys from the
  shared salt.
- Every ciphertext still uses a fresh CSPRNG nonce under AEAD (`aes_gcm_provider.rb:71-73`,
  `xchacha20_poly1305_provider.rb:75-77`), so there is no nonce reuse.
- What is lost is the per-deployment separation RFC 5869 salt / BLAKE2b personalization is *meant*
  to provide: cross-deployment HKDF extraction strength and a clean cryptographic boundary between
  installations. It is the correct kind of thing to fix on a "get it right" basis, but it is not an
  emergency.

## Prescribed resolution

Set both knobs to **deployment-unique** values derived from `site.secret`, and register the old
value(s) in salt-history so existing ciphertext keeps decrypting. Familia already supports exactly
this rotation pattern (see "Back-compat" below).

### Implementation steps

1. **Add two derivation purposes** to `Onetime::KeyDerivation::PURPOSES`
   (`lib/onetime/key_derivation.rb:35-39`). These are runtime-only (no `:env_var`), like
   `familia_enc`. Distinct `info` strings guarantee they are cryptographically independent of the
   master key and of each other:

   ```ruby
   PURPOSES = {
     session:     { info: 'session',       length: 64, env_var: 'SESSION_SECRET' },
     identifier:  { info: 'verifiable-id', length: 32, env_var: 'IDENTIFIER_SECRET' },
     familia_enc: { info: 'familia-enc',   length: 32 },
     # New — domain-separation inputs for Familia's providers (runtime only):
     familia_enc_salt: { info: 'familia-enc-salt', length: 32 }, # AES-GCM HKDF salt (any length)
     familia_enc_pers: { info: 'familia-enc-pers', length: 16 }, # BLAKE2b personalization (<=16 bytes)
   }.freeze
   ```

   `length: 16` for the personalization is deliberate: BLAKE2b caps `personal` at 16 bytes and
   Familia's setter raises above that (`settings.rb:95-105`).

2. **Assign both in the initializer**, right after the key block
   (`configure_familia.rb:68-72`). Use hex for the salt (printable, any length is fine for HKDF)
   and the raw 16 bytes for personalization (BLAKE2b wants bytes, null-padded to 16 by the provider
   at `xchacha20_poly1305_provider.rb:101`):

   ```ruby
   Familia.config.encryption_keys     = { v1: v1_key, v2: v2_key }
   Familia.config.current_key_version = :v2

   # Per-deployment domain separation for the providers' inner KDF (finding C2 / #310, #311).
   # Derived from site.secret so each deployment is distinct; independent `info` strings keep
   # these cryptographically separate from the master key and from each other.
   Familia.config.encryption_hkdf_salt =
     Onetime::KeyDerivation.derive_hex(secret_key, :familia_enc_salt)        # AES-GCM
   Familia.config.encryption_personalization =
     Onetime::KeyDerivation.derive(secret_key, :familia_enc_pers)            # XChaCha20 (16 raw bytes)

   # Back-compat: data written before this change was salted/personalized with Familia's
   # global literal. Keep it decryptable. (See "Back-compat" notes below for personalization.)
   Familia.config.encryption_hkdf_salt_history = ['FamilialMatters']
   ```

   Note: `derive` returns raw bytes; confirm the personalization value contains no NUL byte before
   use — the provider rejects embedded NULs (`xchacha20_poly1305_provider.rb:99`). A 16-byte HKDF
   output can legitimately contain a `0x00`. To stay safe, prefer a NUL-free encoding that still
   fits 16 bytes, e.g. the first 16 chars of the hex digest:

   ```ruby
   Familia.config.encryption_personalization =
     Onetime::KeyDerivation.derive_hex(secret_key, :familia_enc_pers)[0, 16]  # 16 hex chars, NUL-free
   ```

   This is the recommended form — it is deterministic, deployment-unique, exactly 16 bytes, and
   cannot trip the NUL guard.

3. **Do not change `current_key_version` or the master keys.** This change only affects the
   *inner* KDF salt/personalization, not the master key or envelope version, so it composes cleanly
   with C6.

### Back-compat: keeping old ciphertext readable

The decrypt path is already rotation-aware on the **AES-GCM** side:

- `Manager#decrypt` iterates `provider.hkdf_salts` (current → history → pre-#310 legacy), trying
  each until the authenticated decrypt succeeds; a wrong salt fails GCM cleanly with no false
  positive (`familia/.../manager.rb:71-87`).
- `AESGCMProvider#hkdf_salts` is `[current, *history, LEGACY_HKDF_SALT].compact.uniq`
  (`aes_gcm_provider.rb:97-101`). Putting `'FamilialMatters'` in `encryption_hkdf_salt_history`
  makes pre-fix AES-GCM ciphertext decrypt on the first or second attempt.

The **XChaCha20/BLAKE2b** side has **no** personalization-history mechanism: `derive_key` reads a
single `Familia.config.encryption_personalization` (`xchacha20_poly1305_provider.rb:90-101`) and
`hkdf_salts` is AES-GCM-only. **Confirm first which provider your deployment actually uses for
writes.** XChaCha20 has priority 100 vs AES-GCM's 50 (`xchacha20_poly1305_provider.rb:44`,
`aes_gcm_provider.rb:37`), so if `rbnacl` is installed, XChaCha20 is the default writer and changing
`encryption_personalization` **will make previously-written XChaCha20 ciphertext undecryptable**.

Two safe options, in order of preference:

- **Option 1 (recommended): change personalization only on the next master-key rotation.** Because
  secrets are short-lived (TTL-bounded; default 7 days, max 30 days — `base_secret_action.rb:127`),
  the simplest correct path is: deploy the new personalization **prefixed by a grace window**. If
  you can tolerate a ≤30-day window where you keep the *old* personalization, set the new value only
  after the longest possible secret has expired. During the window, set the AES salt (which is
  history-safe) but leave personalization at the default; after the window, flip personalization too.
- **Option 2 (no waiting, requires a Familia change): add personalization-history to XChaCha20.**
  Mirror `hkdf_salts`/`encryption_hkdf_salt_history` with an `encryption_personalization_history`
  that the manager's decrypt loop also iterates. This is the principled long-term fix and is the
  natural sibling of #310/#311; it belongs upstream in Familia. Treat it as a prerequisite PR if you
  cannot accept the grace window.

Given the short secret lifetimes, **Option 1 is the pragmatic, zero-data-loss choice**; ship Option
2 upstream if instant rotation without a window is a requirement.

### Alternatives considered

- **Leave it at the default.** Rejected: it removes the per-deployment separation the library
  intends and is trivial to fix. The maintainer asked to get it right.
- **Use `site.secret` directly as the salt.** Rejected: reusing the root secret as a salt muddies
  the key hierarchy; a dedicated HKDF purpose with a distinct `info` is cleaner and matches the
  existing `familia_enc` pattern.
- **Random per-deployment salt persisted to Redis/config.** Rejected: deriving from `site.secret`
  is reproducible across restarts and workers with no new state to manage or back up.

## Test / verification

- **Unit (app):** after boot, assert `Familia.config.encryption_hkdf_salt` and
  `encryption_personalization` are non-empty, deployment-derived, and **not** `'FamilialMatters'`;
  assert personalization is ≤16 bytes and NUL-free.
- **Determinism:** two boots with the same `site.secret` produce identical salt/personalization;
  two different `site.secret` values produce different ones.
- **Round-trip:** encrypt a `Secret#ciphertext` with the new config, decrypt it back (both
  providers if `rbnacl` is present).
- **Back-compat (AES-GCM):** write a ciphertext under `'FamilialMatters'`, then set the new salt +
  `encryption_hkdf_salt_history = ['FamilialMatters']`, and confirm it still decrypts (exercises the
  `manager.rb:71-87` loop). A unit test asserting `hkdf_salts` includes the history entry guards the
  wiring.
- **Back-compat (XChaCha20):** if Option 2 is taken, add the equivalent personalization-history
  decrypt test upstream in Familia. If Option 1 is taken, document the grace window in the runbook;
  no code test applies.

## Effort & risk

- **Effort:** Low for the AES-GCM-only / Option-1 path (two `derive_*` calls + two purposes +
  history entry). Medium if Option 2 (Familia personalization-history) is required.
- **Risk:** **Data-loss risk is the whole game here.** The salt change is safe due to existing
  history support; the personalization change is **not** safe for XChaCha20 without either the grace
  window (Option 1) or upstream history support (Option 2). Confirm the active write provider before
  shipping. The master key and envelope are untouched, so there is no interaction with key rotation
  or C6.
- **Priority:** Medium — after C1 (atomicity) and C3 (V1 rate limit). Worth doing carefully rather
  than quickly.
