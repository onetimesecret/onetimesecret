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
   - **Class**: `Onetime::MinimalSession` (extends `Rack::Session::Abstract::PersistedSecure`)
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
   - Reads `auth_requirement` from `route_definition`
   - Executes matching auth strategy
   - Strategy reads `env['rack.session']` and `route_definition`
   - Creates `StrategyResult`
   - Sets `env['otto.strategy_result']`, `env['otto.user']`, `env['otto.user_context']`
   - **On success**: calls wrapped handler
   - **On failure**: returns 401/redirect

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
**Implementation**: `Onetime::MinimalSession` extends `Rack::Session::Abstract::PersistedSecure`

```ruby
# Session lookup (lib/onetime/minimal_session.rb)
def find_session(request, sid)
  sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

  unless sid_string && valid_session_id?(sid_string)
    return [generate_sid, {}]
  end

  stringkey = get_stringkey(sid_string)
  stored_data = stringkey.value if stringkey

  # Verify HMAC before deserializing
  data, hmac = stored_data.split('--', 2)
  unless hmac && valid_hmac?(data, hmac)
    return [generate_sid, {}]  # Session tampered
  end

  session_data = Familia::JsonSerializer.parse(Base64.decode64(data))
  [sid, session_data]
end
```

### Environment: Request-Scoped State

**Purpose**: Request-specific authentication state
**Access**: Read-only from Controllers
**Keys**:

```ruby
# Set by Identity Resolution Middleware
env['identity.resolved']      # Customer object or nil
env['identity.source']        # 'basic', 'advanced', or 'anonymous'
env['identity.authenticated'] # Boolean
env['identity.metadata']      # Hash with customer_id, external_id, etc.

# Set by Otto RouteAuthWrapper
env['otto.user']              # Customer object (authenticated) or nil
env['otto.strategy_result']   # StrategyResult object with session, user, metadata
env['otto.route_definition']  # Current route definition
```

## Authentication Modes

### Basic Mode (Default)

**Configuration**: `AUTHENTICATION_MODE=basic`

**Stack**:
- Core app handles `/auth/*` routes
- V2 Logic classes manage authentication
- Redis
 session storage only
- No external database required

**Session Keys**:
```ruby
session['authenticated']      = true
session['identity_id']        = customer.custid
session['email']              = customer.email
session['authenticated_at']   = Time.now.to_i
session['ip_address']         = request.ip
session['user_agent']         = request.user_agent
session['locale']             = 'en'
```

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

**Session Keys** (extends Basic Mode):
```ruby
# Basic mode keys plus:
session['account_external_id'] = account.id  # Rodauth account external_id
session['advanced_account_id'] = account.id  # Rodauth account ID
```

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
    instance_eval(&Auth::Config::RodauthMain.configure)
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
# apps/web/auth/config/rodauth_main.rb
module Auth::Config::RodauthMain
  def self.configure
    proc do
      # Database and features
      db Auth::Config::Database.connection
      enable :json, :login, :logout, :create_account, :close_account,
             :change_password, :reset_password, :verify_account

      # Session integration
      session_key 'onetime.session'

      # JSON-only responses for Vue frontend
      json_response_success_key :success
      json_response_error_key :error
      only_json? true

      # Otto integration methods
      def create_otto_customer
        customer = Onetime::Customer.create(account[:email])
        db[:accounts].where(id: account_id).update(external_id: customer.extid)
        customer
      end

      def sync_session_with_otto(customer = nil)
        session['authenticated'] = true
        session['authenticated_at'] = Time.now.to_i
        session['identity_id'] = customer.custid if customer
        session['account_external_id'] = account[:external_id]
      end

      # Lifecycle hooks
      after_create_account { create_otto_customer }
      after_login { sync_session_with_otto }
    end
  end
end
```

**Use Cases**:
- Multi-tenant deployments
- Compliance requirements (audit logs, password policies)
- Advanced features (MFA, WebAuthn, account verification)

## Otto Authentication Strategies


Strategies are centralized in `lib/onetime/application/auth_strategies.rb` and shared across all applications.

### NoAuthStrategy (`auth=noauth`)

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
end

# Routes using this strategy:
GET / Core::Controllers::Page#index auth=noauth
GET /api/v2/secret/:key V2::Logic::Secrets::ShowSecret auth=noauth
```

### SessionAuthStrategy (`auth=sessionauth`)

**Access**: Authenticated users only
**User**: Authenticated `Customer`

```ruby
class SessionAuthStrategy < BaseSessionAuthStrategy
  def authenticate(env, _requirement)
    session = env['rack.session']
    return failure('[SESSION_MISSING] No session') unless session

    unless session['authenticated'] == true
      return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated')
    end

    identity_id = session['identity_id']
    return failure('[IDENTITY_MISSING] No identity') if identity_id.to_s.empty?

    cust = Onetime::Customer.load(identity_id)
    return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

    success(
      session: session,
      user: cust,
      auth_method: 'sessionauth',
      metadata: build_metadata(env)
    )
  end
end

# Routes using this strategy:
GET /account Core::Controllers::Account#show auth=sessionauth
GET /api/v2/account V2::Logic::Account::GetAccount auth=sessionauth
```

