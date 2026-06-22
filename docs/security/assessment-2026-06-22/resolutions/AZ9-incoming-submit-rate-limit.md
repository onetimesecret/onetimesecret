# AZ9 — No in-logic rate limit on anonymous incoming /secret and /validate (mail-flood / Redis-flood abuse)

- **Severity:** Low–Medium — **NEEDS-VALIDATION** (Medium absent any upstream limiter; Low if one exists)
- **Status:** Proposed fix
- **Affects default config?** Only when the **incoming** feature is enabled for a deployment/domain (it is
  off unless configured), but anonymous-by-design when on
- **Related:** finding 02 F9; F10 (invite limiter IP resolution); existing limiters
  `FeedbackRateLimiter`, `InviteTokenRateLimiter`, `DnsRateLimiter`
- **Primary files:** `apps/api/incoming/logic/create_incoming_secret.rb:67-99,216-239`,
  `apps/api/incoming/logic/validate_recipient.rb`, `apps/api/incoming/routes.txt:22-24`,
  `lib/onetime/security/feedback_rate_limiter.rb` (pattern to mirror)

## Problem (recap)

All three incoming routes are `noauth` (`apps/api/incoming/routes.txt:22-24`,
`apps/api/incoming/auth_strategies.rb:26`), and neither `/secret` nor `/validate` applies a rate limiter in
its logic class (`raise_concerns` does entitlement + validation only, `create_incoming_secret.rb:67-99`). Each
successful `/secret`:

- creates and persists an encrypted secret + receipt in Redis (`create_and_encrypt_secret`, `:180-203`), and
- **enqueues an email to a configured recipient** (`send_recipient_notification`, `:216-235`):

```ruby
# create_incoming_secret.rb:222-233
Onetime::Jobs::Publisher.enqueue_email(
  :incoming_secret,
  { secret_key: secret.identifier, recipient: recipient_email, memo: memo, ... },
  domain_id: domain_id,
)
```

Valid recipient hashes are **published** by `GET /api/incoming/config`
(assessment §7, `get_config.rb:56-60`), so an attacker does not need to guess them. With no per-IP/per-domain
limiter, an anonymous attacker can:
- **flood a configured recipient's mailbox** with notification emails (one per `/secret`), and/or
- **flood Redis** with anonymous secret/receipt records.

The recipient *email* is never recoverable (hash indirection, §7 B5), and per-domain entitlement gating
(`require_domain_entitlement!('incoming_secrets')`, `:71`) limits *which* domains are usable — but neither
stops volume abuse against an enabled domain's known recipients.

*Confirm first:* whether an **upstream** per-IP limiter (reverse proxy / middleware / WAF) already throttles
these routes in production. The assessment flags this as the deciding factor: Medium if no limiter exists,
Low if one does. The fix below adds an in-app limiter so protection does not depend on deployment-specific
infrastructure.

## Root cause

The incoming feature was designed for anonymous submission (bug-bounty / tip intake), so it deliberately has
no auth to anchor a per-account limit. But "anonymous" does not mean "unbounded": the codebase already has a
reusable per-IP limiter pattern for exactly this situation (`FeedbackRateLimiter`,
`InviteTokenRateLimiter`), and it simply was not applied to the incoming endpoints. The send-email side
effect makes the missing limit an abuse amplifier (one cheap request → one delivered email to a third party).

## Prescribed resolution

Add an in-logic, per-IP **and** per-domain rate limiter to `/secret` (submission + email) and `/validate`
(probe), reusing the existing limiter shape so behavior, logging, and test bypass are consistent. Bucket by
both client IP and the resolved domain so one abusive IP cannot exhaust a domain and one domain's abuse does
not affect others.

### Implementation steps

1. Add `Onetime::Security::IncomingRateLimiter` modeled on `FeedbackRateLimiter`
   (`lib/onetime/security/feedback_rate_limiter.rb`): an atomic-Lua INCR + EXPIRE + lockout, `check!` /
   `record!`, IP sanitization, obscured-IP logging, and the `test_bypass?` escape hatch. Bucket the key on
   **(domain, ip)** so limits are per-tenant:

   ```ruby
   # lib/onetime/security/incoming_rate_limiter.rb (sketch — mirror FeedbackRateLimiter)
   module Onetime::Security
     module IncomingRateLimiter
       MAX_SUBMISSIONS  = 10    # per window, per (domain, ip) — tune for legitimate tip volume
       RATE_WINDOW      = 600   # 10 min
       LOCKOUT_DURATION = 1200  # 20 min

       def check_incoming_rate_limit!(domain_key, ip_address)
         return if ip_address.to_s.empty?
         # ... same pipelined lockout check + LimitExceeded raise as FeedbackRateLimiter ...
       end

       def record_incoming_submission!(domain_key, ip_address)
         # ... same atomic Lua INCR/EXPIRE/lockout, keyed "incoming:{domain_key}:{ip}" ...
       end
     end
   end
   ```

