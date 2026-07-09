---
labels: email-quality, phase-3, backend
depends: 10-headers-and-classification, 11-keys-hashing-tokens
epic: TBD
---

# Email quality: per-address / per-domain / per-sender outbound limits

## Context

Part of the **Email Quality Controls** epic, Phase 3. Independent of Phase 2 —
can proceed in parallel. Today the only outbound throttles are Rodauth's
30-second magic-link resend skip and org-invitation `MAX_RESENDS = 3`; a single
account can fire unlimited secret links at one address (the harassment vector),
and an anonymous visitor can flood an incoming-secrets recipient. This slice
adds `Onetime::Security::EmailRateLimiter` in the exact mold of the four
existing Security limiters, registered in the ratelimit Registry so colonel
inspect/reset and `bin/ots ratelimit` light up with zero new adapter code.
Supersedes the v0.23 `limit_action :email_recipient` intent (grounding
correction 6).

## Scope

- `Onetime::Security::EmailRateLimiter` (`lib/onetime/security/
  email_rate_limiter.rb`): layer-agnostic module, Lua atomic
  check-and-increment (the `DnsRateLimiter` single-script shape — sends have no
  separate failure event), raising `Onetime::LimitExceeded` (→ 429 via the Otto
  hook), `*_status` read-only helpers, `force_enabled` test bypass. Four
  subjects, keys under one recognizable prefix:
  - **recipient address** — `email:limit:addr:%s` (subject =
    `EmailProtection.address_hash`): `MAX_PER_ADDRESS_HOURLY = 10`,
    `MAX_PER_ADDRESS_DAILY = 30` (across ALL senders — the anti-harassment
    limit).
  - **recipient domain** — `email:limit:rdom:%s` (subject = hashed registrable
    domain): `MAX_PER_RDOMAIN_HOURLY = 200`, protecting a target org's MX and
    our standing with it. ⚠️ Exempt a small allowlist of mega-providers
    (gmail.com, outlook.com, yahoo.com, …) where a shared-domain limit would
    only create collateral damage — frozen constant, documented.
  - **sender account** — `email:limit:cust:%s` (subject = customer objid):
    `MAX_PER_SENDER_DAILY = 100` recipient-emails/day (categories
    `transactional_recipient` only — account/security mail never counts).
  - **tenant domain** — `email:limit:brand:%s` (subject = `domain_id`, already
    on every payload): daily cap for custom-domain-branded sends, isolating a
    noisy tenant's blast radius.
- **Enforcement points**:
  - Interactive pre-checks in `raise_concerns` of the three third-party flows —
    v1/v2 `BaseSecretAction#validate_recipient` (secret_link),
    `Incoming::Logic::CreateIncomingSecret` (plus a per-IP submission limiter
    here — the disabled tryout's other half), org
    `CreateInvitation`/`ResendInvitation` — so users get proper 429s with
    `retry_after`.
  - Authoritative check-and-increment in `Publisher#enqueue_email` (and the
    fallback direct-path), scoped by category: `transactional_recipient` counts
    against all four subjects; `notification` counts address-only;
    `transactional_account`/`system` are EXEMPT (limits must never block
    password resets; abusable account-mail loops get their own narrow counters
    below).
  - Close the unbounded verification-resend loop: per-address counter on
    `Logic::Base#send_verification_email` / CreateAccount's silent resend and
    on `ResetPasswordRequest` (e.g. 5/day/address) — these bypass the
    category exemption deliberately, with generous ceilings.
- Register all kinds in `Operations::RateLimit::Registry::LIMITERS` (one row
  each: subject description, key templates, lazy dbclient proc) — colonel
  `GET /ratelimit/limiters|inspect` + `POST /ratelimit/reset` and
  `bin/ots ratelimit keys` inherit them for free.
- Suppression-adjacent behavior: a `LimitExceeded` on the enqueue path for
  QUEUED mail (e.g. DispatchNotification re-publishing) is rescued and dropped
  with an `EmailActivity` `rate_limited` event — never DLQ'd (the
  `DomainValidationWorker` rescue precedent).

## Grounding — files & pointers

- Limiter templates: `lib/onetime/security/{feedback,dns,invite_token,passphrase}_rate_limiter.rb` (+ `lib/onetime/security/README.md` — layer-agnostic contract); evalsha/NOSCRIPT caching in invite_token
- Registry: `lib/onetime/operations/ratelimit/registry.rb` (`LIMITERS`, lazy dbclient, golden-master key templates)
- Error currency + HTTP mapping: `Onetime::LimitExceeded` in `lib/onetime/errors.rb`; 429 handler in `lib/onetime/application/otto_hooks.rb`
- Call sites to guard: `apps/api/v2/logic/secrets/base_secret_action.rb` (`validate_recipient`, `send_email_to_recipient`; v1 twin), `apps/api/incoming/logic/create_incoming_secret.rb`, `apps/api/organizations/logic/invitations/{create_invitation,resend_invitation}.rb`, `lib/onetime/logic/base.rb` (`send_verification_email`), `apps/api/account/logic/authentication/reset_password_request.rb`
- Enqueue funnel: `lib/onetime/jobs/publisher.rb`
- Per-customer email-change limiter precedent (MULTI incr+expire, 5/24h): `apps/api/account/logic/account/request_email_change.rb`
- Old intent being superseded: `try/disabled/features/incoming/06_rate_limiting_try_disabled.rb`, `src/schemas/contracts/config/section/limits.ts`
- Domain parsing: `lib/onetime/utils/domain_parser.rb`

## Acceptance criteria

- [ ] Constants-only thresholds (Q5) with `force_enabled` test bypass; all
      kinds registered in the Registry; `bin/ots ratelimit` and colonel
      inspect/reset work on them unchanged.
- [ ] 11th secret-link to one address inside an hour → 429 with `retry_after`;
      the sender-side error does NOT reveal per-address counters state beyond
      the retry hint (no oracle for "someone else also emails this address").
- [ ] Password reset and verification mail deliver even when the recipient
      address is at its transactional_recipient limit; the dedicated
      verification-resend counter caps the CreateAccount silent-resend loop.
- [ ] Mega-provider recipient domains are exempt from the domain limiter but
      still subject to the address limiter.
- [ ] Queued-path limit hits ack + log `rate_limited` activity; DLQ depth
      unaffected.
- [ ] Anonymous incoming-secret submissions rate-limited per IP AND per
      recipient hash; the disabled tryout's scenarios re-enabled/adapted as
      real tryouts.
- [ ] Golden-master tryout keys byte-match the Registry (`keys_for`) —
      sibling file to `try/unit/operations/email_ratelimit_tools_try.rb`.

## Notes / risks

- Fixed windows (house style) allow 2× burst at window edges — acceptable for
  abuse ceilings; do not invent sliding windows here.
- Counter keys use hashes, so `ratelimit inspect` subjects are hashes — the
  colonel suppression screen's check-an-address form (slice 22) is the
  operator's translation path; note it in the inspect panel copy.
- Ceilings are deliberately generous first (observe via slice 60, then
  tighten); shipping too-tight limits on legitimate flows is the bigger risk.
- Per-plan quota entitlements remain out of scope (epic non-goal); revisit once
  billing catalog work picks up `secrets_per_day`.
