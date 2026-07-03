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

## Strategy chains and fail-closed behaviour

Routes declare an ordered strategy chain (e.g. `basicauth,noauth`) resolved by
Otto's `RouteAuthWrapper`:

- Valid credentials → the first matching strategy wins; later strategies do not run.
- No credentials presented → the chain falls through to `noauth` (anonymous access).
- **Invalid** credentials must fail closed — a bad credential must not fall
  through to anonymous.

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
