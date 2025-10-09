---
labels: authstrategies
---
# Authentication Architecture

**Last Updated:** 2025-10-08
**Framework:** Otto v2.0.0-pre2
**Session Store:** Redis via Rack::Session

## Overview

Onetime Secret uses Otto's authentication framework following standard Rack conventions. This document describes our concrete implementation of Otto's prescribed architecture for session and environment management.

## Architecture Pattern: Otto Prescribed Flow

```
1. Request arrives

2. Session Middleware (Rack::Session::Abstract::Persisted)
   Location: lib/onetime/application/middleware_stack.rb
   Class: Onetime::Session (wraps Rack::Session::Redis)
   Sets: env['rack.session']
   Cookie: 'onetime.session'

3. Identity Resolution Middleware (Optional - Advanced Mode Only)
   Location: lib/onetime/middleware/identity_resolution.rb
   Class: Onetime::Middleware::IdentityResolution
   Reads: env['rack.session']
   Sets: env['identity.resolved'], env['identity.authenticated'], env['identity.source']

4. Otto's AuthenticationMiddleware
   Location: otto gem (lib/otto/security/authentication/authentication_middleware.rb)
   Class: Otto::Security::Authentication::AuthenticationMiddleware
   - Reads env['otto.route_definition'] (set by Otto router)
   - Selects strategy based on route's auth requirement
   - Strategy.authenticate(env, requirement) reads env['rack.session']
   - Creates StrategyResult
   - Sets env['otto.strategy_result'], env['otto.user'], env['otto.user_context']

5. Application Controllers
   Location: apps/web/core/controllers/*, apps/api/v2/controllers/*
   Pattern: req.env['otto.user'], req.env['otto.strategy_result']
   - Read from env, never from session directly

6. Logic Classes (on auth state changes)
   Location: apps/api/v2/logic/authentication/*, apps/api/v2/logic/account/*
   Pattern: @strategy_result.session['key'] = value
   - Write to session via StrategyResult.session attribute
   - Only on login/logout/registration

7. Session Middleware persists to Redis
   Same middleware as step 2
```

## Session vs Environment

### Session: Persistence Layer (Redis)

**Cookie Name:** `onetime.session`
**Environment Key:** `env['rack.session']`
**Storage:** Redis (via `Rack::Session::Redis`)

Session stores authentication state that persists across requests:

```ruby
# Written by Logic classes on login/registration
# Location: apps/api/v2/logic/authentication/authenticate_session.rb
session['authenticated']      = true          # Boolean flag
session['identity_id']        = customer.custid  # Customer ID
session['email']              = customer.email   # Email
session['authenticated_at']   = Time.now.to_i    # Login timestamp
session['ip_address']         = ip               # Client IP
session['user_agent']         = user_agent       # Client UA
session['locale']             = locale           # User locale

# Advanced mode adds (written by Rodauth)
# Location: apps/web/auth/config/features/*.rb
session['account_external_id'] = account.id        # Rodauth external_id
session['advanced_account_id'] = account.id        # Rodauth account ID
```

**Write Pattern:** Only authentication Logic classes write to session
**Read Pattern:** Only middleware reads from session (controllers never read directly)

### Environment: Request-Scoped State

Otto's AuthenticationMiddleware reads from `env['rack.session']` once per request and populates `env`:

```ruby
# Set by Otto's AuthenticationMiddleware
env['otto.strategy_result']   # StrategyResult object
env['otto.user']              # User object (Customer instance)
env['otto.user_context']      # User context hash
env['otto.route_definition']  # Current route definition

# Set by IdentityResolution middleware (advanced mode only)
env['identity.resolved']      # Resolved identity (Customer or Account)
env['identity.authenticated'] # Boolean
env['identity.source']        # 'advanced', 'basic', or 'redis'
env['identity.metadata']      # Additional metadata
```

**Single Source of Truth:** All application code reads from `env`, never from session

## Authentication Modes

Onetime Secret supports two authentication modes, configured via `AUTHENTICATION_MODE`:

### Basic Mode (Default)

**Configuration:** `AUTHENTICATION_MODE=basic`
**Auth App Status:** Not mounted
**Session Backend:** Redis (shared)
**Routes:** Core app handles `/auth/*` routes
**Use Case:** Simple deployments, single application

**Flow:**
1. User submits credentials to Core app (`/auth/login`)
2. Core controller calls Logic class with `StrategyResult`
3. Logic validates credentials, writes to `session`
4. Redis persists session
5. Future requests use NoAuthStrategy or SessionAuthStrategy

### Advanced Mode

**Configuration:** `AUTHENTICATION_MODE=advanced`
**Auth App Status:** Mounted at `/auth`
**Session Backend:** Redis (shared) + PostgreSQL (Rodauth)
**Routes:** Auth app handles `/auth/*`, Core handles rest
**Use Case:** Multi-tenant, external authentication, compliance requirements

