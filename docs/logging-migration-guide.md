# Logging System Migration Guide

This guide shows how to migrate from legacy logging methods to the new structured logging system with strategic categories.

## Quick Reference

### 8 Strategic Categories

1. **Auth** - Authentication/authorization flows
2. **Session** - Session lifecycle management
3. **HTTP** - HTTP requests, responses, and middleware
4. **Familia** - Redis operations via Familia ORM (configured via `Familia.logger =`)
5. **Otto** - Otto framework operations (configured via `Otto.logger =`)
6. **Rhales** - Rhales template rendering (pass logger instance)
7. **Sequel** - Database queries and operations (configured via `db.loggers <<`)
8. **Secret** - Core business value (create/view/burn)
9. **App** - Default fallback for application-level logging

## Exception Logging (NEW)

The `OT.le` method now supports a dedicated `exception:` parameter for proper exception handling with SemanticLogger. This replaces the old pattern of multiple log calls for exception details.

### Before (Old Pattern - Multiple Calls)

```ruby
begin
  dangerous_operation
rescue StandardError => ex
  OT.le "#{ex.class}: #{ex.message}"
  OT.le ex.backtrace.join("\n")
end
```

**Problems:**
- Requires 2-3 separate log calls per exception
- Backtrace logged as raw string (hard to parse)
- No structured context
- String interpolation (less efficient)

### After (New Pattern - Single Call)

```ruby
begin
  dangerous_operation
rescue StandardError => ex
  OT.le "Operation failed", exception: ex, operation: :create, user_id: user.id
end
```

**Benefits:**
- Single log call with all exception details
- SemanticLogger automatically formats exception and backtrace
- Structured context preserved for log aggregation
- Compatible with error tracking systems (Sentry)
- More efficient (no string interpolation needed)

### Exception Logging Patterns

```ruby
# Basic exception logging
rescue StandardError => ex
  OT.le "Unexpected error", exception: ex
end

# Exception with structured context
rescue Redis::ConnectionError => ex
  OT.le "Redis operation failed",
    exception: ex,
    operation: :save,
    key: identifier
end

# Exception with sanitized user data
rescue ArgumentError => ex
  OT.le "Validation failed",
    exception: ex,
    field: :email,
    input: sanitized_input
end

# Exception in authentication flow
rescue SecurityError => ex
  OT.le "Authentication failed",
    exception: ex,
    email: sanitized_email,
    ip: request.ip,
    attempt_count: attempts
end
```

## Migration Patterns

### Pattern 1: Simple Message (Backward Compatible)

**Before:**
```ruby
Onetime.li "User logged in"
Onetime.le "Authentication failed"
Onetime.ld "Processing request"
```

**After (no changes required - backward compatible):**
```ruby
Onetime.li "User logged in"
Onetime.le "Authentication failed"
Onetime.ld "Processing request"
```

### Pattern 2: Add Structured Data

**Before:**
```ruby
Onetime.ld "User login: #{email} from #{ip}"
```

**After:**
```ruby
Onetime.ld "User login", email: email, ip: ip
```

**Benefits:**
- Easier to query/aggregate in log analysis tools
- Automatic parameter sanitization
- Type-safe structured data

### Pattern 3: Using Logging Module in Classes

**Before:**
```ruby
class AuthController
  def login
    Onetime.ld "Processing login for #{email}"
  end
end
```

**After:**
```ruby
class AuthController
  include Onetime::Logging

  def login
    auth_logger.debug "Processing login", email: email, ip: request.ip
  end
end
```

### Pattern 4: Automatic Category Detection

**Before:**
```ruby
module V2::Logic::Authentication
  class ValidateCredentials
    def perform
      Onetime.ld "Validating password"
    end
  end
end
```

**After:**
```ruby
module V2::Logic::Authentication
  class ValidateCredentials
    include Onetime::Logging

    def perform
      # Automatically uses 'Auth' logger based on class name
      logger.debug "Validating password", user_id: user.id
    end
  end
end
```

