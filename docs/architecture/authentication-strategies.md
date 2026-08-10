# Authentication Strategies

How the request-authentication layer resolves an identity, and the session
contract that logic classes depend on. See also the
[authentication section](../authentication/README.md) for auth modes and SSO.

## StrategyResult and the session contract

Each strategy returns a `StrategyResult` — an immutable `Data.define` provided by
Otto. Its `session` field is a plain `Hash`, accessed only with bracket notation;
Otto never calls `.id` or other methods on it. `StrategyResult.anonymous`
defaults to `session: {}`, so an empty hash is a valid session at this layer.

OTS assigns `@sess = strategy_result.session` in `Onetime::Logic::Base`, and
logic classes read it by key (`@sess['authenticated']`, `@sess['domain_context']`).

**Two distinct session objects — do not conflate them:**

- `strategy_result.session` → `@sess` in **logic classes**. A plain hash carrying
  the authenticated identity's state.
- `req.session` / `env['rack.session']` in **controllers**. The Rack session.

They are different objects reached by different paths; `.id`-style access appears
only on the Rack session in controllers, never on `@sess`.

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

The refusal is scoped to requests that would otherwise become _anonymous_.
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
  _missing_ credentials, never on _invalid_ ones.
