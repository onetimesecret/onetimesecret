# S2 — Clickjacking / HSTS / security headers off by default

- **Severity:** High
- **Status:** Proposed fix
- **Affects default config?** **Yes**
- **Related:** S1 (CSP), P1 (HttpOrigin/CSRF). Findings 05, 04 #1.
- **Primary files:** `etc/defaults/config.defaults.yaml:314-338`
  (`http_origin`, `xss_header`, `frame_options`, `strict_transport` all default false),
  `lib/onetime/middleware/security.rb:76`

## Problem (recap)

`frame_options`, `strict_transport` (HSTS), `http_origin` (origin CSRF), and `xss_header` all default to
**false**. With CSP also off (S1), a default install ships **neither** `X-Frame-Options` **nor**
`frame-ancestors` → it is framable/clickjackable, and has **no HSTS** → vulnerable to TLS-stripping/SSL
downgrade. Confirmed live: `X-Frame-Options` and `Strict-Transport-Security` **absent** on
`/api/v2/status` (`../evidence/headers_output.txt`). (`X-Content-Type-Options: nosniff`,
`X-XSS-Protection`, and `Referrer-Policy` *are* present.)

## Root cause

Same as S1: hardening headers are opt-in. `rack-protection` and the middleware support them; the
defaults just don't enable them.

## Prescribed resolution

Flip the defaults to secure, with operator overrides retained:

1. **`frame_options` → `true`** (emit `X-Frame-Options: DENY` / `SAMEORIGIN`). Combined with CSP
   `frame-ancestors 'none'` (S1) this gives layered clickjacking protection. Allow an override for the
   rare legitimate-embedding deployment.
2. **`strict_transport` → `true`** with a sane `max-age` (e.g. `max-age=31536000; includeSubDomains`).
   Guard against breaking plain-HTTP local/dev by binding HSTS emission to `SSL=true`/HTTPS requests so
   it's on in production (TLS) and inert in local HTTP dev.
3. **`http_origin` → `true`** so Origin/Referer is validated for state-changing requests — this is the
   default-on partner for P1's CSRF hardening.
4. **Add `Cross-Origin-Opener-Policy: same-origin`** (and consider `Cross-Origin-Resource-Policy`)
   — currently absent everywhere — to isolate the secret-bearing window.
5. `nosniff`/Referrer-Policy are already on; keep them.

All of these are one-line default changes in `config.defaults.yaml` plus the HSTS-on-HTTPS guard.

## Alternatives considered

- **HSTS on unconditionally:** risky for local HTTP/dev and for operators terminating TLS oddly; bind to
  HTTPS instead.
- **Rely on the reverse proxy (Caddy) to add headers:** fragile — not every deployment uses the bundled
  proxy; the app should be safe by itself.

## Test / verification

- Default boot → `X-Frame-Options`, `Strict-Transport-Security` (under HTTPS), origin checks present;
  re-run `../poc/headers_check.rb` and confirm in `headers_output.txt`.
- Clickjacking probe: framing the app in a cross-origin iframe is blocked.
- Dev (HTTP) boot → no HSTS emitted (no dev breakage).

## Effort & risk

- **Effort:** Small (config defaults + HSTS-on-HTTPS guard).
- **Risk:** Low–Medium. HSTS is sticky in browsers — ship the HTTPS guard and document `max-age`/preload
  implications. Coordinate `http_origin` flip with P1 so origin-checking and CSRF land together.
