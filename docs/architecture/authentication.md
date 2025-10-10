---
labels: authstrategies
---
# Authentication Architecture

**Last Updated:** 2025-10-09
**Framework:** Otto v2.0.0-pre2
**Session Store:** Redis via Rack::Session

## Overview

Onetime Secret uses Otto's post-routing authentication pattern following standard Rack conventions. Authentication strategies execute after route matching but before controller execution, providing access to both route requirements and session state.

## Architecture Pattern: Post-Routing Authentication

```
1. Request arrives

2. Session Middleware (Rack::Session::Abstract::Persisted)
   Location: lib/onetime/application/middleware_stack.rb
   Class: Onetime::Session (wraps Rack::Session::Redis)
   Sets: env['rack.session']
   Cookie: 'onetime.session'

3. Otto Router
   Location: Otto gem (lib/otto/core/router.rb)
   - Matches route based on path and method
   - Sets env['otto.route_definition']

4. Route Handler Factory
   Location: Otto gem (lib/otto/route_handlers/factory.rb)
   - Creates appropriate handler (Instance, Class, Logic)
   - Wraps with RouteAuthWrapper if auth_requirement exists

5. RouteAuthWrapper (Authentication Enforcement)
   Location: Otto gem (lib/otto/security/authentication/route_auth_wrapper.rb)
   - Reads auth_requirement from route_definition
   - Executes matching auth strategy
   - Strategy reads env['rack.session'] and route_definition
   - Creates StrategyResult
   - Sets env['otto.strategy_result'], env['otto.user'], env['otto.user_context']
   - On success: calls wrapped handler
   - On failure: returns 401/redirect

6. Application Controllers
   Location: apps/web/core/controllers/*, apps/api/v2/controllers/*
   Pattern: req.env['otto.user'], req.env['otto.strategy_result']
   - Read from env, never from session directly

7. Logic Classes (on auth state changes)
   Location: apps/api/v2/logic/authentication/*, apps/api/v2/logic/account/*
   Pattern: @strategy_result.session['key'] = value
   - Write to session via StrategyResult.session attribute
   - Only on login/logout/registration

8. Session Middleware persists to Redis
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
session['authenticated']      = true               # Boolean flag
session['identity_id']        = customer.custid    # Customer ID
session['email']              = customer.email     # Email
session['authenticated_at']   = Time.now.to_i      # Login timestamp
session['ip_address']         = ip                 # Client IP
session['user_agent']         = user_agent         # Client UA
session['locale']             = locale             # User locale

# Advanced mode adds (written by Rodauth)
# Location: apps/web/auth/config/features/*.rb
session['account_external_id'] = account.id        # Rodauth external_id
session['advanced_account_id'] = account.id        # Rodauth account ID
```

**Write Pattern:** Only authentication Logic classes write to session
**Read Pattern:** Only auth strategies read from session (controllers never read directly)

### Environment: Request-Scoped State

Otto's RouteAuthWrapper reads from `env['rack.session']` once per request and populates `env`:

```ruby
# Set by Otto's RouteAuthWrapper
env['otto.strategy_result']   # StrategyResult object
env['otto.user']              # User object (Customer instance)
env['otto.user_context']      # User context hash
env['otto.route_definition']  # Current route definition (set by router)
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
1. User submits credentials to Auth app (`/auth/login` via Rodauth)
2. Rodauth validates credentials, writes to PostgreSQL + session
3. Redis persists session
4. Future requests use auth strategies to read session
5. Strategies load Customer from session data

## Otto Strategies

### Strategy Architecture

**Centralized Implementation:** `lib/onetime/application/auth_strategies.rb`
**Application Wrappers:**
- Web Core: `apps/web/core/auth_strategies.rb`
- V2 API: `apps/api/v2/auth_strategies.rb`

**Pattern:** Application wrappers delegate to centralized `Onetime::Application::AuthStrategies` module, which provides shared strategy implementations used by all applications.

**Registration:** Applications call `Core::AuthStrategies.register_essential(otto)` or `V2::AuthStrategies.register_essential(otto)`, which internally delegate to the centralized module.

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
      auth_method: 'noauth',
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
GET /account Core::Controllers::Account#show auth=sessionauth
GET /api/v2/account V2::Logic::Account::GetAccount response=json auth=sessionauth

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::SessionAuthStrategy < BaseSessionAuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated') unless session['authenticated']

    cust = Onetime::Customer.load(session['identity_id'])
    return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

    success(
      session: session,
      user: cust,
      auth_method: 'sessionauth',
      metadata: { ip: env['REMOTE_ADDR'], user_agent: env['HTTP_USER_AGENT'] }
    )
  end
end
```

**Access:** Authenticated users only
**User:** Authenticated Customer
**Session Required:** Yes (`session['authenticated'] == true`)

#### ColonelStrategy (`auth=colonelsonly`)

