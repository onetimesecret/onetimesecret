# Authentication Strategies

## What StrategyResult tells us

`StrategyResult` is a `Data.define` (immutable). Its `session` field is accessed in two places:
- Line 232: `session[:user_id] || session['user_id']` — bracket access inside `user_id`
- Line 255: `session[:id] || session['id'] || session[:session_id] || session['session_id']` — bracket access inside `session_id`
- Line 115: `StrategyResult.anonymous` defaults to `session: {}`

So Otto itself treats `session` purely as a Hash. An empty `{}` works fine at this layer.

## What OTS does with `@sess`

From the grep results, `@sess` (assigned from `strategy_result.session` in `Logic::Base:53`) is only accessed with bracket notation in logic classes — `@sess['authenticated']`, `sess['domain_context']`, etc. No `.id` calls on `@sess` anywhere.

The `.id` calls the Explore agent found are on a different object: `req.session` / `env['rack.session']` in controllers, not `strategy_result.session` in logic classes. The rodauth-expert was correct about the two separate paths.

## Three codepath families to test

### 1. Strategy-level tests — Does each strategy return the right StrategyResult shape?

- BasicAuthStrategy with valid credentials → `StrategyResult` with `session: {}`, `user: <Customer>`, `authenticated?: true`
- BasicAuthStrategy with invalid credentials → `AuthFailure`
- BasicAuthStrategy with nonexistent user → `AuthFailure` (timing-safe)
- BasicAuthStrategy with no auth header → `AuthFailure`
- NoAuthStrategy with empty session → `StrategyResult` with `user: nil`, `authenticated?: false`
- NoAuthStrategy with authenticated session → `StrategyResult` with real customer
- SessionAuthStrategy with valid session → `StrategyResult` with session from env

### 2. Logic class integration tests — Does `Logic::Base.new(strategy_result, params)` work correctly when the strategy result comes from BasicAuth?

- Construct a `StrategyResult` with `session: {}` and a real customer → instantiate `GenerateAPIToken` → call `raise_concerns` → verify `@sess['authenticated']` returns `nil` (not `true`), so it correctly blocks the action
- This is actually an interesting finding: `GenerateAPIToken#raise_concerns` checks `@sess['authenticated'] == true`, but BasicAuth passes `session: {}` which means `@sess['authenticated']` is `nil`. So `GenerateAPIToken` would reject BasicAuth requests even though BasicAuth is listed on the route. That might be a real bug worth surfacing.

### 3. Route chain tests — Does the `basicauth,noauth` fallback chain work correctly?

- Request with valid Basic auth header → `basicauth` strategy succeeds, `noauth` never runs
- Request with invalid Basic auth header → `basicauth` fails, chain should stop (bad credentials should not fall through to anonymous)
- Request with no auth header → `basicauth` fails (no header), falls through to `noauth` → anonymous access

That third family is the one that validates your concern about bad credentials passing through as anonymous. This needs to test Otto's `RouteAuthWrapper` chain behavior, not just individual strategies.

## Where to put the tests

The existing pattern is tryouts for unit-level strategy tests (`try/unit/auth_strategies/noauth_strategy_try.rb`). RSpec is used for integration tests in `spec/integration/`. I'd suggest:

- `spec/unit/auth_strategies/basic_auth_strategy_spec.rb` — Strategy-level tests for all BasicAuth paths
- `spec/unit/auth_strategies/session_contract_spec.rb` — Tests that verify the session object contract (`[]` access works, expected keys present/absent) for each strategy's result
- `spec/integration/basic_auth_logic_spec.rb` — Integration tests constructing StrategyResults with `session: {}` and passing them into Logic classes like `GenerateAPIToken`, `UpdateDomainContext`, `RemoveDomain` to verify they handle the empty session correctly
