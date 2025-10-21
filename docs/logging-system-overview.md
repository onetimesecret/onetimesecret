# Logging System Overview

## Summary

The Onetime Secret logging system has been enhanced with structured logging capabilities using SemanticLogger, organized around 6 strategic categories for targeted debugging and operational instrumentation.

## Strategic Categories

1. **Auth** - Authentication/authorization flows
2. **Session** - Session lifecycle management
3. **HTTP** - HTTP requests, responses, and middleware
4. **Familia** - Redis operations via Familia ORM (configured via `Familia.logger =`)
5. **Otto** - Otto framework operations (configured via `Otto.logger =`)
6. **Rhales** - Rhales template rendering (pass logger instance, no native support)
7. **Sequel** - Database queries and operations (configured via `db.loggers <<`)
8. **Secret** - Core business value (create/view/burn)
9. **App** - Default fallback for application-level logging

## Key Features

### 1. Backward Compatible

Existing `Onetime.li/le/lw/ld` methods continue to work:

```ruby
Onetime.li "User logged in"
Onetime.le "Authentication failed"
Onetime.ld "Debug message"
```

### 2. Structured Logging

Add key-value pairs for better log aggregation:

```ruby
Onetime.li "User logged in", user_id: user.id, ip: request.ip
Onetime.le "Auth failed", reason: :invalid_password, attempts: 3
```

### 3. Category-Aware Logging Module

Mix into classes for automatic category detection:

```ruby
class AuthController
  include Onetime::Logging

  def login
    auth_logger.info "Login attempt", email: email
    # or use automatic detection:
    logger.debug "Validating credentials"  # Uses 'Auth' category
  end
end
```

### 4. Environment Variable Control

```bash
# Enable debug logging for specific categories
DEBUG_AUTH=1 bundle exec puma
DEBUG_SECRET=1 DEBUG_SESSION=1 bundle exec puma
DEBUG_FAMILIA=1 DEBUG_SEQUEL=1 bundle exec puma

# Or use fine-grained control
DEBUG_LOGGERS=Auth:debug,Secret:trace bundle exec puma

# Global log level
LOG_LEVEL=debug bundle exec puma
```

### 5. Configuration File

`etc/logging.yaml` provides centralized configuration:

```yaml
default_level: info
formatter: color  # or json for production

loggers:
  Auth: info
  Session: info
  HTTP: warn
  Secret: info
  # ...

http:
  enabled: true
  capture: standard  # minimal, standard, debug
  slow_request_ms: 1000
  ignore_paths:
    - /health
    - /_vite/*
```

## Architecture

### Files Created/Modified

**New Files:**
- `etc/logging.yaml` - Configuration file
- `lib/onetime/logging.rb` - Logging module for category-aware logging
- `lib/onetime/initializers/semantic_logger.rb` - SemanticLogger configuration
- `lib/onetime/application/request_logger.rb` - HTTP request logging middleware
- `docs/logging-migration-guide.md` - Migration guide with examples
- `try/system/logging_simple_try.rb` - Test suite

**Modified Files:**
- `lib/onetime/boot.rb` - Added `configure_logging` call
- `lib/onetime/class_methods.rb` - Enhanced li/le/lw/ld with structured logging
- `lib/onetime/initializers.rb` - Loads semantic_logger initializer
- `lib/onetime/initializers/semantic_logger.rb` - Added external library logger configuration
- `apps/web/auth/config/database.rb` - Updated to use SemanticLogger for Sequel

### Logging Flow

1. **Boot Time** (`lib/onetime/boot.rb:configure_logging`)
   - Load `etc/logging.yaml`
   - Initialize SemanticLogger appenders
   - Configure named logger levels
   - Apply environment variable overrides
   - Configure external library loggers (Familia, Otto, Sequel)

2. **Runtime**
   - Legacy calls use simple stdout/stderr output
   - Structured calls use SemanticLogger with categories
   - Thread-local category can override defaults

3. **Category Detection**
   - Automatic based on class name patterns (Auth, Session, Secret, etc.)
   - Manual via `with_log_category('Category')` helper
   - Explicit via category-specific loggers (`auth_logger`, `session_logger`)

## Usage Patterns

### Pattern 1: Simple Messages (Backward Compatible)

```ruby
Onetime.li "Processing request"
Onetime.le "Error occurred"
```

### Pattern 2: Structured Data

```ruby
Onetime.li "Request processed",
  path: req.path,
  method: req.request_method,
  duration_ms: duration
```

### Pattern 3: Category-Aware Class

```ruby
class V2::Logic::Authentication::ValidateCredentials
  include Onetime::Logging

  def perform
    # Automatically uses 'Auth' category
    logger.debug "Validating password", user_id: user.id

    # Or use explicit accessor
    auth_logger.info "Password validated", user_id: user.id
  end
end
```

### Pattern 4: Thread-Local Override

```ruby
include Onetime::Logging

def process_request(req)
  with_log_category('HTTP') do
    logger.info "Request received", path: req.path
    # ... processing ...
    logger.info "Response sent", status: status
  end
end
```

### Pattern 5: Explicit Category Logger

```ruby
include Onetime::Logging

def create_secret(params)
  secret_logger.debug "Creating secret", customer_id: customer.id
  # ... creation logic ...
  secret_logger.info "Secret created",
    key: secret.key,
    ttl: secret.ttl,
    encrypted: true
end
```

## Environment Variables

### Quick Debug Flags