```ruby
# Usage in routes files (all apps)
GET /colonel Core::Controllers::Colonel#dashboard auth=colonelsonly
GET /api/v2/colonel/stats V2::Logic::Colonel::GetColonelStats response=json auth=colonelsonly

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::ColonelStrategy < BaseSessionAuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated') unless session['authenticated']

    cust = Onetime::Customer.load(session['identity_id'])
    return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust
    return failure('[ROLE_COLONEL_REQUIRED] Colonel role required') unless cust.role?(:colonel)

    success(
      session: session,
      user: cust,
      auth_method: 'colonel',
      metadata: { ip: env['REMOTE_ADDR'], user_agent: env['HTTP_USER_AGENT'], role: 'colonel' }
    )
  end
end
```

**Access:** Users with colonel role only
**User:** Authenticated Customer with `:colonel` role
**Session Required:** Yes + role check

#### BasicAuthStrategy (`auth=basicauth`)

```ruby
# Usage in routes files (V2 API only)
GET /api/v2/status V2::Controllers::Status#show auth=basicauth

# Strategy implementation (lib/onetime/application/auth_strategies.rb)
class Onetime::Application::AuthStrategies::BasicAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    # Extract and validate HTTP Basic Auth credentials
    auth_header = env['HTTP_AUTHORIZATION']
    return failure('[AUTH_HEADER_MISSING] No authorization header') unless auth_header

    # Parse and validate credentials
    username, apikey = parse_basic_auth(auth_header)
    cust = Onetime::Customer.load(username)

    # Security: Uses constant-time comparison for both username and API key
    # to prevent timing attacks that could enumerate valid usernames
    valid_apikey = if cust
      cust.valid_apikey?(apikey)
    else
      # Perform same constant-time comparison with dummy value
      # to prevent username enumeration via timing
      Rack::Utils.secure_compare(dummy_hash, Digest::SHA256.hexdigest(apikey))
      false  # Always fail for non-existent users
    end

    return failure('[CREDENTIALS_INVALID] Invalid credentials') unless valid_apikey

    success(
      session: {},  # No session for Basic auth (stateless)
      user: cust,
      auth_method: 'basicauth',
      metadata: { ip: env['REMOTE_ADDR'], user_agent: env['HTTP_USER_AGENT'], auth_type: 'basic' }
    )
  end
end
```

**Access:** Valid API credentials via Authorization header
**User:** Customer associated with API credentials
**Session Required:** No (stateless)
**Security:** Constant-time comparison prevents timing attacks

### Application Delegation Pattern

**Web Core:** `apps/web/core/auth_strategies.rb`
**V2 API:** `apps/api/v2/auth_strategies.rb`

Both applications delegate to centralized implementations:

```ruby
# apps/web/core/auth_strategies.rb
module Core::AuthStrategies
  def self.register_essential(otto)
    # Register strategies from centralized module
    otto.add_auth_strategy('noauth',
      Onetime::Application::AuthStrategies::NoAuthStrategy.new)
    otto.add_auth_strategy('sessionauth',
      Onetime::Application::AuthStrategies::SessionAuthStrategy.new)
    otto.add_auth_strategy('colonelsonly',
      Onetime::Application::AuthStrategies::ColonelStrategy.new)
  end
end

# apps/api/v2/auth_strategies.rb
module V2::AuthStrategies
  def self.register_essential(otto)
    # V2 API registers additional BasicAuth strategy
    otto.add_auth_strategy('noauth',
      Onetime::Application::AuthStrategies::NoAuthStrategy.new)
    otto.add_auth_strategy('sessionauth',
      Onetime::Application::AuthStrategies::SessionAuthStrategy.new)
    otto.add_auth_strategy('basicauth',
      Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
  end
end
```

**Benefits:**
- **Single Source of Truth:** All strategy implementations in `lib/onetime/application/auth_strategies.rb`
- **Consistency:** Identical authentication logic across applications
- **Flexibility:** Applications can selectively register strategies (e.g., BasicAuth only in V2 API)
- **Maintainability:** Changes propagate to all applications automatically

## Controllers

### Base Controller Pattern

**Location:** `apps/web/core/controllers/base.rb`

