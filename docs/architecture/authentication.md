---
labels: authstrategies
---
# Authentication Architecture

**Last Updated:** 2025-10-10
**Framework:** Otto v2.0.0-pre2 + Rodauth 2.x
**Session Store:** Redis via Rack::Session
**Authentication Modes:** Basic (default) | Advanced (Rodauth)

## Overview

Onetime Secret supports dual authentication modes with unified session management:

- **Basic Mode**: Simple Redis-only authentication for single deployments
- **Advanced Mode**: Rodauth integration with PostgreSQL for enterprise features (MFA, account verification, password policies)

Both modes share the same session cookie (`onetime.session`) and Otto authentication strategies, enabling seamless mode switching without data migration.

## Architecture Pattern: Post-Routing Authentication

### Request Flow (Both Modes)

1. **Request arrives**

2. **Session Middleware** (`Rack::Session::Abstract::PersistedSecure`)
   - **Location**: `lib/onetime/application/middleware_stack.rb`
   - **Class**: `Onetime::Session` (extends `Rack::Session::Abstract::PersistedSecure`)
   - **Backend**: `Familia::StringKey` (Redis)
   - **Sets**: `env['rack.session']`
   - **Cookie**: `'onetime.session'`
   - **Security**: HMAC verification, SessionId objects

3. **Identity Resolution Middleware**
   - **Location**: `lib/onetime/middleware/identity_resolution.rb`
   - Reads session data
   - Determines auth mode (basic/advanced)
   - Populates `env['identity.*']` keys

4. **Otto Router**
   - **Location**: Otto gem (`lib/otto/core/router.rb`)
   - Matches route based on path and method
   - Sets `env['otto.route_definition']`

5. **RouteAuthWrapper** (Authentication Enforcement)
   - **Location**: Otto gem (`lib/otto/security/authentication/route_auth_wrapper.rb`)
   - Reads `auth_requirement` from route definition
   - Executes matching auth strategy → Creates `StrategyResult`
   - Sets: `env['otto.strategy_result']`, `env['otto.user']`
   - On success: calls handler | On failure: returns 401/redirect

6. **Application Controllers**
   - **Location**: `apps/web/core/controllers/*`, `apps/api/v2/logic/*`
   - **Pattern**: `req.env['otto.user']`, `req.env['otto.strategy_result']`
   - Read from env, never from session directly

7. **Logic Classes** (on auth state changes)
   - **Location**: `apps/api/v2/logic/authentication/*`, `apps/api/v2/logic/account/*`
   - **Pattern**: `@strategy_result.session['key'] = value`
   - Write to session via `StrategyResult.session` attribute
   - Only on login/logout/registration

8. **Session Middleware persists to Redis**
   - Same middleware as step 2

## Session vs Environment

### Session: Persistence Layer (Redis)

**Purpose**: Long-term storage across requests
**Access**: Write-only from Logic classes
**Implementation**: `Onetime::Session` extends `Rack::Session::Abstract::PersistedSecure`

```ruby
# Session lookup (lib/onetime/session.rb)
def find_session(request, sid)
  # Validate session ID format
  # Validates session ID format
  # Verifies HMAC integrity
  # Returns: [sid, session_data] or [new_sid, {}]
end
```

### Environment: Request-Scoped State

**Purpose**: Request-specific authentication state
**Access**: Read-only from Controllers

| Environment Key | Set By | Contains |
|----------------|--------|----------|
| `identity.resolved` | Identity Middleware | Customer or nil |
| `identity.source` | Identity Middleware | 'basic', 'advanced', or 'anonymous' |
| `identity.authenticated` | Identity Middleware | Boolean |
| `identity.metadata` | Identity Middleware | Hash with customer_id, external_id |
| `otto.user` | RouteAuthWrapper | Authenticated Customer |
| `otto.strategy_result` | RouteAuthWrapper | StrategyResult object |
| `otto.route_definition` | Otto Router | Current route definition |

## Authentication Modes

### Basic Mode (Default)

**Configuration**: `AUTHENTICATION_MODE=basic`

**Stack**:
- Core app handles `/auth/*` routes
- V2 Logic classes manage authentication
- Redis session storage only
- No external database required

**Use Cases**:
- Single deployments
- Development environments
- Simple authentication requirements

### Advanced Mode

**Configuration**: `AUTHENTICATION_MODE=advanced`

**Stack**:
- Auth app (Roda + Rodauth) mounted at `/auth`
- PostgreSQL for Rodauth account storage
- Redis for unified session management
- Otto strategies bridge Rodauth → Otto

**Session Keys Comparison**:

| Session Key | Basic Mode | Advanced Mode | Purpose |
|------------|------------|---------------|---------|
| `authenticated` | ✓ | ✓ | Auth state flag |
| `identity_id` | ✓ | ✓ | Customer ID |
| `email` | ✓ | ✓ | User email |
| `authenticated_at` | ✓ | ✓ | Timestamp |
| `ip_address` | ✓ | ✓ | Client IP |
| `user_agent` | ✓ | ✓ | Browser info |
| `locale` | ✓ | ✓ | User locale |
| `account_external_id` | - | ✓ | Rodauth account link |
| `advanced_account_id` | - | ✓ | Rodauth account ID |

**Application
 Architecture**:
```ruby
# apps/web/auth/application.rb
module Auth
  class Application < Onetime::Application::Base
    @uri_prefix = '/auth'.freeze

    def build_router
      Auth::Router  # Roda app with Rodauth plugin
    end
  end
end

# apps/web/auth/router.rb
class Auth::Router < Roda
  plugin :rodauth do
    instance_eval(&Auth::Config.configure)
  end

  route do |r|
    r.is { { message: 'Auth
 Service', version: Onetime::VERSION } }
    r.rodauth        # Handles /login, /logout, /create-account, etc.
    handle_custom_routes(r)
  end
end
```

**Rodauth Configuration**:
```ruby
# apps/web/auth/config.rb
module Auth::Config
  # Features: json, login, logout, create_account, change_password, reset_password
  # Integration points: create_otto_customer, sync_session_with_otto
  # Hooks: after_create_account, after_login
  # Session key: 'onetime.session' (shared with basic mode)
end
```







**Use Cases**:
- Multi-tenant deployments
- Compliance requirements (audit logs, password policies)
- Advanced features (MFA, WebAuthn, account verification)


## Otto Authentication Strategies

Strategies are centralized in `lib/onetime/application/auth_strategies.rb` and shared across all applications.

### NoAuthStrategy (`auth=noauth`) - Complete Reference

**Access**: Everyone (anonymous or authenticated)
**User**: `nil` (anonymous) or `Customer` (authenticated)

```ruby
class NoAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    cust = load_customer_from_session(session) || Onetime::Customer.anonymous

    success(
      session: session,
      user: cust.anonymous? ? nil : cust,  # nil for anonymous users
      auth_method: 'noauth',
      metadata: build_metadata(env)
    )
  end

  private

  def load_customer_from_session(session)
    return nil unless session && session['authenticated'] == true
    return nil if session['identity_id'].to_s.empty?

    Onetime::Customer.load(session['identity_id'])
  end

  def build_metadata(env, additional = {})
    {
      ip: env['REMOTE_ADDR'],
      user_agent: env['HTTP_USER_AGENT'],
      timestamp: Time.now.to_i
    }.merge(additional)
  end
end

# Routes using this strategy:
GET / Core::Controllers::Page#index auth=noauth
GET /api/v2/secret/:key V2::Logic::Secrets::ShowSecret auth=noauth
```

### SessionAuthStrategy (`auth=sessionauth`)

**Access**: Authenticated users only
**User**: Authenticated `Customer`

**Key Differences from NoAuthStrategy**:
- **Strict authentication check**: `session['authenticated'] == true` or fail
- **Required identity**: Must have valid `identity_id` and loadable customer
- **No anonymous fallback**: Returns failure instead of anonymous user

```ruby
class SessionAuthStrategy < BaseSessionAuthStrategy
  def authenticate(env, _requirement)
    # Core validation: session['authenticated'] == true
    # Returns: failure or success with Customer object
  end
end

# Routes using this strategy:
GET /account Core::Controllers::Account#show auth=sessionauth
GET /api/v2/account V2::Logic::Account::GetAccount auth=sessionauth
```

### ColonelStrategy (`auth=colonelsonly`)

**Access**: Users with `:colonel` role
**User**: Authenticated `Customer` with admin role

Extends `SessionAuthStrategy` with `role?(:colonel)` check.

### BasicAuthStrategy (`auth=basicauth`)

**Access**: Valid API credentials via HTTP Basic Auth
**User**: `Customer` (stateless, no session)

**Key Differences from Session-based Strategies**:
- **Stateless**: No session dependency, reads from HTTP headers
- **HTTP Basic Auth**: Parses `Authorization: Basic <encoded>` header
- **Empty session**: Returns `session: {}` since no session persistence needed
- **Timing attack protection**: Constant-time comparison with dummy hash

```ruby
class BasicAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    # Reads: HTTP Authorization header
    # Validates: Basic auth credentials with timing attack prevention
    # Returns: success with empty session (stateless)
  end
end
```