### Pattern 5: Thread-Local Category Override

**Before:**
```ruby
def process_request(req)
  Onetime.ld "Request: #{req.path}"
  # ... processing ...
  Onetime.ld "Response: #{status}"
end
```

**After:**
```ruby
def process_request(req)
  Thread.current[:log_category] = 'HTTP'
  Onetime.ld "Request received", path: req.path, method: req.request_method
  # ... processing ...
  Onetime.ld "Response sent", status: status, duration_ms: duration
ensure
  Thread.current[:log_category] = nil
end
```

**Or using helper:**
```ruby
include Onetime::Logging

def process_request(req)
  with_log_category('HTTP') do
    logger.debug "Request received", path: req.path
    # ... processing ...
    logger.debug "Response sent", status: status
  end
end
```

## Real-World Examples

### Example 1: Authentication Controller

**Before:**
```ruby
class AuthenticationController
  def authenticate(req, res)
    email = req.params['email']
    Onetime.ld "Login attempt for #{email}"

    result = AuthenticateSession.new(email, password).process

    if result.success?
      Onetime.li "User #{email} logged in successfully"
      res.redirect '/'
    else
      Onetime.lw "Login failed for #{email}: #{result.error}"
      res.status = 401
    end
  end
end
```

**After:**
```ruby
class AuthenticationController
  include Onetime::Logging

  def authenticate(req, res)
    email = req.params['email']
    auth_logger.debug "Login attempt", email: email, ip: req.ip

    result = AuthenticateSession.new(email, password).process

    if result.success?
      auth_logger.info "Login successful",
        user_id: result.user.id,
        email: email,
        session_id: req.session.id
      res.redirect '/'
    else
      auth_logger.warn "Login failed",
        email: email,
        reason: result.error,
        ip: req.ip
      res.status = 401
    end
  end
end
```

### Example 2: Secret Creation Logic

**Before:**
```ruby
module V2::Logic::Secrets
  class CreateSecret
    def perform
      Onetime.ld "Creating secret"
      secret = Secret.new
      secret.save
      Onetime.li "Secret created: #{secret.key}"
      secret
    end
  end
end
```

**After:**
```ruby
module V2::Logic::Secrets
  class CreateSecret
    include Onetime::Logging

    def perform
      secret_logger.debug "Creating secret",
        customer_id: customer.id,
        ttl: ttl

      secret = Secret.new
      secret.save

      secret_logger.info "Secret created",
        key: secret.key,
        ttl: secret.ttl,
        encrypted: true,
        customer_id: customer.id

      secret
    end
  end
end
```

### Example 3: Session Management

**Before:**
```ruby
class SessionManager
  def create_session(user)
    Onetime.ld "Creating session for user #{user.id}"
    session = Session.create(user_id: user.id)
    Onetime.li "Session created: #{session.id}"
    session
  end

  def destroy_session(session_id)
    Onetime.ld "Destroying session #{session_id}"
    Session.find(session_id)&.destroy
    Onetime.li "Session destroyed: #{session_id}"
  end
end
```

**After:**
```ruby
class SessionManager
  include Onetime::Logging

  def create_session(user)
    session_logger.debug "Creating session",
      user_id: user.id,
      ip: user.last_ip

    session = Session.create(user_id: user.id)

    session_logger.info "Session created",
      session_id: session.id,
      user_id: user.id,
      expires_at: session.expires_at

    session
  end

  def destroy_session(session_id)
    session_logger.debug "Destroying session", session_id: session_id
    Session.find(session_id)&.destroy
    session_logger.info "Session destroyed", session_id: session_id
  end
end
```

### Example 4: Middleware Logging

**For general-purpose middleware (lib/middleware/), use the Middleware::Logging module:**