```ruby
module Core::Controllers
  module Base
    # Returns StrategyResult from Otto's RouteAuthWrapper
    #
    # RouteAuthWrapper (post-routing authentication) executes the strategy and sets
    # req.env['otto.strategy_result'] before the controller handler runs.
    def _strategy_result
      req.env['otto.strategy_result']
    end

    # Note: Otto v2.0.0-pre2 Migration
    # The fallback pattern below handles cases where Otto's authentication
    # middleware may not have run or set the strategy result properly.

    # Returns current customer from Otto's RouteAuthWrapper
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
- ✅ **Correct:** Read from `req.env['otto.user']` or `req.env['otto.strategy_result']`
- ✅ **Correct:** Use `_strategy_result` helper which reads from RouteAuthWrapper
- ❌ **Wrong:** Never read from `session` directly in controllers
- ❌ **Wrong:** Never create `StrategyResult` manually

### Example Controller

```ruby
module Core::Controllers
  class Account
    include Base

    def show
      # ✅ Correct - read from env
      customer = req.env['otto.user']

      # ✅ Correct - use helper
      strategy_result = _strategy_result

      # ❌ Wrong - don't read from session
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

    # ✅ Correct - write to session via StrategyResult
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
    # ✅ Correct - clear session via StrategyResult
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
    # ✅ Security: Check if user already authenticated via StrategyResult
    raise OT::FormError, "You're already signed up" if @strategy_result.authenticated?

    # ✅ Security: Prevent duplicate accounts
    raise_form_error 'Please try another email address' if Onetime::Customer.exists?(email)

    # ✅ Security: Validate email format
    raise_form_error 'Is that a valid email address?' unless valid_email?(email)

    # ✅ Security: Enforce minimum password length
    raise_form_error 'Password is too short' unless password.size >= 6

    # ✅ Security: Bot detection via honeypot field
    return if skill.empty?
    raise OT::Redirect.new('/?s=1')
  end

  def process
    # Create customer
    cust = Onetime::Customer.create(email: email)
    cust.update_passphrase(password)

    # Set role (colonel if in config, otherwise customer)
    colonels = OT.conf.dig('site', 'authentication', 'colonels')
    cust.role = colonels&.member?(cust.custid) ? 'colonel' : 'customer'
    cust.planid = planid
    cust.verified = autoverify.to_s
    cust.save

    # ✅ Security: Don't auto-authenticate on signup
    @sess['success_message'] = if autoverify
      'Account created. Please sign in.'
    else
      "Verification email sent to #{cust.custid}."
    end

    @cust = cust
  end
end
```

**Rules:**
- ✅ Initialize with `StrategyResult`
- ✅ Access session via `@strategy_result.session`
- ✅ Access user via `@strategy_result.user`
- ✅ Write to session on login/logout only (not on registration)
- ❌ Never read from `env` directly (controllers handle that)

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
- ✅ Read from `env['rack.session']`
- ✅ Write to `env['identity.*']`
- ✅ Run before Otto's AuthenticationMiddleware

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
      auth_method: 'noauth',
      metadata: {}
    )

    logic = described_class.new(strategy_result, { u: 'test@example.com', p: 'password' })
    logic.process

    expect(strategy_result.session['authenticated']).to be true
    expect(strategy_result.session['identity_id']).to eq(customer.custid)
  end
end
```

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
   - Failed authentication returns 401 or redirect

### Authentication Security

1. **Password Hashing**
   - BCrypt (via `Onetime::Customer#update_passphrase`)
   - Salt automatically applied

2. **API Token Validation**
   - Constant-time comparison
   - Token stored hashed in Redis

3. **Timing Attack Protection**
   - Auth strategies use timing-safe operations
   - Invalid credentials take same time as valid

## Architecture Benefits

### Post-Routing Authentication

Authentication happens AFTER routing but BEFORE handler execution:
- **Strategies have route context:** Know which auth requirement to enforce
- **Strategies have session access:** Can read/write authentication state
- **No chicken-and-egg problem:** Route definition available when strategy executes
- **Clean separation:** Routing → Authentication → Handler

### Single Source of Truth

`env` values are authoritative for each request. Session is I/O layer.

### Separation of Concerns

- **Routing:** Otto router matches routes
- **Authentication:** RouteAuthWrapper enforces auth requirements
- **Controllers:** Read from env, pass to Logic
- **Logic:** Business rules + write session
- **Middleware:** Persist session to Redis

### Testability

Mock `env` in tests, not session. Test strategies independently.

### Framework Alignment

Otto's design aligns with OneTime Secret's request-response cycle, ensuring authentication decisions are made with full route context.

## Migration Notes

### Otto v2.0.0-pre2 Changes

The following changes were made during the Otto v2.0.0-pre2 migration:

- **Removed Methods**: The `.success?` and `.failure?` methods from `StrategyResult` are no longer available
- **Fallback Pattern**: Added fallback handling in `load_current_customer` for cases where Otto's authentication middleware doesn't set `otto.user`
- **Strategy Result Access**: Direct access to strategy results through `req.env['otto.strategy_result']` remains unchanged

## References

- **Otto Framework:** https://github.com/delano/otto
- **Otto v2.0.0-pre2 Migration Guide:** `.serena/memories/otto-v2.0.0-pre2-migrating-guide.md`
- **Rack Session Specification:** https://github.com/rack/rack/blob/main/SPEC.rdoc
- **Rodauth Documentation:** https://rodauth.jeremyevans.net/
