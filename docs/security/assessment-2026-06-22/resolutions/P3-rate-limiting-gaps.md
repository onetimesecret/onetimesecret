# P3 — Rate-limiting gaps on auth/login and secret creation

- **Severity:** Medium
- **Status:** Proposed fix — **superseded by re-verification correction (2026-06-24) below**
- **Affects default config?** Yes — anonymous secret creation (`/api/v3/guest/*`, `/api/v2/secret/conceal`) and login are reachable in the default deployment
- **Related:** A3/P2 (trusted-proxy / host-header trust — the IP key must use the otto-resolved client IP). Findings 04 #4, §3, §9.4.
- **Primary files:** `apps/api/v1/controllers/base.rb:145-171` (fail-open, auth-exempt V1 limiter),
  `apps/api/v2/logic/secrets/base_secret_action.rb:41-48` (`raise_concerns` — wire-in point for conceal/generate),
  `apps/web/auth/config/features/lockout.rb` (Rodauth account lockout — present but not IP-keyed),
  `lib/onetime/security/feedback_rate_limiter.rb` / `invite_token_rate_limiter.rb` (the well-built pattern to reuse),
  `lib/onetime/application/auth_strategies/helpers.rb:67-79` (canonical IP resolution)

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §5).**
> The prescribed fix below **under-counts** — it records the limiter budget only on *successful* creation,
> so failed/abusive attempts cost an attacker nothing and they flood freely under the limit.
> Step 3's `process` calls `record_secret_creation!(...) if greenlighted` (`base_secret_action.rb:104` in the
> sketch), and `greenlighted` is only true when the secret actually stores
> (`@greenlighted = receipt.valid? && secret.valid?`, `apps/api/v2/logic/secrets/base_secret_action.rb:334`).
> A request that fails validation, or is deliberately malformed, burns no quota.
>
> **Correction:** count at **attempt time**, not on success. Record the attempt *before* the success branch —
> e.g. call `record_secret_creation!(strategy_result.metadata[:ip])` in `raise_concerns` alongside (right
> after) `check_secret_creation_rate_limit!`, or at the top of `process` unconditionally — so every attempt,
> including rejected ones, consumes the budget. Drop the `if greenlighted` guard on the limiter record.

## Problem (recap)

There is no application-layer rate limiting on the two surfaces most exposed to abuse:

1. **Auth / login.** No limiter wraps session authentication, registration, or password reset. Rodauth's
   `lockout` feature locks an *account* after 5 invalid logins (`lockout.rb:15`), but that is keyed on the
   target account, not the client — it does not throttle credential-stuffing across many accounts, nor
   anonymous registration/reset flooding.
2. **V2 / V3 secret creation.** `POST /api/v2/secret/conceal|generate` and the anonymous
   `/api/v3/guest/*` conceal/generate routes are unthrottled in-app. Only passphrase brute-force on
   *retrieval* is limited (`apps/api/v2/logic/secrets/show_secret.rb:53` wires `PassphraseRateLimiter`).
3. **The V1 limiter is the wrong template.** `check_rate_limit!` (`base.rb:145-171`) is atomic (good —
   Lua INCR+EXPIRE at `:139-143`), but it **fails open** on any Redis error (`:165-168`) and **fully
   exempts authenticated non-anonymous customers** (`:147`). The code itself calls it "vestigial …
   enforced externally (infrastructure layer)" (`:124-126`). It is wired into V1 create/read only
   (`apps/api/v1/controllers/index.rb:67,87,154,192`).

Combined with the public unauthenticated intake surface (Finding §9.4), the absence of a creation limit
makes flooding / resource-exhaustion and large-scale enumeration cheap.

## Root cause

Rate limiting was treated as an infrastructure-layer concern (proxy/WAF) and the in-app V1 limiter was
deliberately neutered. The four purpose-built limiters (passphrase, feedback, invite, DNS) demonstrate the
correct in-app pattern but were only applied to the specific endpoints that motivated each one; the
general auth and creation paths were never given one.