```ruby
# lib/middleware/session_debugger.rb
require_relative 'logging'

module Rack
  class SessionDebugger
    include Middleware::Logging

    def initialize(app)
      @app = app
      @enabled = ENV['DEBUG_SESSION'].to_s.match?(/^(true|1|yes)$/i)
    end

    def call(env)
      return @app.call(env) unless @enabled

      logger.debug "Session debug start",
        method: env['REQUEST_METHOD'],
        path: env['PATH_INFO']

      status, headers, body = @app.call(env)

      logger.debug "Session debug complete", status: status

      [status, headers, body]
    rescue StandardError => ex
      logger.error "Session debugging failed",
        error: ex.message,
        backtrace: ex.backtrace.first(3)
      [500, {}, []]
    end
  end
end
```

**Benefits:**
- Automatic logger selection (SemanticLogger when available, stdlib Logger as fallback)
- Category inference from middleware class name (SessionDebugger → 'Session')
- Structured logging with consistent interface
- Portable middleware (works outside Onetime context)

**Category Inference Rules:**
- `/Session/` → 'Session'
- `/Auth/` → 'Auth'
- `/Security|CSRF|IPPrivacy/` → 'HTTP'
- Default → 'App'

## Environment Variable Usage

### Development

```bash
# Enable debug logging for authentication
DEBUG_AUTH=1 bundle exec puma

# Enable debug for multiple categories
DEBUG_LOGGERS=Auth:debug,Secret:trace bundle exec puma

# Set global log level
LOG_LEVEL=debug bundle exec puma
```

### Production

```bash
# Use JSON formatter for log shipping
# (configured in etc/logging.yaml: formatter: json)
RACK_ENV=production bundle exec puma

# Enable targeted debugging without changing config
DEBUG_SECRET=1 RACK_ENV=production bundle exec puma
```

## Testing Your Changes

```ruby
# try/system/logging_system_try.rb

## Verify backward compatibility
output = capture_output { Onetime.li "Test message" }
output #=> /I\(\d+\): Test message/

## Verify structured logging
logger = SemanticLogger['Auth']
logger.info "Login", user_id: 123
# Check log output contains structured data

## Verify category detection
class TestAuth
  include Onetime::Logging
end

TestAuth.new.logger.name #=> 'Auth'
```

## Common Pitfalls

### ❌ Don't use multiple calls for exception logging

```ruby
# Bad - Multiple calls, string interpolation
rescue StandardError => ex
  OT.le "#{ex.class}: #{ex.message}"
  OT.le ex.backtrace.join("\n")
end

# Good - Single call with exception parameter
rescue StandardError => ex
  OT.le "Operation failed", exception: ex, context: value
end
```

### ❌ Don't interpolate sensitive data

```ruby
# Bad
logger.info "Password: #{password}"  # Logs password!

# Good
logger.info "Password validated", valid: true
```

### ❌ Don't use string interpolation with structured logs

```ruby
# Bad
logger.info "User #{user.id} logged in", status: :success

# Good
logger.info "User logged in", user_id: user.id, status: :success
```

### ❌ Don't interpolate exception details into message string

```ruby
# Bad - Loses structured data and backtrace
logger.error "Error: #{ex.message} at #{ex.backtrace.first}"

# Good - Preserves full exception with context
logger.error "Operation failed", exception: ex, operation: :save
```

### ❌ Don't forget to set category for cross-cutting concerns

```ruby
# Bad - uses 'App' logger
def middleware_call(env)
  logger.debug "Processing request"
end

# Good - explicit category
def middleware_call(env)
  with_log_category('HTTP') do
    logger.debug "Processing request"
  end
end
```

## Gradual Migration Strategy

1. **Phase 1**: Update high-value areas (Auth, Secret)
   - Authentication flows
   - Secret creation/viewing
   - Session management

2. **Phase 2**: Update infrastructure (HTTP, Middleware)
   - Request logging
   - Middleware operations
   - Error handlers

3. **Phase 3**: Update remaining areas
   - Background jobs
   - Administrative operations
   - Utility functions

4. **Phase 4**: Remove legacy methods (optional)
   - Once all code migrated
   - Update tests
   - Final cleanup
