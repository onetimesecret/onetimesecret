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

---

## Comparative Analysis: Rodauth vs Otto

### Architectural Philosophy

| Dimension | Rodauth | Otto |
|-----------|---------|------|
| What it is | Authentication library (Roda plugin) | Rack routing framework |
| Auth ownership | Owns the full auth lifecycle (login, logout, password reset, 2FA, etc.) | Owns only the auth check — delegates credential verification to the app |
| Session layer | Abstracts via overridable `session` method | Reads `env['rack.session']` from external middleware |
| Stateless support | JWT feature replaces session backing store transparently | No built-in stateless auth; strategy system can accommodate it |
| Extension model | Method override chains via Ruby modules (features) | Named strategy registration + route-level declaration |

### How They Handle the Same Problems

**"Is this request authenticated?"**

| | Rodauth | Otto |
|-|---------|------|
| Entry point | `logged_in?` → `session_value` → `session[session_key]` | `RouteAuthWrapper#call` → `strategy.authenticate(env, requirement)` |
| Abstraction | Single `session` method, overridden per transport | Named strategies with OR composition |
| Result type | Truthy/falsy from `session_value` | `StrategyResult` immutable value object |

**Session vs stateless**

| | Rodauth | Otto |
|-|---------|------|
| Session-based | `session` → `scope.session` (Rack session) | `SessionStrategy` reads `env['rack.session']` |
| JWT | `session` → decoded JWT hash (transparent swap) | Not implemented; would be a custom strategy |
| Basic Auth | `logged_in?` override → bootstraps a Rack session | Not implemented |

The key difference: Rodauth's abstraction point is the `session` method — swap the backing store, everything else works unchanged. Otto's abstraction point is the `AuthStrategy` interface — swap the strategy, the route wrapper and result propagation work unchanged. Same principle, different layer.

### Alignment Assessment

**Where they complement each other well:**

1. **Clean boundary.** Rodauth handles credential verification, session establishment, account lifecycle (registration, recovery, 2FA). Otto handles request routing, auth enforcement per-route, and result propagation to business logic. Neither steps on the other's concerns.
2. **Session contract compatibility.** Rodauth writes `session[:account_id]` and `session[:authenticated_by]`. Otto's `SessionStrategy` reads `session[@session_key]`. The contract is a single key in `env['rack.session']` — they can share a Rack session cookie with minimal configuration (set `@session_key` to `:account_id`).
3. **The Logic class pattern.** Otto's logic classes receive a `StrategyResult` as constructor arg, decoupled from env. This aligns with Rodauth's philosophy of separating auth concerns from business logic.

**Where they have friction:**

1. **JWT gap.** Rodauth's JWT feature replaces session with a decoded JWT hash — everything downstream is transparent. Otto has no equivalent. If an Otto app uses Rodauth for JWT auth, Otto's `SessionStrategy` wouldn't work because there's no `env['rack.session']` in stateless JWT mode. A custom strategy would need to read Rodauth's JWT-decoded state, which means understanding Rodauth's internals.
2. **Basic Auth session side-effect.** Rodauth's HTTP Basic Auth writes to the Rack session after credential verification. This means Otto's `SessionStrategy` would work on subsequent requests (session cookie exists), but the first request requires Rodauth's `logged_in?` override to run before Otto's auth check. Middleware ordering becomes critical.
3. **Double auth checking.** If Rodauth sits upstream (as Roda middleware) and Otto sits downstream (as the main app), both will attempt to determine auth state independently. Rodauth via `require_account` in Roda routes, Otto via `RouteAuthWrapper`. Without careful coordination, you get redundant DB queries and potential inconsistency.
4. **No shared result type.** Rodauth exposes auth state via `rodauth.logged_in?`, `rodauth.authenticated?`, `rodauth.account`. Otto exposes it via `env['otto.strategy_result']`. There's no bridge between these representations.

---

## Recommendations for Cohesive Design

### 1. Build a Rodauth-aware Otto strategy.

A `RodauthStrategy` that reads Rodauth's state from the Rack environment would bridge the two systems cleanly:

```ruby
class RodauthStrategy < Otto::Security::Authentication::AuthStrategy
  def authenticate(env, _requirement)
    rodauth = env['rodauth'] # Rodauth sets this on the Rack env
    return failure('No rodauth instance') unless rodauth
    return failure('Not authenticated') unless rodauth.logged_in?

    rodauth.account_from_session
    success(
      session: env['rack.session'],
      user: rodauth.account,
      auth_method: rodauth.authenticated_by&.first || 'session'
    )
  end
end
```

This would let Otto routes declare `auth=rodauth` and get a `StrategyResult` populated from Rodauth's state — including JWT mode, where `rodauth.logged_in?` already transparently reads the JWT payload.

### 2. Let Rodauth own all credential operations.

Otto should never verify passwords, issue tokens, or manage account lifecycle. Rodauth handles login, logout, registration, password reset, 2FA, JWT issuance, and token refresh. Otto handles route-level enforcement and result propagation to business logic. The boundary is: Rodauth writes auth state, Otto reads auth state.

### 3. For JWT mode, bridge via `env['rodauth']` not `env['rack.session']`.

When Rodauth's JWT feature is active, `env['rack.session']` is not the auth source — the JWT payload is. Reading `env['rodauth'].logged_in?` works in both session and JWT modes because Rodauth's `session` method abstraction handles the transport difference internally. A Rodauth-aware strategy should always go through the Rodauth instance, not directly through the Rack session.

### 4. Middleware ordering contract.

Establish a clear ordering: Rack session middleware → Rodauth (Roda middleware) → Otto. Rodauth runs first to establish auth state (decode JWT, validate session, handle basic auth). Otto's `RouteAuthWrapper` then reads that state via the `RodauthStrategy`. This eliminates double-checking and ensures consistency.

### 5. Consider a shared `StrategyResult` factory on the Rodauth side.

If Otto's logic classes expect `StrategyResult` objects, and Rodauth is the auth source, a thin adapter that constructs `StrategyResult` from Rodauth state would keep the contract clean without coupling Otto to Rodauth internals. This could live in a small integration gem or in the application's configuration.

### 6. Configuration freeze alignment.

Otto freezes all security configuration on first request (`freeze_configuration!`). Rodauth's configuration is set at plugin load time and is effectively immutable after that. These align well — both prevent runtime mutation of security state.