2. Wire it into `CreateIncomingSecret`. Check **before** the expensive work and the email enqueue; record on
   success so failed validations do not consume budget asymmetrically (or record on every attempt for
   `/validate` to throttle probing):

   ```ruby
   # apps/api/incoming/logic/create_incoming_secret.rb
   include Onetime::Security::IncomingRateLimiter

   def raise_concerns
     client_ip  = @strategy_result&.metadata&.dig(:ip) || @strategy_result&.metadata&.dig('ip')
     domain_key = display_domain.to_s.empty? ? 'canonical' : display_domain
     check_incoming_rate_limit!(domain_key, client_ip)   # fail-closed on abuse

     resolver.require_domain_entitlement!('incoming_secrets')
     # ... existing validation ...
   end

   def process
     create_and_encrypt_secret
     @greenlighted = receipt.valid? && secret.valid?
     raise_form_error 'Failed to create secret' unless @greenlighted
     update_customer_stats
     send_recipient_notification          # the rate-limited side effect
     record_incoming_submission!(domain_key, client_ip)   # count successful sends
     success_data
   end
   ```

3. Apply the same limiter to `ValidateRecipient` (`validate_recipient.rb`) — it is a noauth probe against the
   recipient config; rate-limit it (record every attempt) to prevent enumeration/abuse of `/validate`.
   `GetConfig` is a read of already-public hashes; limit it only if probing is a concern.

4. **IP resolution (shared with F10):** the limiter is only effective if `metadata[:ip]` carries the real
   client IP. Verify the production proxy populates it via
   `lib/onetime/application/auth_strategies/helpers.rb` (the invite limiter falls back to `0.0.0.0`, F10 /
   `show_invite.rb:37`). If IP cannot be trusted, fall back to a stricter **per-domain global** ceiling so a
   single domain's recipients cannot be flooded regardless of source IP.

### Alternatives considered

- **Rely on an upstream proxy/WAF limiter:** acceptable *if confirmed present and correctly configured*, but
  it is deployment-specific and invisible to the app. An in-app limiter guarantees the protection ships with
  the feature (defense-in-depth, and the only protection for self-hosted deployments without a WAF).
- **Per-IP only (no domain bucket):** insufficient — a botnet spreads across IPs. The per-domain ceiling (a
  cap on total submissions/emails per domain per window) is the backstop that actually protects a recipient's
  mailbox; combine both.
- **CAPTCHA on submit:** heavier UX cost and at odds with the anonymous-tip use case; a rate limit is the
  lighter, sufficient control for the documented abuse (mail-flood / Redis-flood).

## Test / verification

Add `lib/onetime/security/spec` + incoming logic specs (set `force_enabled` to exercise the limiter in test,
as `InviteTokenRateLimiter` does):
1. **Per-IP lockout:** N+1 `/secret` from one IP within the window → `LimitExceeded`; the (N+1)th email is
   **not** enqueued.
2. **Per-domain ceiling:** submissions spread across many IPs to one domain hit the domain cap → throttled.
3. **Isolation:** abuse on domain A does not throttle domain B.
4. **/validate throttled:** repeated `/validate` probes from one IP hit the limit.
5. **Happy path:** a legitimate single submission still creates the secret and enqueues exactly one email.
6. **IP fallback:** with `metadata[:ip]` absent, the per-domain ceiling still applies (no unbounded path).

## Effort & risk

- **Effort:** Low–Medium — one new limiter module (largely copied from `FeedbackRateLimiter`) plus wiring into
  two logic classes and specs.
- **Back-compat:** legitimate tip volume must stay under the limits; tune `MAX_SUBMISSIONS`/`RATE_WINDOW` per
  the deployment's expected intake and expose them as constants (as the existing limiters do).
- **Risk:** Low. The feature is opt-in; the limiter only rejects abusive volume and preserves the single
  legitimate submission path. Confirm the upstream-limiter question first to finalize the Low-vs-Medium
  severity.
