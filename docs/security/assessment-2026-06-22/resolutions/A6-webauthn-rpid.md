# A6 — WebAuthn RP-ID and origin derived from attacker-controllable Host header

- **Severity:** Medium (NEEDS-VALIDATION — net impact depends on edge `Host` enforcement)
- **Status:** Proposed fix — follow-on to A3/P2; lands with the canonical-host work
- **Affects default config?** No — gated on auth being enabled **and** WebAuthn enrolled
  (`:webauthn`/`:webauthn_login`). WebAuthn is conditionally enabled (`webauthn.rb:9-11`).
- **Related:** **A3/P2 host-header-trust** (shared root cause and shared canonical-host fix — see
  `A3-P2-host-header-trust.md` §3 step 4), finding 01 §6. Reuses `env['onetime.display_domain']` /
  `DomainStrategy.canonical_domain`.
- **Primary files:**
  - `apps/web/auth/config/features/webauthn.rb:14-22` (RP-ID/origin derivation — the fix point)
  - `lib/onetime/middleware/domain_strategy.rb:137,191-193,398-402` (validated host + canonical host)
  - fork `rodauth/lib/rodauth/features/webauthn.rb` (consumes `webauthn_rp_id`/`webauthn_origin`)

## Problem (recap)

Both the expected RP-ID and the expected origin are taken straight from the inbound request host:

```ruby
# apps/web/auth/config/features/webauthn.rb:14-22
auth.webauthn_rp_id  do
  request.host                                   # attacker-controllable Host
end
auth.webauthn_origin do
  "#{request.scheme}://#{request.host_with_port}" # tracks the same host
end
```

Because the **expected** RP-ID and origin both move to match whatever host the request claims, a
mismatched/attacker host does not fail verification — the anti-phishing origin check degenerates to
"origin must equal whatever host this request says it is." If any unvalidated host reaches the app
(precisely the A3/P2 gap — the edge and `DomainStrategy` do not reject untrusted hosts; see
`A3-P2-host-header-trust.md`), a credential registered under host A can be exercised in a ceremony run
under an attacker-chosen RP-ID/origin. (Assertion *replay* is still blocked by `sign_count`; the weakened
control is origin pinning.)

The codebase already computes a validated host (`env['onetime.display_domain']`,
`domain_strategy.rb:137`) and a configured canonical host (`DomainStrategy.canonical_domain`,
`domain_strategy.rb:191-193`, sourced from `domains.default || site.host`, `:398-402`) — WebAuthn simply
does not use either.

> **Confirm first (NEEDS-VALIDATION):** Standalone exploitability requires that an unvalidated `Host`
> can actually reach the Rack app in production (i.e. the edge proxy does not strictly pin `Host`). This
> is the same precondition as A3/P2. Confirm the production edge behavior before rating impact; the fix
> below is correct hardening regardless and is essentially free once A3/P2's canonical-host pinning
> lands.

## Root cause

RP-ID/origin are treated as **request-derived** rather than **configuration-derived**. WebAuthn's
security model assumes the RP (relying party) defines a fixed, trusted RP-ID and origin allowlist;
deriving them from `request.host` hands that definition to the client/network.

## Prescribed resolution

Pin RP-ID and origin to **validated, configured** values, mirroring A3/P2's "host is configuration, not
request input" principle. Support the multi-host reality (canonical host, subdomains, verified custom
domains) explicitly rather than by trusting the request.

### Implementation steps

1. **Pin the RP-ID to a stable, configured value.** Use the registrable canonical domain — the
   eTLD+1-style apex that all first-party hosts share — so a single RP-ID covers `app.example.com`,
   `www.example.com`, etc. Derive it from `DomainStrategy.canonical_domain` (already the configured
   `site.host`/`domains.default`):

   ```ruby
   # webauthn.rb
   auth.webauthn_rp_id do
     # Stable RP-ID from configuration, NOT request.host.
     # RP-ID must be a registrable suffix of the origin's host.
     Onetime::Middleware::DomainStrategy.canonical_domain ||
       Onetime.conf.dig('site', 'host')
   end
   ```

   The RP-ID **must be a registrable suffix of every origin** WebAuthn will accept (WebAuthn spec rule).
   If the canonical host is `app.example.com` and you also serve `www.example.com`, set the RP-ID to
   `example.com` so both origins validate; if you only ever serve the exact canonical host, use it
   directly. Decide this from the deployment's host topology and document it.