# Routes using this strategy:
GET /api/v2/status V2::Controllers::Status#show auth=basicauth
```
### Strategy Comparison

| Strategy | Auth Check | State | Session | Use Case |
|----------|-----------|-------|---------|----------|
| `noauth` | None | Stateless | Read-only | Public endpoints |
| `sessionauth` | `session['authenticated']` | Stateful | Read/Write | Web UI |
| `colonelsonly` | `sessionauth` + `:colonel` role | Stateful | Read/Write | Admin UI |
| `basicauth` | HTTP Basic Auth | Stateless | Empty `{}` | API endpoints |

### Application Registration

| Application | Registered Strategies | Purpose |
|------------|----------------------|---------|
| Core | `noauth`, `sessionauth`, `colonelsonly` | Web UI routes |
| V2 | `noauth`, `sessionauth`, `basicauth` | API endpoints |

## Controllers and Logic

### Base Controller Pattern

Controllers read authentication state from `env`, never from session:

```ruby
# apps/web/core/controllers/base.rb
module Core::Controllers
  module Base
    # Gets the strategy result from Otto
    def _strategy_result
      req.env['otto.strategy_result']
    end

    # Loads current customer from Otto auth result
    def load_current_customer
      # Try Otto auth result first (set by auth middleware)
      if req.env['otto.user']
        user = req.env['otto.user']
        return user if user.is_a?(Onetime::Customer)
      end

      # Fall back to anonymous
      Onetime::Customer.anonymous
    end

    # Checks if request is authenticated
    def authenticated?
      _strategy_result&.authenticated?
    end
  end
end
```

### Example Controller

```ruby
module Core::Controllers
  class Account
    include Base

    def show
      customer = req.env['otto.user']           # ✅ Correct
      strategy_result = _strategy_result         # ✅ Correct
      # customer_id = session['identity_id']    # ❌ Wrong - never read session

      view = Core::Views::Account.new(req, session, customer, locale)
      res.body = view.render
    end
  end
end
```

### Logic Base Pattern

```ruby
module V2::Logic
  class Base
    def initialize(strategy_result, params = {}, locale = nil)
      @strategy_result = strategy_result
      @sess = strategy_result.session    # Access session via StrategyResult
      @cust = strategy_result.user
      @params = params
      @locale = locale
    end
  end
end
```

### Session Write Pattern

Logic classes are the **only** code that writes to session. All authentication logic follows this pattern:

```ruby
class AuthenticateSession < Base
  def process
    cust = find_customer_by_email(@params[:u])
    raise OT::FormError unless cust.valid_passphrase?(@params[:p])

    # Standard authentication session write
    @sess['authenticated'] = true
    @sess['identity_id'] = cust.custid
    @sess['email'] = cust.email
    @sess['authenticated_at'] = Time.now.to_i
    @sess['ip_address'] = @strategy_result.metadata[:ip]
    @sess['user_agent'] = @strategy_result.metadata[:user_agent]
  end
end
```

### Authentication Logic Classes

#### AuthenticateSession
- **Purpose**: Log in existing user
- **Session Fields**: `authenticated`, `identity_id`, `email`, `authenticated_at`, `ip_address`, `user_agent`

#### CreateAccount
- **Purpose**: Create new account and log in
- **Session Fields**: `authenticated`, `identity_id`, `email`, `authenticated_at`

#### DestroySession
- **Purpose**: Log out user
- **Session Fields**: Clears all fields via `@sess.clear`

#### UpdateAccount
- **Purpose**: Modify account settings
- **Session Fields**: `email` (if changed)

## Integration with Rodauth (Advanced Mode)

### Identity Resolution Middleware

```ruby
class IdentityResolution
  def call(env)
    # Resolves identity based on auth mode
    # Sets env['identity.*'] keys
    # Delegates to @app
  end

  private
  # Key decisions:
  # - Check session['authenticated'] == true
  # - Advanced mode: lookup via session['account_external_id']
  # - Basic mode: lookup via session['identity_id']
  # - Returns identity hash with user, source, authenticated, metadata
end
```

## Testing Patterns

### Test Environment Requirements

Both authentication modes require Redis/Valkey for session storage and data persistence.

**Required Services**:
- **Redis/Valkey**: Session storage, customer data, secrets
  ```bash
  # Start test database (port 2121)
  pnpm run test:database:start

  # Check status
  pnpm run test:database:status

  # Stop when done
  pnpm run test:database:stop
  ```

**Optional Services** (for password reset testing):
- **Mailpit**: SMTP server for email delivery in dev/test
  - Default: `localhost:1025`
  - Environment: `MAILPIT_SMTP_HOST`, `MAILPIT_SMTP_PORT`

**Test Commands**:
```bash
# Basic mode integration tests (Tryouts)
AUTHENTICATION_MODE=basic FAMILIA_DEBUG=0 bundle exec try --agent try/integration/authentication/dual_mode_try.rb

