# Authentication Strategies

How the request-authentication layer resolves an identity, and the session
contract that logic classes depend on. See also the
[authentication section](../authentication/README.md) for auth modes and SSO.

## StrategyResult and the session contract

Each strategy returns an Otto `StrategyResult`. On normal Rack requests, the
built-in strategies pass `env['rack.session']` through as
`strategy_result.session`. `Onetime::Logic::Base` assigns that same session object
to `@sess`, and logic classes read it by key
(`@sess['authenticated']`, `@sess['domain_context']`).

Controllers reach the same session through `req.session` or
`env['rack.session']`; logic classes reach it through `@sess`. Treat those as two
access paths to the Rack session, not as independent stores.

There is one important exception: a stateless Basic-auth request can have no Rack
session, so `BasicAuthStrategy` returns `session: nil`. Session-only logic must
therefore continue to require its session state explicitly rather than inferring
it from the authenticated customer alone.

## Basic auth credential identity

`BasicAuthStrategy` resolves the Basic username via
`Customer.load_by_extid_or_email`: it accepts the **account email** or the
**customer external ID** (`ur…` prefix). The password is the API token.

Two lookalike identifiers do **not** resolve and must never be documented as
the username: the organization external ID (`on…` prefix) and the UUIDv7
`owner_id` emitted in API responses. Any doc, UI copy, or support guidance
about API credentials must say "email or customer ID (`ur…`)".

## Strategy chains and fail-closed behaviour

Routes declare an ordered strategy chain (e.g. `basicauth,noauth`) resolved by
Otto's `RouteAuthWrapper`:

- Valid credentials → the first matching strategy wins; later strategies do not run.
- No credentials presented → the chain falls through to `noauth` (anonymous access).
- **Invalid** credentials must fail closed — a bad credential must not fall
  through to anonymous.

The refusal is scoped to requests that would otherwise become *anonymous*.
`NoAuthStrategy` reads the credentialed-failure marker only after the session
resolves no identity, so a valid session cookie outranks a rejected
`Authorization` header. Without that ordering, a logged-in browser that
re-sends cached Basic credentials — or any deployment behind an htpasswd
reverse proxy that forwards its own header — would 401 on every
`basicauth,noauth` route, web-UI conceal included. Anonymous requests bearing
a forwarded header still 401; that is the intended fail-closed edge, and
operators must strip `Authorization` before proxying to the API.

Because a strategy such as BasicAuth yields `session: {}`, any logic class that
gates on `@sess['authenticated'] == true` will reject that request. Session-only
actions are mounted accordingly: `POST /n` (`GenerateAPIToken`) is declared
`auth=sessionauth` with no `basicauth`, and this is locked by regression tests
(`apps/web/auth/spec/integration/full/basicauth/`), so the empty-session case
cannot silently authorize.

## Test surfaces

- Strategy-level (unit): each strategy returns the correct `StrategyResult` /
  `AuthFailure` for valid, invalid, missing, and nonexistent-user inputs. Pattern:
  tryouts under `try/unit/auth_strategies/`.
- Session-contract: for each strategy's result, bracket access works and the
  expected keys are present or absent.
- Chain behaviour: the `basicauth,noauth` fallback admits anonymous only on
  *missing* credentials, never on *invalid* ones.