### ColonelStrategy (`auth=colonelsonly`)

**Access**: Users with `:colonel` role
**User**: Authenticated `Customer` with admin role

```ruby
class ColonelStrategy < BaseSessionAuthStrategy
  def additional_checks(cust, _env)
    return failure('[ROLE_COLONEL_REQUIRED] Colonel role required') unless cust.role?(:colonel)
    nil
  end

  def additional_metadata(_cust)
    { role: 'colonel' }
  end
end

# Routes using this strategy:
GET /colonel Core::Controllers::Colonel#dashboard auth=colonelsonly
```

### BasicAuthStrategy (`auth=basicauth`)

**Access**: Valid API credentials via HTTP Basic Auth
**User**: `Customer` (stateless, no session)

```ruby
class BasicAuthStrategy < Otto::Security::AuthStrategy
  def authenticate(env, _requirement)
    auth_header = env['HTTP_AUTHORIZATION']
    return failure('[AUTH_HEADER_MISSING]') unless auth_header

    unless auth_header.start_with?('Basic ')
      return failure('[AUTH_TYPE_INVALID]')
    end

    encoded = auth_header.sub('Basic ', '')
    decoded = Base64.decode64(encoded)
    username, apikey = decoded.split(':', 2)

    cust = Onetime::Customer.load(username)

    # Constant-time comparison to prevent timing attacks
    dummy_hash = Digest::SHA256.hexdigest("dummy:#{username}")
    valid_apikey = cust ? cust.valid_apikey?(apikey) : false

    return failure('[CREDENTIALS_INVALID]') unless valid_apikey

    success(
      session: {},  # No session for Basic auth (stateless)
      user: cust,
      auth_method: 'basic_auth',
      metadata: build_metadata(env, { auth_type: 'basic' })
    )
  end
end

# Routes using this strategy:
GET /api/v2/status V2::Controllers::Status#show auth=basicauth
```

### Application Delegation Pattern

All applications delegate to centralized strategies:

```ruby
# apps/web/core/auth_strategies.rb
module Core::AuthStrategies
  def self.register_essential(otto)
    # Always register public strategy
    otto.add_auth_strategy('noauth',
      Onetime::Application::AuthStrategies::NoAuthStrategy.new)

    return unless Onetime::Application::AuthStrategies.authentication_enabled?

    # Register session-based strategies
    otto.add_auth_strategy('sessionauth',
      Onetime::Application::AuthStrategies::SessionAuthStrategy.new)
    otto.add_auth_strategy('colonelsonly',
      Onetime::Application::AuthStrategies::ColonelStrategy.new)
  end
end

# apps/api/v2/auth_strategies.rb
module V2::AuthStrategies
  def self.register_essential(otto)
    otto.add_auth_strategy('noauth',
      Onetime::Application::AuthStrategies::NoAuthStrategy.new)

    return unless Onetime::Application::AuthStrategies.authentication_enabled?

    otto.add_auth_strategy('sessionauth',
      Onetime::Application::AuthStrategies::SessionAuthStrategy.new)
    otto.add_auth_strategy('basicauth',
      Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
  end
end
```

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

### Authentication Logic

Logic classes are the **only** code that writes to session:

#### AuthenticateSession

```ruby
class AuthenticateSession < Base
  def process
    cust = find_customer_by_email(@params[:u])
    raise OT::FormError unless cust.valid_passphrase?(@params[:p])

    # Write to session
    @sess['authenticated'] = true
    @sess['identity_id'] = cust.custid
    @sess['email'] = cust.email
    @sess['authenticated_at'] = Time.now.to_i
    @sess['ip_address'] = @strategy_result.metadata[:ip]
    @sess['user_agent'] = @strategy_result.metadata[:user_agent]
  end
end
```

#### DestroySession

```ruby
class DestroySession < Base
  def process
    @sess.clear
    { success: true, message: 'Logged out successfully' }
  end
end
```

### Account Logic

#### CreateAccount

```ruby
class CreateAccount < Base
  def raise_concerns
    raise OT::FormError, 'Email required' if @params[:email].to_s.empty?
    raise OT::FormError, 'Password required' if @params[:password].to_s.empty?

    existing = Onetime::Customer.load(@params[:email])
    raise OT::FormError, 'Account exists' if existing
  end

  def process
    cust = Onetime::Customer.create(@params[:email])
    cust.update_passphrase(@params[:password])

    # Write authentication to session
    @sess['authenticated'] = true
    @sess['identity_id'] = cust.custid
    @sess['email'] = cust.email
    @sess['authenticated_at'] = Time.now.to_i

    { success: true, customer: cust.safe_attributes }
  end
end
```

## Integration with Rodauth (Advanced Mode)

### Identity Resolution Middleware