2. **Validate the origin against an allowlist instead of echoing the request.** Accept the request origin
   only if it matches the canonical host or a verified host; otherwise fall back to the canonical origin
   (never reflect an arbitrary host):

   ```ruby
   auth.webauthn_origin do
     canonical = Onetime::Middleware::DomainStrategy.canonical_domain
     scheme    = Onetime.conf.dig('site', 'ssl') ? 'https' : 'http'
     # Prefer the validated display domain when it is an allowed first-party host;
     # otherwise pin to the canonical origin.
     host = env['onetime.display_domain']
     host = canonical unless allowed_webauthn_host?(host)   # see step 3
     "#{scheme}://#{host}"
   end
   ```

   `env['onetime.display_domain']` is already the sanitized/validated host
   (`domain_strategy.rb:130-137`), so this leans on the same allowlist A3/P2 introduces rather than
   re-implementing host validation.

3. **Custom-domain support → explicit per-domain RP-ID map.** OTS supports verified custom domains
   (`CustomDomain`). A WebAuthn credential is bound to the RP-ID under which it was registered, so a
   custom-domain user's credentials must use that domain's RP-ID, not the canonical one. Implement
   `allowed_webauthn_host?`/RP-ID selection against the verified `CustomDomain` registry: for a request
   on a verified custom domain, use that domain (or its registrable apex) as the RP-ID/origin; for
   first-party hosts, use the canonical domain. Do **not** derive either from an unverified request host.

4. **Land on top of A3/P2.** This is item 4 of `A3-P2-host-header-trust.md`'s prescription. Once the edge
   + `DomainStrategy` reject/allowlist untrusted hosts and `env['onetime.display_domain']` is
   trustworthy, steps 1–3 reduce to "read the validated host/config." Sequence A6 immediately after A3/P2.

### RP-ID stability & migration implications (important)

Changing the RP-ID is a **credential-invalidating** operation: an authenticator stores credentials keyed
by the RP-ID used at registration, and an assertion under a different RP-ID will not match. Therefore:

- **Choose the RP-ID once, deliberately.** If existing credentials were registered under
  `request.host` values (e.g. `app.example.com`), and you switch the pinned RP-ID to `example.com` (the
  apex), those existing credentials **break** — users must re-register. Picking the apex up front
  maximizes future host flexibility but only if it matches what was used at registration.
- **Prefer the value already in use.** If production has only ever served one host, pin the RP-ID to
  that exact host to avoid invalidating enrolled credentials. Audit the `account_webauthn_*` table /
  registration history to learn which RP-ID(s) credentials currently assume before changing anything.
- **If a change is unavoidable**, treat it as a credential migration: notify affected users, keep TOTP /
  recovery codes (A5) as the fallback factor through the transition, and require re-enrollment of
  WebAuthn under the new RP-ID. There is no in-place re-key for WebAuthn credentials.
- **Origin can vary; RP-ID should not.** You may safely broaden the *origin* allowlist (multiple first-
  party hosts/custom domains) as long as each origin's host is the RP-ID or a subdomain of it — that
  does not invalidate credentials. It is the RP-ID that must stay stable.

### Alternatives considered

- **Keep `request.host` but validate it against an allowlist first:** partial — it fixes origin
  echoing, but still derives RP-ID per-request, which is fragile (a momentary misconfig changes the
  RP-ID and breaks credentials). Pinning RP-ID to configuration is more robust.
- **Hard-code a single RP-ID constant:** simplest and safe for single-host deployments, but breaks
  custom-domain WebAuthn. The config-driven canonical + per-custom-domain map (step 3) preserves the
  feature set.
- **Set `webauthn_user_verification 'required'` here:** that is finding 01 §16 (A separate Low item), not
  A6; note it as a complementary hardening but keep it out of scope for this fix.

## Test / verification

Add to `apps/web/auth/spec/` (WebAuthn integration):

1. **Origin not reflected:** drive a WebAuthn registration/auth ceremony with `Host: attacker.test`
   (and via `X-Forwarded-Host` from a non-trusted peer) → the RP-ID/origin used for verification is the
   canonical host, **not** the attacker host; the ceremony for a canonical-host credential still
   succeeds, and an attacker-host ceremony cannot satisfy a canonical-host credential.
2. **Canonical happy path:** register + assert on the canonical host → succeeds.
3. **Custom domain:** for a verified custom domain, RP-ID/origin resolve to that domain; an unverified
   host falls back to canonical (no echo).
4. **RP-ID stability regression:** a credential registered under the pinned RP-ID still asserts after a
   request arrives with a different `Host` (proves verification no longer tracks the request host).

## Effort & risk

- **Effort:** Small once A3/P2 lands (two config blocks + reuse of `canonical_domain` /
  `display_domain`); Medium if the custom-domain RP-ID map is built out.
- **Risk:** **Medium–High if mis-sequenced** — the dominant risk is RP-ID choice invalidating existing
  WebAuthn credentials. Audit current RP-ID usage first; pin to the value already in use unless a
  deliberate, communicated re-enrollment is planned. Roll out behind the domains feature flag alongside
  A3/P2, and keep TOTP/recovery as fallback during any transition.
