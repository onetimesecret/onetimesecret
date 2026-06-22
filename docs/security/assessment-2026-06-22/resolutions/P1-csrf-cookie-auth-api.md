# P1 — CSRF protection bypassed for cookie-authenticated API mutations

- **Severity:** High (any logged-in/cookie session using API-backed actions)
- **Status:** Proposed fix
- **Affects default config?** Conditional — applies once accounts/sessions are used
- **Related:** S2 (HttpOrigin off by default). Finding 04 #2.
- **Primary files:** `lib/onetime/middleware/security.rb:142` (blanket `/api/` CSRF exemption),
  `apps/api/*/auth_strategies.rb` (per-route `auth=sessionauth,...`)

## Problem (recap)

The entire `/api/` prefix is exempted from token-based CSRF protection, but many `/api/*` POST/PATCH
endpoints accept `auth=sessionauth` (browser cookie) — including account deletion, password and
API-token changes, and secret creation. A cross-site form/`fetch` from an attacker page therefore rides
the victim's session cookie. The only origin-based fallback (`HttpOrigin`) is off by default (S2).

## Root cause

CSRF exemption is keyed on the **URL prefix** (`/api/`) rather than on the **authentication method** of
the request. The exemption is correct for *stateless* token/Basic-auth API calls (no ambient
credentials, so no CSRF risk) but wrong for *cookie-authenticated* requests to the same paths.

## Prescribed resolution

Make CSRF protection a function of how the request is authenticated, not its path prefix:

1. **Exempt only ambient-credential-free auth.** Stateless requests (Bearer/API-token, HTTP Basic) carry
   no cookie and are not CSRF-able → keep exempt. Requests authenticated by the **session cookie** must
   pass CSRF validation for unsafe methods (POST/PUT/PATCH/DELETE).
2. **Reuse the existing token.** Rodauth already issues a CSRF token and the SPA holds it in memory
   (`csrfStore`), sending it as a header. Validate that header for cookie-authenticated `/api/*`
   mutations (the SPA already has the token; service-to-service token clients are unaffected).
3. **Belt-and-suspenders origin check.** Enable `HttpOrigin` (see S2) so Origin/Referer is validated for
   state-changing requests, and set the session cookie `SameSite=Lax` (or `Strict` where UX allows) as a
   second independent layer.

```ruby
# sketch: decide CSRF requirement from the resolved auth strategy
use Rack::Protection::AuthenticityToken, except_when: ->(req, env) {
  env['otts.auth_method'].in?(%w[apitoken basicauth])   # stateless => exempt
}                                                        # cookie/session => enforced
```

(Record the chosen auth method in the env during the auth-strategy phase so the CSRF layer can read it.)

## Alternatives considered

- **Enable CSRF for the whole `/api/` prefix unconditionally:** would break legitimate stateless token
  clients (which can't hold a CSRF token). The auth-method split avoids that.
- **Rely on SameSite alone:** helpful but not sufficient (older browsers, `Lax` still allows top-level
  GET navigations; some flows need POST). Use SameSite + token + origin together.

## Test / verification

- Cross-origin POST to `/api/v2/account/destroy` (or password change) with only the session cookie and no
  CSRF header → **403**; same request with a valid CSRF header → allowed.
- Token/Basic-auth client POST with no CSRF header → allowed (unchanged).
- SPA end-to-end: normal authenticated mutations still succeed (token is sent).

## Effort & risk

- **Effort:** Medium — thread the resolved auth method into the CSRF decision; audit which `/api/*`
  routes accept `sessionauth`.
- **Risk:** Medium — get the exemption predicate right or you either break token clients or under-protect
  cookie clients. Cover both with the tests above. Pairs with S2.