**Flow:**
1. User submits credentials to Auth app (`/auth/login`Rodauth)
2. Rodauth validates credentials, writes to PostgreSQL + session
3. Redis persists session
4. IdentityResolution middleware loads Customer from session
5. Future requests use OnetimeAdvancedStrategy

## Otto Strategies

### Centralized Strategies

**Location:** `lib/onetime/application/auth_strategies.rb`
**Registration:** All applications call `Onetime::Application::AuthStrategies.register_essential(otto)`

All Onetime applications (Web Core, V2 API) use the same centralized strategy implementations:

#### NoAuthStrategy (`auth=noauth`)

```ruby
# Usage in routes files (all apps)
GET / Core::Controllers::Page#index auth=noauth
GET /api/v2/secret/:key V2::Logic::Secrets::ShowSecret response=json auth=noauth

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::NoAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    cust = load_customer_from_session(session) || Onetime::Customer.anonymous

    success(
      session: session,
      user: cust,  # Customer instance or anonymous
      auth_method: 'public',
      metadata: { ip: env['REMOTE_ADDR'], user_agent: env['HTTP_USER_AGENT'] }
    )
  end
end
```

**Access:** Everyone (anonymous or authenticated)
**User:** `Customer.anonymous` or authenticated Customer
**Session Required:** No

#### SessionAuthStrategy (`auth=sessionauth`)

```ruby
# Usage in routes files (all apps)
GET /account Core::Controllers::Account#show auth=authenticated
GET /api/v2/account V2::Logic::Account::GetAccount response=json auth=authenticated

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::SessionAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    return failure('Not authenticated') unless session['authenticated']

    cust = Onetime::Customer.load(session['identity_id'])
    return failure('Customer not found') unless cust

    success(
      session: session,
      user: cust,
      auth_method: 'session',
      metadata: { ip: env['REMOTE_ADDR'], user_agent: env['HTTP_USER_AGENT'] }
    )
  end
end
```

**Access:** Authenticated users only
**User:** Authenticated Customer
**Session Required:** Yes (`session['authenticated'] == true`)

#### ColonelStrategy (`auth=colonel`)

```ruby
# Usage in routes files (all apps)
GET /colonel Core::Controllers::Colonel#dashboard auth=colonel
GET /api/v2/colonel/stats V2::Logic::Colonel::GetColonelStats response=json auth=colonel

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::ColonelStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    return failure('Not authenticated') unless session['authenticated']

    cust = Onetime::Customer.load(session['identity_id'])
    return failure('Colonel role required') unless cust.role?(:colonel)

    success(
      session: session,
      user: cust,
      auth_method: 'colonel',
      metadata: { ip: env['REMOTE_ADDR'], role: 'colonel' }
    )
  end
end
```

**Access:** Users with colonel role only
**User:** Authenticated Customer with `:colonel` role
**Session Required:** Yes + role check

### Application Delegation

**Web Core:** `apps/web/core/auth_strategies.rb`
**V2 API:** `apps/api/v2/auth_strategies.rb`

Both applications delegate to the centralized implementation:

```ruby
# apps/web/core/auth_strategies.rb
module Core::AuthStrategies
  def self.register_essential(otto)
    Onetime::Application::AuthStrategies.register_essential(otto)
  end
end

# apps/api/v2/auth_strategies.rb
module V2::AuthStrategies
  def self.register_essential(otto)
    Onetime::Application::AuthStrategies.register_essential(otto)
  end
end
```

This ensures all applications use identical authentication logic while maintaining clean separation.

## Controllers

### Base Controller Pattern

**Location:** `apps/web/core/controllers/base.rb`

```ruby
module Core::Controllers
  module Base
    # Returns StrategyResult from Otto middleware
    def _strategy_result
      req.env['otto.strategy_result'] || fallback_strategy_result
    end

    # Returns current customer from Otto middleware
    def load_current_customer
      user = req.env['otto.user']
      return user if user.is_a?(Onetime::Customer)
      Onetime::Customer.anonymous
    end

    # Check authentication state
    def authenticated?
      _strategy_result.authenticated?
    end
  end
end
```

**Rules:**
- Read from `req.env['otto.user']` or `req.env['otto.strategy_result']`
- Never read from `session` directly
- Never create `StrategyResult` manually (Otto middleware provides it)

### Example Controller

```ruby
module Core::Controllers
  class Account
    include Base

    def show
      #  Correct - read from env
      customer = req.env['otto.user']

      #  Correct - use helper
      strategy_result = _strategy_result

      # L Wrong - don't read from session
      # customer_id = session['identity_id']  # NEVER DO THIS

      view = Core::Views::Account.new(req, session, customer, locale)
      res.body = view.render
    end
  end
end
```

## Logic Classes

