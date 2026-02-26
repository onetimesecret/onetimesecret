# ADR: PASETO Authentication for v3 API

**Status:** Proposed (pending maintainer decisions)
**Issue:** [#2427](https://github.com/onetimesecret/onetimesecret/issues/2427)
**Date:** 2026-02-26

## Context

Issue #2427 proposes replacing Basic Auth with PASETO (Platform-Agnostic
Security Tokens) for the v3 API. This ADR captures analysis findings and
recommendations from a multi-agent codebase review.

## Codebase Readiness

The following infrastructure already exists and supports PASETO integration:

| Capability | Location |
|---|---|
| Pluggable auth strategies (Otto) | `lib/onetime/application/auth_strategies.rb` |
| Timing-attack-safe comparison | `Customer#apitoken?` via `Rack::Utils.secure_compare` |
| HKDF key derivation (RFC 5869) | `lib/onetime/key_derivation.rb` |
| Argon2id password hashing | `argon2 ~> 2.3` in Gemfile |
| Authorization policies + roles | `lib/onetime/application/authorization_policies.rb` |
| Initializer boot system | `lib/onetime/initializers/` (19 initializers) |
| Feature flags | `lib/onetime/auth_config.rb` |
| V3 API (47 routes, logic classes) | `apps/api/v3/` |
| BaseJSONAPI pattern | `apps/api/base_json_api.rb` |

## Issues with the Ticket as Written

### 1. Gem version constraint is wrong

Ticket proposes `ruby-paseto ~> 0.1` — this excludes the current release
v0.2.0 (April 2025), which drops stale OpenSSL 1.x support and fixes UTF-8
handling. Should be `~> 0.2.0`.

### 2. PASETO v3 vs v4 decision is missing

The ticket specifies `v4.public` tokens without justifying v4 over v3:

- **v3.public**: NIST curves (P-384) via OpenSSL — no extra deps
- **v4.public**: Ed25519/BLAKE2b via libsodium — requires `rbnacl` + system lib

The codebase already uses OpenSSL extensively (HKDF, HMAC-SHA256, sessions).
Recommendation: **v3.public** unless v4 is specifically needed.

### 3. V3 API already exists

V3 has 47 routes, logic classes, and registered auth strategies. The ticket
reads as if V3 needs to be created. The actual task is adding `pasetoauth`
to the existing V3 infrastructure.

### 4. Token endpoint route conflicts

Ticket proposes `POST /api/v3/auth/token` but V3 uses flat paths (no `/auth/`
prefix). Options: add to V3 as `POST /token`, or use Account API which
already handles `POST /apitoken`.

### 5. Scope system doesn't exist

Ticket proposes `"scope": ["secrets:read", "secrets:write"]` but the codebase
has no scope granularity — it's all-or-nothing. Recommendation: start with
`["*"]` and expand later.

### 6. Phase 4 is independent work

Hashing stored API tokens with Argon2 is valuable but orthogonal to PASETO.
Should be a separate ticket.

## Dependency Risk Assessment

| Gem | Stars | Downloads | Maintainers | Risk |
|---|---|---|---|---|
| `ruby-paseto ~> 0.2.0` | 19 | 1.43M | 1 | Medium |
| `rbnacl ~> 7.1.1` | 986 | 33M | 46 | Low |

`ruby-paseto` passes all official PASETO test vectors and has zero CVEs, but
has 19 GitHub stars and a single maintainer (bus factor of 1). Mitigations:
pin exact version, vendor the gem, and write integration tests against
official test vectors.

If v3.public is chosen, `rbnacl` is not needed at all.

## Recommended Implementation Order

### Phase 1: Key Infrastructure

- Add `ruby-paseto ~> 0.2.0` to Gemfile
- Create `Onetime::Crypto::PASETO` module for key management
- Add HKDF-derived signing key to `lib/onetime/key_derivation.rb`
- Add initializer: `lib/onetime/initializers/setup_paseto_keys.rb`
- Feature flag: `paseto_enabled: false` in `etc/defaults/auth.defaults.yaml`

### Phase 2: Auth Strategy

- Create `PASETOStrategy` in `lib/onetime/application/auth_strategies.rb`
- Parse `Authorization: Bearer v3.public...` headers
- Verify signature, check `exp` claim, extract `sub` (customer extid)
- Register in V3: `otto.add_auth_strategy('pasetoauth', PASETOStrategy.new)`
- Update V3 routes: `auth=pasetoauth,sessionauth`

### Phase 3: Token Endpoint

- Add `POST /token` to V3 routes (requires `sessionauth`)
- Logic class: `V3::Logic::Auth::GenerateToken`
- Claims: `sub`, `exp` (1hr default), `iat`, `kid`
- Start with `scope: ["*"]`

### Phase 4: Token Hashing (separate ticket)

- Hash existing `apitoken` values with Argon2
- Add `api_key_hash` field to Customer model
- Grace period migration

## Decisions Required

1. **v3.public vs v4.public?** — v3 avoids libsodium; v4 uses non-NIST curves
2. **Token endpoint location?** — V3 API vs Account API
3. **Scope granularity?** — `["*"]` now or define scopes upfront?
4. **Key derivation?** — HKDF from existing `SECRET` or independent keypair?
