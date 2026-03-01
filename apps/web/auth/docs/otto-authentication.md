# Otto v2.0 Authentication: Definitive Analysis

## What Otto Is

Otto is a pure Rack framework — no Roda, no Sinatra, no external web framework. Routes are defined in plain-text files, not Ruby DSL. Authentication is a pluggable strategy system where route definitions declare their requirements inline:

```
GET  /profile  Dashboard  auth=session
GET  /admin    Admin      auth=role:admin
GET  /api/data ApiHandler auth=apikey,session  response=json
```

---

## Core Auth Mechanism

Every route handler is wrapped by `RouteAuthWrapper` at startup (`route_handlers/factory.rb:28-38`). On each request:

1. If the route has no `auth=` parameter → anonymous `StrategyResult`, pass through
2. If present → resolve each named strategy, try in order (first success wins, OR semantics)
3. Result stored as `env['otto.strategy_result']` — an immutable `Data.define` value object
4. Logic classes receive the `StrategyResult` as their first constructor argument — no direct env access needed

The strategies are registered by the application at startup via `add_auth_strategy(name, instance)` and resolved by name at request time through `StrategyResolver`.

## Session Auth

`SessionStrategy` (`strategies/session_strategy.rb:18-27`) reads `env['rack.session'][@session_key]`. Otto does not provide session middleware — the application must add `Rack::Session::Cookie` or equivalent upstream in `config.ru`. Otto reads sessions but never writes them. Session establishment is the application's responsibility.

## JWT / Token Auth

Otto has no JWT implementation. No JWT gems in the gemspec, no token encoding/decoding, no signature verification, no expiry logic, no refresh mechanism. The only token auth is the MCP subsystem's `TokenAuth` (`mcp/auth/token.rb`), which does a simple `Set#include?` check against a static allowlist of opaque Bearer tokens — not JWT.

The framework is designed so a JWT strategy could be registered:

```ruby
otto.add_auth_strategy('jwt', MyJwtStrategy.new(secret: '...'))
# Then in routes: GET /api/data Handler auth=jwt
```

But nothing ships.

## HTTP Basic Auth

Not present. No `Rack::Auth::Basic`, no `WWW-Authenticate` header generation, no password hashing, no bcrypt. Otto's built-in strategies are all stateless readers of pre-established state (session keys, API keys, role arrays). Credential verification is entirely the application's concern.

## Rodauth Integration

No direct integration. Rodauth is mentioned only in documentation comments on `StrategyResult` (`strategy_result.rb:73-74`) where session key contracts are documented for interoperability:

```ruby
#   session['account_external_id']  # Rodauth external_id
#   session['advanced_account_id']  # Rodauth account ID
```

A design document (`docs/1007-OTTO-AND-RODAUTH-SITTING-IN-A-TREE.md`) describes an external Roda+Rodauth auth app that writes session keys that Otto strategies later read, but this is a future architectural sketch, not implemented code.
