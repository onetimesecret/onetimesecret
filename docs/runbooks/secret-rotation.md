# SECRET Backup and Rotation

## Overview

`SECRET` is the root keying material for a Onetime Secret install. Every
working key derives from it via HKDF (RFC 5869) in
`lib/onetime/key_derivation.rb`:

```
SECRET (64 random bytes, operator-provided or generated)
    ├── session        → SESSION_SECRET       (Rack session signing)
    ├── verifiable-id  → IDENTIFIER_SECRET    (secret/receipt link identifiers)
    ├── familia-enc    → [runtime only]       (ciphertext encryption — the payload data)
    └── key-verifier   → [runtime only]       (boot-time SECRET-vs-datastore check)
```

**Treat SECRET like the database itself.** Store a copy in a secret manager
or offline vault the moment it is generated. `bin/setup --init` and
`rake ots:secrets` never overwrite an existing SECRET, but a lost `.env`
plus no backup means the data below is gone.

What is lost if SECRET is lost:

| Derived from SECRET | If SECRET is lost |
|---|---|
| Ciphertexts (secret payloads) | **Unrecoverable, permanently** |
| Sessions | Regenerate — users sign in again |
| Link identifiers | Regenerate — existing links keep resolving (#3630 tracks verification-on-read) |

Independent secrets (`AUTH_SECRET`, `ARGON2_SECRET`, `ACCOUNT_ID_SECRET`,
`FEDERATION_SECRET`) are NOT derived from SECRET and must be backed up
separately — see `.env.reference`.

## How the app protects you (C10 / QS-6)

- **Boot-time verifier.** On every boot the app compares an HKDF-derived
  verifier against the one stored in the datastore
  (`onetime:secret_verifier`). A changed SECRET — or the app pointed at
  another install's datastore — logs a loud `SECRET MISMATCH` error instead
  of booting silently into a state where nothing decrypts. Policy knob:
  `SECRET_VERIFIER_MODE` / `site.secret_verifier_mode` (`warn` default,
  `enforce` refuses to boot, `off` skips).
- **Reveals fail safe.** Under a wrong key, a reveal returns HTTP 503 with
  code `secret_undecryptable` and the reveal claim is rolled back: the
  record and ciphertext survive, and the link becomes revealable again the
  moment the correct key is restored. No secret is consumed by a decrypt
  that cannot succeed.
- **Surfacing.** `/health/advanced` reports a `secret_verifier` sub-check
  (mismatch degrades the top-level status); `bin/setup --doctor` runs
  `rake ots:secrets:verify` (exit codes: 0 ok, 1 mismatch, 2 never adopted,
  3 datastore unreachable).

## Runbook: SECRET changed by accident

Symptoms: `SECRET MISMATCH` in the boot log, degraded `secret_verifier` in
`/health/advanced`, reveals returning 503 `secret_undecryptable`.

1. Restore the previous SECRET in `.env` (from your secret manager backup).
2. Restart the app.
3. Confirm: `bundle exec rake ots:secrets:verify` exits 0.

Nothing was lost: failed reveals rolled back, so every secret that existed
before the accident is still revealable.

## Runbook: intentional rotation

New writes move to the new SECRET; existing ciphertexts keep decrypting via
a decrypt-only chain of previous secrets (`SECRET_PREVIOUS`).

1. **Append** the current SECRET to `SECRET_PREVIOUS` in `.env`
   (comma-separated, oldest first):

   ```
   SECRET_PREVIOUS=<old-secret>            # first rotation
   SECRET_PREVIOUS=<oldest>,<old-secret>   # later rotations: append each time
   ```

2. Install the new value in `SECRET`.
3. Restart the app, then confirm the rotation was intentional:

   ```
   CONFIRM=yes bundle exec rake ots:secrets:adopt
   ```

   and restart running app processes again so they drop the mismatch state.
4. Verify: `bundle exec rake ots:secrets:verify` exits 0, and a reveal of a
   pre-rotation secret still works (the harness lane
   `scripts/test-install/secret-rotation.sh` automates this proof).
5. **Retention:** keep each `SECRET_PREVIOUS` entry for at least the longest
   secret TTL plus the receipt TTL, then drop it.

Mechanics (for the curious): envelopes are tagged with a key version.
Pre-rotation envelopes (`v1`/`v2`) map to the oldest previous secret; each
generation after that writes under a content-addressed tag
(`r<8-hex>`, derived from that secret's verifier), so every entry in the
chain decrypts exactly the envelopes it wrote. See
`Onetime::Initializers::ConfigureFamilia.build_encryption_keys`.

## Rotating without SECRET_PREVIOUS (the cut-line path)

If you rotate without setting `SECRET_PREVIOUS`, ciphertexts written under
the old SECRET become undecryptable — but they are **preserved, not
destroyed**: reveals fail safe with `secret_undecryptable` and the records
age out with their TTLs. Recipients see an honest "the operator must
restore the key" message rather than a burned link. Restore the old value
via `SECRET_PREVIOUS` at any time before expiry and those reveals start
succeeding again.

## Do not

- Regenerate SECRET casually ("it's just an env var" — it is the database).
- Run `rake ots:secrets:adopt` to silence a mismatch you don't understand:
  adopting declares every old ciphertext expendable.
- Re-encrypt in place. There is no re-encryption tooling by design: secrets
  age out in days, and the decrypt-only chain covers the window.