```bash
DEBUG_AUTH=1       # Set Auth logger to debug
DEBUG_SESSION=1    # Set Session logger to debug
DEBUG_HTTP=1       # Set HTTP logger to debug
DEBUG_FAMILIA=1    # Set Familia logger to debug (Redis operations)
DEBUG_OTTO=1       # Set Otto logger to debug (router operations)
DEBUG_RHALES=1     # Set Rhales logger to debug (template rendering)
DEBUG_SEQUEL=1     # Set Sequel logger to debug (database queries)
DEBUG_SECRET=1     # Set Secret logger to debug
```

### Fine-Grained Control

```bash
# Multiple loggers with different levels
DEBUG_LOGGERS=Auth:debug,Secret:trace,HTTP:info

# Global level override
LOG_LEVEL=debug

# Familia command sampling (reduce high-traffic log volume)
FAMILIA_SAMPLE_RATE=0.01   # Log 1% of Redis commands (production)
FAMILIA_SAMPLE_RATE=0.1    # Log 10% of Redis commands (development)
FAMILIA_SAMPLE_RATE=1.0    # Log all Redis commands (debugging)
```

## Testing

```bash
# Run logging tests
bundle exec try --agent try/system/logging_simple_try.rb

# Test results: 23 testcases passed
# - Configuration file validation
# - Strategic category presence
# - HTTP config validation
# - Module file syntax check
```

## Migration Strategy

See `docs/logging-migration-guide.md` for detailed examples.

**Recommended phases:**

1. **Phase 1** - High-value areas (Auth, Secret, Session)
2. **Phase 2** - Infrastructure (HTTP, Middleware)
3. **Phase 3** - Remaining areas
4. **Phase 4** - Cleanup (optional)

No breaking changes required - migrate incrementally at your own pace.

## Production Considerations

### JSON Formatter

For log shipping and aggregation, use JSON format:

```yaml
# etc/logging.yaml
formatter: json
```

### Log Levels

Default configuration uses conservative levels:
- **info** - Auth, Session, Secret, App
- **warn** - HTTP, Familia, Otto, Rhales, Sequel

Adjust based on your monitoring needs.

### Performance

- Per-category level control reduces log volume
- Structured data more efficient than string interpolation
- SemanticLogger supports async appenders for high-throughput

## External Library Integration

The logging system automatically configures external libraries to use SemanticLogger for consistent formatting and centralized control.

### Libraries with Native Logger Support

These libraries are automatically configured during boot:

```ruby
# Familia Redis ORM - configured in lib/onetime/initializers/semantic_logger.rb
Familia.logger = SemanticLogger['Familia']

# Otto router - configured in lib/onetime/initializers/semantic_logger.rb
Otto.logger = SemanticLogger['Otto']

# Sequel database - configured per-connection in apps/web/auth/config/database.rb
db.loggers << SemanticLogger['Sequel']
```

### Libraries Without Native Logger Support

These libraries don't support custom loggers, so we use SemanticLogger directly in our wrapper code:

- **Rhales** - No native logger support; use `SemanticLogger['Rhales']` in templates/views
- **Redis** - No native logger support; use `SemanticLogger['Familia']` for Redis operations via Familia
- **Standard Library** - Use appropriate category logger for stdlib integrations

### Debug Flags for External Libraries

```bash
# Enable detailed Redis operation logging
DEBUG_FAMILIA=1 bundle exec puma

# Control Familia command sampling (default: 1% in prod, 10% in dev, 100% in test)
FAMILIA_SAMPLE_RATE=0.01 bundle exec puma  # Production: 1% sampling
FAMILIA_SAMPLE_RATE=0.1 bundle exec puma   # Development: 10% sampling
FAMILIA_SAMPLE_RATE=1.0 bundle exec puma   # Debugging: log everything

# Enable detailed router operation logging
DEBUG_OTTO=1 bundle exec puma

# Enable detailed database query logging
DEBUG_SEQUEL=1 bundle exec puma
```

### Familia Hooks

Familia provides operational hooks for audit trails:

**Command Performance Tracking:**
- Logs Redis command, duration, and context
- Subject to sampling configuration
- Debug level logging

**Lifecycle Events:**
- Logs Familia::Horreum save/destroy operations
- Always logged (not sampled)
- Debug level logging
- Includes class, identifier, and context

### Middleware

Middleware in `lib/middleware/` (not OnetimeSecret-specific) could be moved to `lib/onetime/middleware/` for cleaner organization. Consider this cleanup as a separate task.

## Configuration Reference

### Log Levels

From most to least verbose:
- **trace** - Very detailed debugging
- **debug** - Debugging information
- **info** - General information
- **warn** - Warnings and slow operations
- **error** - Errors and failures
- **fatal** - Critical failures

### Capture Modes (HTTP)

- **minimal** - method, path, status, duration
- **standard** - + request_id, ip
- **debug** - + params, headers, session_id

### Formatters

- **color** - Human-readable with ANSI colors (development)
- **json** - Structured JSON (production, log shipping)
- **default** - Plain text

## Future Enhancements

1. **Async Appenders** - For high-throughput production use
2. **Log Rotation** - File-based appenders with rotation
3. **Remote Logging** - Syslog, Splunk, etc.
4. **Request Context** - Automatic request ID tracking
5. **Performance Metrics** - Timing/profiling integration
6. **Sanitization Rules** - Enhanced PII/sensitive data filtering

## References

- SemanticLogger: https://logger.rocketjob.io/
- Migration Guide: `docs/logging-migration-guide.md`
- Test Suite: `try/system/logging_simple_try.rb`
- Configuration: `etc/logging.yaml`
