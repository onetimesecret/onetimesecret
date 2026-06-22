# D1 — `oauth2` 2.0.18 bearer-token leak (GHSA-pp92-crg2-gfv9)

- **Severity:** High (gated on SSO/OIDC being enabled)
- **Status:** Proposed fix (straightforward dependency bump)
- **Affects default config?** No (SSO off by default)
- **Related:** A1/A2/A4 (same SSO surface). Finding 06 #1.
- **Primary files:** `Gemfile.lock:265` (`oauth2 (2.0.18)`); pulled transitively via the
  `omniauth_openid_connect` → `openid_connect` → `rack-oauth2` chain.

## Problem (recap)

`oauth2` 2.0.18 is vulnerable to **GHSA-pp92-crg2-gfv9**: a protocol-relative redirect can cause the
`Authorization` (bearer) header to be sent to an attacker-controlled host, leaking the token. The library
is on the OIDC/OmniAuth login path, so it is reachable once SSO is enabled. Fixed in **2.0.22**.

## Root cause

A transitive dependency pinned (resolved) below the patched version. The top-level Gemfile constraint
already permits the fix; only the lockfile needs to move.

## Prescribed resolution

1. **Bump to `>= 2.0.22`** and refresh the lockfile:
   ```
   bundle update oauth2 --conservative
   ```
   Confirm `Gemfile.lock` shows `oauth2 (>= 2.0.22)` and that the `omniauth_openid_connect` /
   `rack-oauth2` chain still resolves. If a top-level pin is desired for clarity, add
   `gem 'oauth2', '>= 2.0.22'` to the Gemfile (the existing `~> 2.0` / transitive constraints allow it).
2. **Re-run the advisory scan** to confirm the advisory clears:
   ```
   bundle exec bundler-audit check --update
   ```
3. **Rebuild the OCI images** so the patched gem ships (the lockfile is frozen at build time).
4. **Regression:** run the SSO/OmniAuth integration specs (the `apps/web/auth/spec/integration/full/omniauth_*`
   suite) to confirm no behavioral change from the bump.

## Alternatives considered

- **Wait until SSO ships:** not advisable even though SSO is off by default — it's a free, low-risk bump
  that removes a High before the feature goes live. Do it now.

## Effort & risk

- **Effort:** Trivial (one `bundle update` + image rebuild).
- **Risk:** Very low — patch release within the same major; covered by the OmniAuth integration specs.