## Prescribed resolution

Reuse the existing **atomic, fail-closed-where-it-matters** limiter pattern (the feedback/invite shape:
server-side Lua INCR+EXPIRE, lockout key, no auth exemption) and apply it to login and secret creation,
keyed on the **otto-resolved client IP** (and, for authenticated requests, additionally on account).

### Implementation steps

1. **Add a reusable creation/auth limiter module** modeled on
   `lib/onetime/security/feedback_rate_limiter.rb`. Keep the same structure: a `RECORD_*_SCRIPT` Lua
   string that does `INCR` + `EXPIRE` + lockout via `SETEX`, a `check_*!` that raises
   `Onetime::LimitExceeded` (`lib/onetime/errors.rb:224`) when locked, and a `record_*!` called on each
   attempt. Place it under `lib/onetime/security/` so it sits alongside the others.

   ```ruby
   # lib/onetime/security/secret_creation_rate_limiter.rb (sketch — mirrors feedback_rate_limiter.rb)
   module Onetime::Security::SecretCreationRateLimiter
     MAX_CREATES     = 100   # per window; tune per plan
     RATE_WINDOW     = 600
     LOCKOUT_DURATION = 600

     def check_secret_creation_rate_limit!(ip_address)
       return if ip_address.to_s.empty?       # see fail-closed note below
       # ... identical pipelined exists?/ttl check + raise LimitExceeded as feedback limiter ...
     end

     def record_secret_creation!(ip_address)
       # ... identical atomic Lua INCR+EXPIRE+SETEX as feedback_rate_limiter.rb:36-56 ...
     end
   end
   ```

2. **Key on the otto-resolved client IP, never a raw header.** Inside the secret-creation logic
   (`BaseSecretAction`), the resolved IP is already carried on the strategy result:
   `strategy_result.metadata[:ip]`, which is populated by `build_metadata` →
   `client_ip(env)` → `env['otto.client_ip']` (`lib/onetime/application/auth_strategies/helpers.rb:44-79`).
   This is the trusted-proxy-aware value (`Otto::Utils.resolve_client_ip`, `/home/user/otto/lib/otto/utils.rb:112-140`),
   so a spoofed `X-Forwarded-For` from an untrusted peer cannot rotate the key. **Do not** read
   `env['HTTP_X_FORWARDED_FOR']` or `Rack::Request#ip` directly. (This is the same key source the V1
   controller uses via `req.client_ipaddress`, `/home/user/otto/lib/otto/request.rb:122-132`.) For a
   defence-in-depth account dimension, also key on `cust&.objid` when authenticated.

   **Cross-reference A3/P2:** the limiter's anti-spoofing guarantee depends entirely on the otto 2.3.1
   trusted-proxy configuration (`site.network.trusted_proxy`) being correct. If the ingress appends rather
   than overwrites `X-Forwarded-For`, or trusts an over-broad private range, the resolved IP can be
   attacker-influenced (Finding §1.1, §3 "Key-derivation / bypass"). Land the A3/P2 host/proxy
   harmonization alongside this, and confirm the ingress overwrites XFF.

3. **Wire creation limiting into `BaseSecretAction#raise_concerns`** (the same lifecycle slot
   `ShowSecret` uses for the passphrase limiter at `show_secret.rb:46-54`), so both conceal and generate
   inherit it for V2 and V3:

   ```ruby
   # apps/api/v2/logic/secrets/base_secret_action.rb
   include Onetime::Security::SecretCreationRateLimiter

   def raise_concerns
     check_secret_creation_rate_limit!(strategy_result.metadata[:ip])
     require_entitlement!('api_access')
     # ... existing checks ...
   end

   def process
     create_secret_pair
     record_secret_creation!(strategy_result.metadata[:ip]) if greenlighted
     handle_success
   end
   ```