# Advanced mode integration tests (Tryouts)
FAMILIA_DEBUG=0 bundle exec try --agent try/integration/authentication/advanced_mode_try.rb

# Advanced mode integration tests (RSpec)
AUTHENTICATION_MODE=advanced bundle exec rspec spec/integration/advanced_auth_mode_spec.rb

# Debug specific test failures
bundle exec try --verbose --fails --stack try/integration/authentication/dual_mode_try.rb:169-180
```

### Controller Tests

**Pattern**: Mock Otto environment variables to simulate authenticated/anonymous states

**Key Assertions**:
- Controller reads from `env['otto.user']` (not session directly)
- Authenticated routes return expected status codes
- Anonymous users are handled appropriately
- Strategy result is accessible via `_strategy_result`

**Test Approach**: Set `env['otto.user']` and `env['otto.strategy_result']` to simulate different authentication states

### Logic Tests

**Pattern**: Create `StrategyResult` objects with session state, test session mutations

**Key Assertions**:
- Logic writes correct session keys after authentication
- Session is cleared on logout
- Customer objects are properly loaded/created
- Error conditions raise appropriate exceptions

**Test Approach**: Initialize Logic classes with `StrategyResult` objects, verify session changes via `strategy_result.session`


## Configuration

### Session Middleware

- **Class**: `Onetime::Session`
- **Cookie**: `onetime.session`
- **Security flags**: `secure`, `httponly`, `same_site: :strict`
- **Backend**: Redis via HMAC-signed storage

### Authentication Mode

**Environment Variables**:
- `AUTHENTICATION_MODE`: `basic` or `advanced`
- `HMAC_SECRET`: Session integrity
- `DATABASE_URL`: PostgreSQL (advanced mode only)

**Configuration** (`etc/config.yaml`):
- `authentication.mode`: Authentication strategy
- `authentication.session`: Session parameters
- `authentication.colonels`: Admin users list

### Troubleshooting

**Common Test Failures**:

1. **Connection refused / Redis errors**
   - **Symptom**: Tests fail with "Connection refused" or Redis connection errors
   - **Solution**: Start test database with `pnpm run test:database:start`
   - **Verify**: `pnpm run test:database:status` should return `PONG`

2. **Password reset returns 500**
   - **Symptom**: `/auth/reset-password` endpoint returns 500 Internal Server Error
   - **Cause**: Missing Redis connection or undefined instance variables (e.g., `@custid` when only `@objid` is set)
   - **Solution**: Ensure Redis is running; verify Logic classes use consistent variable names in `process_params`, `raise_concerns`, and `process` methods
   - **Fixed in**: apps/api/v2/logic/authentication/reset_password_request.rb (changed `@custid` → `@objid`)

3. **JSON responses return HTML**
   - **Symptom**: Tests expect JSON but receive `text/html` responses
   - **Cause**: Route configuration missing `response=json` or controller error before JSON rendering
   - **Solution**: Verify route definition includes `:response => 'json'` and check for exceptions in controller

4. **Session not persisting across requests**
   - **Symptom**: Login succeeds but subsequent requests show unauthenticated
   - **Cause**: Test helper not preserving cookies between requests
   - **Solution**: Use `@test.last_response.headers['Set-Cookie']` in subsequent requests or verify `Rack::Test` session handling

5. **Undefined constant errors in Advanced mode**
   - **Symptom**: `NameError: uninitialized constant` for Rodauth classes
   - **Cause**: Auth application not loaded or DATABASE_URL not configured
   - **Solution**: Set `AUTHENTICATION_MODE=advanced` and verify PostgreSQL connection

## Security Considerations

### Session Security

- **Cookie Security**: `secure`, `httponly`, `same_site: :strict`
- **Session Protection**: HMAC integrity, 24-hour expiration, Redis storage
- **No sensitive data in cookies** - only session ID

### Authentication Security

- **Password Hashing**: BCrypt with automatic salt generation
- **API Key Separation**: Distinct from passwords, constant-time comparison
- **Rate Limiting**: Protection on authentication endpoints
- **Timing Attack Prevention**: Consistent execution time for all attempts

## Architecture Benefits

- **Post-Routing**: Full route context available during authentication
- **Single Source of Truth**: Redis session, clear read/write boundaries
- **Separation of Concerns**: Middleware → Identity → Strategies → Controllers → Logic
- **Testability**: Mockable environment, isolated components, no global state
- **Framework Alignment**: Otto + Rodauth + Rack work in harmony

## References

- **Otto Framework**: https://github.com/delano/otto
- **Rodauth Documentation**: https://rodauth.jeremyevans.net/
- **Rack Session Specification**: https://github.com/rack/rack/blob/main/SPEC.rdoc
- **Implementation Details**: `.serena/memories/otto-v2.0.0-pre2-migrating-guide.md`
