---
id: 008
status: accepted
title: "ADR-008: Secret Management Architecture"
---

## Status
Accepted

## Date
2026-02-18

## Context

The application uses six secret values for distinct cryptographic purposes. Prior to this decision, the relationship between these secrets was ad hoc — some derived from a root key via HKDF, some generated independently, and naming mixed algorithm identifiers (`_HMAC_SECRET`) with purpose identifiers (`SESSION_SECRET`).

Three factors forced a deliberate architecture:

1. **Rotation blast radius.** Rodauth's `hmac_secret` has a sticky rotation problem: TOTP enrollments are HMAC-wrapped with it, and Rodauth intentionally never re-wraps OTP keys. Deriving this from a root key would mean a Familia encryption compromise (requiring root key rotation) forces TOTP re-enrollment as collateral damage.

2. **Federation lifecycle.** The federation secret must be identical across all instances in a federation group. Deriving it from a per-instance root key is incompatible with this requirement.

3. **Naming inconsistency.** Three secrets used the `_HMAC_SECRET` suffix — they all use HMAC, so the suffix adds no distinguishing information. The useful axis for operators is *what the secret protects*, not *which algorithm it uses*.

## Decision

**Naming convention: `{PURPOSE}_SECRET`.** No algorithm names in env var names.

| Env var | Purpose |
|---|---|
| `SECRET` | Root key for HKDF derivation and Familia field encryption |
| `SESSION_SECRET` | Rack session HMAC signing |
| `IDENTIFIER_SECRET` | Authenticity tags on secret/receipt identifiers |
| `AUTH_SECRET` | Rodauth token signing and TOTP key wrapping |
| `ARGON2_SECRET` | Argon2id password hash pepper |
| `FEDERATION_SECRET` | Cross-region email hashing for billing federation |

**Three lifecycle categories.**

*Derived from SECRET* — regenerable, low-impact rotation:
- `SESSION_SECRET`: Sessions are ephemeral; rotation logs users out.
- `IDENTIFIER_SECRET`: Previous values retained briefly to verify outstanding identifiers.

The derived/independent split follows from an asymmetry in rotation capability: Familia's rolling key versioning (v1/v2) makes SECRET rotation for encrypted data a solved problem — old data remains decryptable while new data uses the new key. Rodauth's TOTP has no equivalent; it intentionally never re-wraps OTP keys. Secrets whose downstream systems handle rotation gracefully are derived; secrets whose systems don't are independent.

*Independent per-instance* — generated randomly, must be backed up:
- `AUTH_SECRET`: Decoupled from root key so Familia rotation doesn't cascade into MFA re-enrollment.
- `ARGON2_SECRET`: Password re-hashing is a separate operational concern.

*Shared per-federation-group* — generated once via passforge, distributed to all instances:
- `FEDERATION_SECRET`: `init.rake` validates presence but does not generate it.

`KeyDerivation::PURPOSES` is the single source of truth for HKDF parameters. `init.rake` delegates to it.

## Trade-offs

- **We lose**: Operational simplicity of one root secret. Operators must back up three independent values plus coordinate FEDERATION_SECRET across instances.
- **We gain**: Rotation isolation. Familia's rolling key versioning handles SECRET rotation cleanly; auth and password secrets rotate on their own timelines via Rodauth's `hmac_old_secret` and re-hash-on-login respectively.
- **Risk**: AUTH_SECRET and ARGON2_SECRET cannot be regenerated if lost. This is the explicit trade for rotation isolation.