```ruby
class IdentityResolution
  def call(env)
    request = Rack::Request.new(env)
    identity = resolve_identity(request, env)

    # Store resolved identity in environment
    env['identity.resolved']      = identity[:user]
    env['identity.source']        = identity[:source]
    env['identity.authenticated'] = identity[:authenticated]
    env['identity.metadata']      = identity[:metadata]

    @app.call(env)
  end

  private

  def resolve_identity(request, env)
    auth_mode = detect_auth_mode

    case auth_mode
    when 'advanced'
      resolve_advanced_identity(request, env)
    when 'basic'
      resolve_basic_identity(request, env)
    else
      resolve_anonymous_identity(request, env)
    end
  end

  def resolve_advanced_identity(_request, env)
    session = env['rack.session']
    return no_identity unless session
    return no_identity unless session['authenticated'] == true

    # Lookup customer by external_id from Rodauth
    customer = Onetime::Customer.find_by_extid(session['account_external_id'])
    return no_identity unless customer

    {
      user: customer,
      source: 'advanced',
      authenticated: true,
      metadata: {
        customer_id: customer.objid,
        external_id: customer.extid,
        account_id: session['advanced_account_id'],
        authenticated_at: session['authenticated_at']
      }
    }
  end
end
```

## Testing Patterns

### Controller Tests

```ruby
RSpec.describe Core::Controllers::Account do
  it 'loads authenticated customer from env' do
    customer = Onetime::Customer.create(email: 'test@example.com')

    # Mock environment with authenticated user
    env = {
      'otto.user' => customer,
      'otto.strategy_result' => Otto::Security::Authentication::StrategyResult.new(
        session: { 'authenticated' => true },
        user: customer,
        auth_method: 'sessionauth',
        metadata: {}
      )
    }

    get '/account', {}, env
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

    logic = described_class.new(
      strategy_result,
      { u: 'test@example.com', p: 'password' }
    )
    logic.process

    expect(strategy_result.session['authenticated']).to be true
    expect(strategy_result.session['identity_id']).to eq('test@example.com')
  end
end
```

## Configuration

### Session Middleware

```ruby
# lib/onetime/application/middleware_stack.rb
builder.use Onetime::MinimalSession, {
  secret: Onetime.auth_config.session['secret'],
  expire_after: 86_400,                    # 24 hours
  key: 'onetime.session',                  # Cookie name
  secure: Onetime.conf&.dig('site', 'ssl'),
  httponly: true,
  same_site: :strict
}
```

### Authentication Mode

```bash
# Environment variables
AUTHENTICATION_MODE=basic   # or 'advanced'
HMAC_SECRET=...            # For session integrity
DATABASE_URL=...           # PostgreSQL (advanced mode only)
```

```yaml
# etc/config.yaml
authentication:
  mode: basic
  session:
    expire_after: 86400
    key: onetime.session
  colonels:
    - admin@example.com
```

## Security Considerations

### Session Security

- **Cookie Attributes**:
  - `secure: true` (HTTPS only in production)
  - `httponly: true` (no JavaScript access)
  - `same_site: :strict` (CSRF protection)
- **Session Validation**:
  - 24-hour expiration with sliding window
  - HMAC-based integrity verification
  - Automatic cleanup of expired sessions
- **Session Storage**:
  - Redis with HMAC-signed + Base64-encoded data
  - No sensitive data in cookies (only session ID)

### Authentication Security

- **Password Hashing**:
  - BCrypt via `Customer#update_passphrase`
  - Automatic salt generation
  - Work factor configured for security/performance balance
- **API Key Security**:
  - Constant-time comparison to prevent timing attacks
  - Separate API keys from passwords
  - Rate limiting on authentication endpoints
- **Timing Attack Prevention**:
  - Dummy hash comparison for non-existent users
  - Consistent execution time regardless of user existence

## Architecture Benefits

### Post-Routing Authentication

- Full route context available during authentication
- Clean separation of routing and authorization
- Flexible per-route authentication requirements
- No middleware order dependencies

### Single Source of Truth

- Session data centralized in Redis
- Environment keys for request-scoped state
- Clear read/write boundaries
- No state duplication

### Separation of Concerns

- **Session Middleware**: Persistence layer (Redis I/O)
- **Identity Resolution**: Mode detection and identity loading
- **Otto Strategies**: Authorization enforcement
- **Controllers**: Read authentication state
- **Logic Classes**: Write authentication state

### Testability

- Controllers testable with mocked environment
- Logic classes testable with StrategyResult objects
- Strategies testable in isolation
- No global state dependencies

### Framework Alignment

- Otto's post-routing authentication provides full route context
- Rodauth's Roda integration preserves Rack conventions
- Shared session ensures state consistency
- Clean integration points between frameworks

## References

- **Otto Framework**: https://github.com/delano/otto
- **Rodauth Documentation**: https://rodauth.jeremyevans.net/
- **Rack Session Specification**: https://github.com/rack/rack/blob/main/SPEC.rdoc
- **Implementation Details**: `.serena/memories/otto-v2.0.0-pre2-migrating-guide.md`
