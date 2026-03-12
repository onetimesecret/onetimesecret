# docs/architecture/encryption.md
---

# Encryption Architecture

## The Claim vs. Reality

The current marketing copy states: "The decryption key is embedded in the URL fragment, never sent to our servers, never logged. We can't read your data even if compelled."

This is inaccurate on every count. There is no client-side encryption, no URL fragment key, and the server can decrypt any secret it holds.

## How It Actually Works

Encryption at rest is the correct characterization. Secrets are encrypted server-side before being stored in Redis, and decrypted server-side when a recipient requests them. The plaintext travels over HTTPS in both directions — to the server during creation, and back to the recipient during reveal.

**Algorithm:** New secrets use XChaCha20-Poly1305 (authenticated encryption with a 24-byte nonce), provided by the Familia ORM's `encrypted_fields` feature via the `rbnacl` gem. A legacy path uses AES-256-GCM as fallback. Both are AEAD ciphers with built-in tamper detection.

**Key hierarchy:**

```
site.secret (operator-provided, 64+ random bytes, in config)
  └─ HKDF-SHA256(info='familia-enc') → master_key_v2
       └─ BLAKE2b(master_key, context) → per-secret-field key
```

Each secret gets a unique derived key based on the context string `"Onetime::Secret:ciphertext:<identifier>"`, where `<identifier>` is the secret's verifiable ID (a base-36 string with 256 bits of randomness + HMAC tag). No two secrets share the same encryption key, though all keys trace back to the same master.

The ciphertext is stored in Redis as a JSON envelope containing the algorithm identifier, a random nonce, the encrypted payload, an authentication tag, and the key version — all Base64-encoded.

> **Note**: The decryption key is not stored on the database server. The key hierarchy derives from `site.secret` in the application config, which lives on the application server. Redis (the database) holds only ciphertext.

## URL Structure

The URL is simply `https://onetimesecret.com/secret/<identifier>` — no fragment (`#`). The identifier is the Redis lookup key. When the recipient visits this URL, the server loads the record, re-derives the per-secret key from the master key + context, decrypts, returns the plaintext over HTTPS, and then destroys the Redis record.

## Passphrase Behavior

In the current v2 system, the passphrase is access control only — a gate checked via Argon2id hash verification before the server agrees to decrypt. It does not contribute to the encryption key. The server could decrypt any secret without the passphrase if it chose to. (In the legacy v1 path, the passphrase was mixed into key derivation via SHA-256, making it cryptographically necessary for decryption.)

## Additional Features

- Authenticated encryption (XChaCha20-Poly1305) prevents tampering
- Per-secret key derivation prevents cross-record attacks
- Context-bound AAD prevents moving ciphertext between records
- HKDF key derivation follows RFC 5869
- Automatic destruction after viewing (one-time read)
- Passphrase hashing uses Argon2id
- Key versioning supports rotation (v1 → v2)
