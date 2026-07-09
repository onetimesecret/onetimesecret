---
labels: email-quality, phase-0, backend, security
depends: none
epic: TBD
---

# Email quality: protection keys, address hashing, stateless token format

## Context

Part of the **Email Quality Controls** epic, Phase 0.

Suppression entries, event logs, and per-address rate-limit keys must never
store plaintext addresses (house norm: plaintext only in transient queue
payloads; `OT::Utils.obscure_email` in logs and stored fields; HMAC hashes as
persistent lookup keys). The existing `Onetime::Utils::EmailHash` is the right
shape but hard-raises without the OPTIONAL `FEDERATION_SECRET` — a suppression
list keyed on it would break every non-federated install (decision Q1). This
slice creates the key material, the hashing helper, and the signed-token
encoder/verifier that slices 20, 40, 50, and 51 consume.

## Scope

- Add an `email_protection:` entry to `Onetime::KeyDerivation::PURPOSES`
  (HKDF from root `SECRET`, distinct `info` string, `env_var:
  'EMAIL_PROTECTION_SECRET'` override) per ADR-008 Category 1. Update
  `.env.example`'s DERIVED block and `lib/tasks/init.rake` env generation.
- New `Onetime::Utils::EmailProtection` (module, `extend self`):
  - `address_hash(email)` — HMAC-SHA256 over `OT::Utils.normalize_email`
    output, truncated to 32 hex chars (mirror `EmailHash::HASH_LENGTH`), keyed
    by the derived secret. Returns nil for blank input; never raises for a
    missing root SECRET at require time (lazy derivation, boot-safe).
  - `domain_hash(email)` — same HMAC over the registrable domain
    (`Onetime::Utils::DomainParser`) for per-domain keys. Recipient domains are
    lower-sensitivity than addresses but hashing keeps Redis keyspace dumps
    clean.
  - `same_hash?` — constant-time compare (`OpenSSL.secure_compare`).
- Stateless token codec `Onetime::Utils::EmailProtection::Token`:
  - `encode(purpose:, category:, email_hash:, issued_at:, expires_at: nil)` →
    base64url(version byte ‖ purpose ‖ category ‖ timestamps ‖ email_hash ‖
    HMAC tag). Version byte enables rotation; `purpose` separates unsubscribe
    vs opt-back-in-confirm tokens cryptographically.
  - `decode(token)` → verified struct or nil (constant-time tag check; expiry
    honored only when present — unsubscribe tokens are non-expiring, confirm
    tokens carry 24h expiry).
- A boot initializer records readiness on `Onetime::Runtime`
  (extend `Runtime::Email` Data.define with e.g. `protection_configured:`),
  following `ConfigureTruemail`'s pattern.

## Grounding — files & pointers

- Key derivation: `lib/onetime/key_derivation.rb` (frozen `PURPOSES`, `derive`/`derive_hex`; SALT `'onetimesecret-v1'`)
- ADR: `docs/architecture/decision-records/adr-008-secret-management-architecture.md` (`{PURPOSE}_SECRET` naming, derived-vs-independent categories)
- Hash precedent (shape + normalization contract): `lib/onetime/utils/email_hash.rb` — note its private `normalize_email` copy must stay in sync with `OT::Utils.normalize_email` (`lib/onetime/utils/strings.rb`); the new helper should call `OT::Utils.normalize_email` directly
- Domain parsing: `lib/onetime/utils/domain_parser.rb`
- Constant-time compare precedent: `EmailHash.same_hash?`; session HMAC in `lib/onetime/session.rb`
- Runtime state precedent: `lib/onetime/runtime/email.rb` + `lib/onetime/initializers/configure_truemail.rb`
- Signed-token precedent (closest existing): Rodauth `account_id_obfuscation_secret_env_key 'ACCOUNT_ID_SECRET'` in `apps/web/auth/config/base.rb` — version-tagged signed tokens in email links

## Acceptance criteria

- [ ] `EmailProtection.address_hash` is deterministic across processes,
      normalization-identical to `OT::Utils.normalize_email`, and returns the
      same hash for `User@Example.COM ` and `user@example.com`.
- [ ] Works on an install with ONLY root `SECRET` set (no FEDERATION_SECRET, no
      EMAIL_PROTECTION_SECRET); env override takes precedence when present.
- [ ] Token round-trip: encode → decode verifies; a flipped bit anywhere fails;
      an expired confirm token fails; an unsubscribe token with no expiry
      decodes years later; tokens for one purpose never validate as another.
- [ ] Rotating `EMAIL_PROTECTION_SECRET` invalidates old tokens AND orphans old
      hash keys — documented loudly (suppression entries would need re-keying;
      this is why the derived-from-root default is preferred).
- [ ] RSpec unit coverage for codec edge cases (truncation, wrong version,
      empty input); tryout for the happy path.

## Notes / risks

- One secret purpose, multiple uses (hash key + token MACs) is acceptable
  because the token payload includes a purpose discriminator; if reviewers
  prefer full separation, register two PURPOSES entries — decide in PR, the
  codec API doesn't change.
- Never log tokens or full hashes; `AdminAuditEvent`'s `SENSITIVE_KEY_PATTERN`
  already redacts `token`-named detail keys — keep that naming so redaction
  applies.
- Keep the module dependency-light (no Familia/models at require time) so
  delay-boot CLI commands can require it — same constraint the ratelimit
  Registry documents.