4. **Add login/auth throttling keyed on client IP**, complementing Rodauth's per-account `lockout`. The
   cleanest place is a Rodauth `before_login_attempt`/`before_create_account` hook (see
   `apps/web/auth/config/hooks/login.rb`) that calls a `check_*!`/`record_*!` pair keyed on the
   otto-resolved IP. This throttles credential-stuffing and registration/reset flooding that per-account
   lockout misses. Keep Rodauth `lockout` enabled — the two are complementary (account vs. client).

5. **Make the limiter fail-closed on the abuse surface — but bounded.** The V1 limiter's blanket
   "fail open on any Redis error" (`base.rb:165-168`) means an attacker who can stress Redis disables the
   limit. For the new limiters, treat a Redis failure as *fail-closed for anonymous creation/login*
   (reject with a 429/`LimitExceeded` and log loudly) rather than silently allowing unlimited traffic.
   To avoid a self-inflicted outage if Redis is briefly unavailable, gate fail-closed behind a short
   circuit-breaker / allow a small burst, but do not default to unlimited. Empty/unresolvable IP
   (`ip_address.to_s.empty?`) is the one case that must still fail open, because an authenticated request
   with a missing IP should not be hard-blocked — rely on the account-key dimension there.

6. **Do not exempt authenticated users wholesale.** Replace the V1 `cust && !cust.anonymous?` bypass with
   per-plan limits (higher ceilings for paid plans, never "unlimited"). A compromised/abusive authenticated
   account should still hit a ceiling.

7. **(Optional) retire or fix the V1 limiter.** Either delete `check_rate_limit!` and its call sites if V1
   is being deprecated, or refactor it onto the shared module so all three (V1/V2/V3) share one
   fail-closed, non-exempting implementation. Don't leave the vestigial fail-open version as the only V1
   defence.

### Alternatives considered

- **Rely solely on infrastructure (proxy/WAF) rate limiting** (the current stated posture, `base.rb:124-126`):
  insufficient as the *only* control — it is invisible to the app, not enforced in tests/CI, varies per
  deployment, and is absent for self-hosters who don't run a tuned proxy. App-layer limiting is the
  portable floor; infra limiting remains a complementary outer layer.
- **Per-account lockout only (Rodauth `lockout`):** does not stop credential-stuffing across many accounts
  or anonymous flooding. Keep it, but add IP-keyed throttling on top.
- **Global (non-IP) creation counter:** trivially turns into a self-DoS (one abuser exhausts everyone's
  budget). Per-IP + per-account keying localizes the impact.

## Test / verification

- Anonymous `POST /api/v3/guest/secret/conceal` repeated past `MAX_CREATES` within the window from a single
  resolved client IP → `429`/`LimitExceeded`; a different IP is unaffected.
- Spoof attempt: send the over-limit requests with rotating `X-Forwarded-For` values from a **non-trusted**
  peer → all map to the same bucket (the resolved `env['otto.client_ip']` is unchanged) and are throttled.
  From a configured trusted proxy with a genuinely different upstream IP → separate buckets (expected).
- Login: N+1 failed logins from one IP across *different* usernames → throttled by the new IP limiter even
  though no single account hit Rodauth's lockout; legitimate single-user retries within budget still work.
- Redis-down behaviour: with Redis unavailable, anonymous creation/login is rejected (fail-closed), logged,
  and recovers when Redis returns; an authenticated request with an unresolved IP is not hard-blocked.
- Paid plan: authenticated paid user gets the higher ceiling but is still limited (no `unlimited`).

## Effort & risk

- **Effort:** Medium — one new limiter module (copy of the feedback limiter), two wire-ins
  (`BaseSecretAction#raise_concerns`/`process` and a Rodauth login hook), plus plan-tier limit config.
- **Risk:** Medium — mis-tuned limits or a too-aggressive fail-closed policy can block legitimate traffic;
  validate the IP key source (`strategy_result.metadata[:ip]` / `env['otto.client_ip']`) actually flows
  through in V3 guest routes, and land the A3/P2 trusted-proxy harmonization so the key can't be spoofed.
  Start limits generous and tighten with telemetry.
