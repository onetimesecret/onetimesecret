# A3 / P2 — Host-header trust (poisoned auth-email links & host injection)

- **Severity:** High (A3, auth email links) / Medium (P2, general host injection)
- **Status:** Proposed fix — single shared remediation for two findings
- **Affects default config?** A3 only when auth/email is enabled; P2 is latent in all configs
- **Related:** A6 (WebAuthn RP-ID from host). Findings 01, 04 #3.
- **Primary files:** `lib/middleware/detect_host.rb:156-194`, `lib/onetime/middleware/domain_strategy.rb:104-149`,
  `apps/web/auth/config/email/reset_password.rb:14-15` (and sibling email link builders),
  otto 2.3.1 trusted-proxy config (`Otto::Utils.resolve_client_ip` / trusted-proxy settings)

## Problem (recap)

- **A3:** Password-reset, magic-link, and verification **email links are built from
  `request.base_url`**. OTS never pins Rodauth's `base_url`/`domain`, and the host middleware doesn't
  reject untrusted Host values, so an attacker-supplied `Host`/`X-Forwarded-Host` causes a valid
  single-use token to be embedded in a link pointing at an attacker domain — credential/token theft when
  the victim clicks.
- **P2:** `Rack::DetectHost` trusts forwarded host headers from **any** RFC1918/loopback peer using its
  own `private_ip?`, independent of otto 2.3.1's trusted-proxy configuration. From an internal/SSRF
  vantage this allows host-header injection that feeds routing, link generation, and reflected response
  headers (`domain_strategy.rb:122-149`).

These are the same underlying weakness: **the request-supplied host is trusted as authoritative.**

## Root cause

Host derivation is request-driven with ad-hoc trust (`private_ip?`), not pinned to a configured canonical
host nor aligned with the framework's single trusted-proxy model.

## Prescribed resolution

Treat the public host as **configuration**, not request input, and align proxy trust with otto:

1. **Pin a canonical host for all generated links.** Drive Rodauth `base_url`/`domain` and every email
   link builder from `site.host` (+ `SSL`) configuration, not `request.base_url`. Password-reset, magic
   link, and verification emails then always point at the canonical origin regardless of the inbound
   `Host`. (`reset_password.rb` and siblings.)
2. **Validate/allowlist the inbound Host.** In `DetectHost`/`DomainStrategy`, accept a forwarded host
   only when it matches the configured canonical host or the configured custom-domain set; otherwise fall
   back to the canonical host (don't reflect the attacker value). For custom-domain features, match
   against the verified `CustomDomain` registry rather than trusting arbitrary input.
3. **Align proxy trust with otto 2.3.1.** Replace `DetectHost`'s local `private_ip?` heuristic with the
   single `site.network.trusted_proxy` configuration otto already uses for client-IP resolution
   (`Otto::Utils.resolve_client_ip`). Forwarded `Host`/`X-Forwarded-Host` are honored **only** when the
   immediate peer is a configured trusted proxy — same rule as forwarded client IPs. This is the
   "harmonization" the recent otto 2.3.1 work started; extend it to host handling.
4. **A6 follow-on:** with a pinned canonical origin, derive the WebAuthn RP-ID/origin from configuration
   too (see `A6-webauthn-rpid.md`), eliminating host-derived RP-ID.

## Alternatives considered

- **Sanitize the Host but still reflect it:** insufficient — link generation needs an *authoritative*
  origin; sanitization alone can't decide which host is legitimate.
- **Trust the first reverse proxy implicitly:** that's the current bug (any private peer is "trusted").
  Use the explicit trusted-proxy allowlist instead.

## Test / verification

- Password-reset/magic-link request with `Host: attacker.test` (and via `X-Forwarded-Host` from a
  non-trusted peer) → the emitted email link uses the configured canonical host, not the attacker host.
- `DetectHost` honors `X-Forwarded-Host` only from a configured trusted proxy; from an arbitrary
  RFC1918 peer it does not.
- Custom-domain request for a verified domain still resolves correctly; an unknown host falls back to
  canonical.

## Effort & risk

- **Effort:** Medium — config-driven `base_url` for Rodauth/emails + host allowlisting + swapping
  `private_ip?` for the otto trusted-proxy config.
- **Risk:** Medium — custom-domain routing must keep working; cover canonical, verified-custom-domain,
  and untrusted-host cases. Roll out behind the existing domains feature flag.