Logic classes handle business rules and are the ONLY code that writes to session.

**Location:** `apps/api/v2/logic/`

### Base Pattern

```ruby
module V2::Logic
  class Base
    def initialize(strategy_result, params = {}, locale = nil)
      @strategy_result = strategy_result
      @sess = strategy_result.session      # Access session through StrategyResult
      @cust = strategy_result.user         # Access user through StrategyResult
      @params = params
      @locale = locale
    end
  end
end
```

### Authentication Logic

**Location:** `apps/api/v2/logic/authentication/`

#### AuthenticateSession

```ruby
class AuthenticateSession < Base
  def process
    # Validate credentials
    cust = find_customer_by_email(@params[:u])
    raise OT::FormError, 'Try again' unless cust.valid_passphrase?(@params[:p])

    #  Correct - write to session via StrategyResult
    @sess['authenticated'] = true
    @sess['identity_id'] = cust.custid
    @sess['email'] = cust.email
    @sess['authenticated_at'] = Time.now.to_i
    @sess['ip_address'] = @strategy_result.metadata[:ip]

    @cust = cust
  end
end
```

#### DestroySession

```ruby
class DestroySession < Base
  def process
    #  Correct - clear session via StrategyResult
    @sess.clear
  end
end
```

### Account Logic

**Location:** `apps/api/v2/logic/account/`

#### CreateAccount

```ruby
class CreateAccount < Base
  def raise_concerns
    #  Correct - check authentication via StrategyResult
    raise OT::FormError, "Already signed up" if @strategy_result.authenticated?
  end

  def process
    # Create customer
    cust = Onetime::Customer.create(email: @params[:email])
    cust.update_passphrase(@params[:password])

    #  Correct - write to session via StrategyResult
    @sess['authenticated'] = true
    @sess['identity_id'] = cust.custid
    @sess['email'] = cust.email
    @sess['authenticated_at'] = Time.now.to_i

    @cust = cust
  end
end
```

**Rules:**
-  Initialize with `StrategyResult`
-  Access session via `@strategy_result.session`
-  Access user via `@strategy_result.user`
-  Write to session on login/logout/registration only
- L Never read from `env` directly (controllers handle that)

## Integration with Rodauth (Advanced Mode)

### Rodauth Configuration

**Location:** `apps/web/auth/config/features/base.rb`

```ruby
module Auth
  class Account < Rodauth::Auth
    configure do
      # Session key must match cookie name
      session_key 'onetime.session'

      # Rodauth writes to session
      # env['rack.session']['account_external_id'] = account.id
      # env['rack.session']['authenticated'] = true
    end
  end
end
```

### Identity Resolution Middleware

**Location:** `lib/onetime/middleware/identity_resolution.rb`

Bridges Rodauth and Otto by reading session and setting env:

```ruby
class IdentityResolution
  def call(env)
    session = env['rack.session']

    # Check Rodauth session (advanced mode)
    if session['account_external_id']
      identity = resolve_from_rodauth(session)
      env['identity.resolved'] = identity
      env['identity.authenticated'] = true
      env['identity.source'] = 'advanced'

    # Check Redis session (basic mode)
    elsif session['authenticated']
      identity = resolve_from_redis(session)
      env['identity.resolved'] = identity
      env['identity.authenticated'] = true
      env['identity.source'] = 'basic'
    end

    @app.call(env)
  end
end
```

**Rules:**
-  Read from `env['rack.session']`
-  Write to `env['identity.*']`
-  Run before Otto's AuthenticationMiddleware

## Testing Patterns

### Controller Tests

```ruby
RSpec.describe Core::Controllers::Account do
  it 'loads authenticated customer from env' do
    # Mock env, not session
    customer = Onetime::Customer.create(email: 'test@example.com')

    get '/account', {}, { 'otto.user' => customer }

    expect(last_response.status).to eq(200)
  end
end
```

### Logic Tests

```ruby
RSpec.describe V2::Logic::Authentication::AuthenticateSession do
  it 'writes authentication to session' do
    strategy_result = Otto::Security::Authentication::StrategyResult.new(
      session: {},
      user: Onetime::Customer.anonymous,
      auth_method: 'public',
      metadata: {}
    )

    logic = described_class.new(strategy_result, { u: 'test@example.com', p: 'password' })
    logic.process

    expect(strategy_result.session['authenticated']).to be true
    expect(strategy_result.session['identity_id']).to eq(customer.custid)
  end
end
```

## Migration from Legacy Patterns

### Anti-Patterns to Avoid

```ruby
# L WRONG - Manual StrategyResult creation
def _strategy_result
  Otto::Security::Authentication::StrategyResult.new(
    session: session,
    user: cust,
    auth_method: 'session',  # Hardcoded - loses semantic meaning
  )
end

# L WRONG - Reading from session in controllers
def show
  customer_id = session['identity_id']  # Don't do this
end

# L WRONG - Using env['onetime.session']
def authenticate(env, requirement)
  session = env['onetime.session']  # Wrong key
end
```

