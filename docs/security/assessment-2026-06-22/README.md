# Security Assessment — 2026-06-22

Authorized internal security review of OneTimeSecret and its supporting libraries
(`otto`, `familia`, `rodauth`, `rodauth-omniauth`). Source review + local runtime validation.

> Confidential. Intentionally not published via PR. Contains a working proof-of-concept for a
> confirmed vulnerability. Handle per `SECURITY.md`.

## Start here
- **`findings/00-EXECUTIVE-REPORT.md`** — executive synthesis, focus-area coverage, top priorities.
- **`risk-register.md`** — every finding ranked by severity / exploitability / business impact, with
  a flag for whether it affects the default (out-of-the-box) configuration.
- **`resolutions/`** — one prescribed-fix document per finding (added after the report).

## Supporting material
- `findings/01`–`06` — detailed per-area reports with `file:line` evidence.
- `poc/` — reproduction scripts (the `race_reveal_*` and `_reveal_worker` scripts demonstrate the
  one-time-reveal race; `headers_check.rb` dumps live security headers).
- `evidence/` — captured PoC output (`race_poc_output.md`, `headers_output.md`).
- `notes/tooling.md` — environment, tooling, and reproduction notes.

## Headline
- **Critical:** SSO email-match account takeover (gated on SSO; not yet enabled in production) — see
  `resolutions/A1-sso-account-linking.md`, designed in concert with issue #3499.
- **High (default-config, PoC-confirmed):** the one-time reveal/burn guarantee is not concurrency-safe
  (12/12 parallel processes obtained the same secret) — see `resolutions/C1-one-time-reveal-atomicity.md`.
- **High:** secure headers (CSP / X-Frame-Options / HSTS) off by default; CSRF exempt for cookie-auth
  `/api/*` mutations; `oauth2` 2.0.18 CVE; host-header trust in auth email links.