### Correct Patterns

```ruby
#  CORRECT - Use middleware-provided result
def _strategy_result
  req.env['otto.strategy_result']
end

#  CORRECT - Read from env in controllers
def show
  customer = req.env['otto.user']
end

#  CORRECT - Use env['rack.session'] in strategies
def authenticate(env, requirement)
  session = env['rack.session']
end
```

### Current Architecture (As of v2.0)

**Strategy Organization:**
- `lib/onetime/application/auth_strategies.rb` - Centralized strategy implementations and registration
- `apps/web/core/auth_strategies.rb` - Thin delegation wrapper for Web Core
- `apps/api/v2/auth_strategies.rb` - Thin delegation wrapper for V2 API

**Pattern:**
1. All strategy implementations live in `Onetime::Application::AuthStrategies`
2. Application-specific modules (`Core::AuthStrategies`, `V2::AuthStrategies`) delegate to centralized module
3. Each application calls `Onetime::Application::AuthStrategies.register_essential(otto)` in `build_router`
4. Strategies use consistent names: `noauth`, `authenticated`, `colonelsonly`, `basicauth`

**Implementation:**
```ruby
# Centralized (lib/onetime/application/auth_strategies.rb)
module Onetime::Application::AuthStrategies
  def self.register_essential(otto)
    otto.enable_authentication!
    otto.add_auth_strategy('noauth', NoAuthStrategy.new)
    otto.add_auth_strategy('sessionauth', SessionAuthStrategy.new)
    otto.add_auth_strategy('colonelsonly', ColonelStrategy.new)
  end

  class NoAuthStrategy < Otto::Security::AuthStrategy
    # Implementation...
  end
end

# Application wrappers (apps/*/auth_strategies.rb)
module Core::AuthStrategies
  def self.register_essential(otto)
    Onetime::Application::AuthStrategies.register_essential(otto)
  end
end
```

**Benefits:**
- **Single Source of Truth:** One implementation for all applications
- **DRY:** Zero duplication of strategy logic
- **Consistency:** Guaranteed identical behavior across apps
- **Maintainability:** Changes in one place affect all apps
- **Extensibility:** Apps can subclass strategies if needed

## Configuration

### Session Middleware

**Location:** `lib/onetime/application/middleware_stack.rb`

```ruby
builder.use Onetime::Session, {
  expire_after: 86_400,           # 24 hours
  key: 'onetime.session',         # Cookie name
  secure: Onetime.conf.dig('site', 'ssl'),
  httponly: true,
  same_site: :strict,
}
```

### Authentication Mode

**Environment Variable:** `AUTHENTICATION_MODE`
**Values:** `basic` (default), `advanced`
**Config:** `etc/config.yaml`

```yaml
authentication:
  mode: basic  # or 'advanced'
  session:
    expire_after: 86400
    key: onetime.session
```

## Security Considerations

### Session Security

1. **Cookie Flags**
   - `secure: true` in production (HTTPS only)
   - `httponly: true` (no JavaScript access)
   - `same_site: :strict` (CSRF protection)

2. **Session Expiration**
   - Default: 24 hours (`expire_after: 86_400`)
   - Sliding window (extends on activity)

3. **Session Validation**
   - Strategies validate `session['authenticated']`
   - Strategies load and verify customer exists
   - Identity middleware checks session integrity

### Authentication Security

1. **Password Hashing**
   - BCrypt (via `Onetime::Customer#update_passphrase`)
   - Salt automatically applied

2. **API Token Validation**
   - Constant-time comparison
   - Token stored hashed in Redis

3. **Timing Attack Protection**
   - Auth adapters use timing-safe operations
   - Invalid credentials take same time as valid

## Architecture Benefits

### Single Source of Truth

`env` values are authoritative for each request. Session is I/O layer.

### Separation of Concerns

- **Middleware:** Read session -> populate env
- **Controllers:** Read envpass to Logic
- **Logic:** Business rules + write session
- **Middleware:** Persist sessionRedis

### Testability

Mock `env` in tests, not session. Test strategies independently.

### Framework Alignment

Follows Rack conventions, Otto patterns, matches Warden/Devise architecture.

## References

- **Otto Framework:** https://github.com/delano/otto
- **Otto v2.0.0-pre2 Migration Guide:** `.serena/memories/otto-v2.0.0-pre2-migrating-guide.md`
- **Otto Session Prescription:** `.serena/memories/2510/otto-auth-session-prescription.md`
- **Rack Session Specification:** https://github.com/rack/rack/blob/main/SPEC.rdoc
- **Rodauth Documentation:** https://rodauth.jeremyevans.net/
