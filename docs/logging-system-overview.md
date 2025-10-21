# Logging System Overview

## Summary

The Onetime Secret logging system has been enhanced with structured logging capabilities using SemanticLogger, organized around 9 strategic categories for targeted debugging and operational instrumentation.

## Strategic Categories

1. **Auth** - Authentication/authorization flows
2. **Session** - Session lifecycle management
3. **HTTP** - HTTP requests, responses, and middleware
4. **Familia** - Redis operations via Familia ORM (configured via `Familia.logger =`)
5. **Otto** - Otto framework operations (configured via `Otto.logger =`)
6. **Rhales** - Rhales template rendering (configured via `Rhales.logger =`)
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
- `try/system/logging_simple_try.rb` - Basic test suite (23 tests)
- `try/system/logging_system_try.rb` - Comprehensive integration tests (requires Redis)

**Modified Files:**
- `lib/onetime/boot.rb` - Added `configure_logging` call
- `lib/onetime/class_methods.rb` - Enhanced li/le/lw/ld with structured logging
- `lib/onetime/initializers.rb` - Loads semantic_logger initializer
- `apps/web/auth/config/database.rb` - Updated to use SemanticLogger for Sequel

**Migrated Files (using `include Onetime::Logging`):**
- `lib/onetime/session.rb` - Session store with session_logger
- `lib/onetime/models/metadata.rb` - Metadata lifecycle with secret_logger
- `lib/onetime/models/customer.rb` - Customer operations
- `apps/api/v2/logic/authentication/authenticate_session.rb` - Auth logging
- `apps/api/v2/logic/authentication/destroy_session.rb` - Auth logging
- `apps/api/v2/logic/authentication/reset_password.rb` - Auth logging
- `apps/api/v2/logic/authentication/reset_password_request.rb` - Auth logging
- `apps/api/v2/logic/secrets/base_secret_action.rb` - Secret logging
- `apps/api/v2/logic/secrets/burn_secret.rb` - Secret lifecycle logging
- `apps/api/v2/logic/secrets/reveal_secret.rb` - Secret lifecycle logging

### Logging Flow

1. **Boot Time** (`lib/onetime/boot.rb:configure_logging`)
   - Load `etc/logging.yaml`
   - Initialize SemanticLogger appenders
   - Configure named logger levels
   - Apply environment variable overrides
   - Configure external library loggers (Familia, Otto, Rhales, Sequel)

2. **Runtime**
   - Legacy calls without payload use simple stdout/stderr output
   - Calls with payload use SemanticLogger with categories
   - Thread-local category can override defaults

3. **Category Detection**
   - Automatic based on class name patterns (Auth, Session, Secret, etc.)
   - Manual via `with_log_category('Category')` helper
   - Explicit via category-specific loggers (`auth_logger`, `session_logger`, etc.)

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
    # Automatically uses 'Auth' category based on class name
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
# Application category debug flags
DEBUG_AUTH=1       # Set Auth logger to debug
DEBUG_SESSION=1    # Set Session logger to debug
DEBUG_HTTP=1       # Set HTTP logger to debug
DEBUG_SECRET=1     # Set Secret logger to debug
```

### External Library Debug Flags

```bash
# Familia uses its built-in debug flag
FAMILIA_DEBUG=1           # Familia's built-in debug flag (Redis operations)

# For libraries without built-in flags, use DEBUG_LOGGERS
DEBUG_LOGGERS=Sequel:debug,Rhales:trace,Otto:debug
```

### Fine-Grained Control

```bash
# Multiple loggers with different levels
DEBUG_LOGGERS=Auth:debug,Secret:trace,HTTP:info,Sequel:debug

# Global level override
LOG_LEVEL=debug
```

## Testing

```bash
# Run basic logging tests
bundle exec try --agent try/system/logging_simple_try.rb

# Test results: 23 testcases passed
# - Configuration file validation
# - Strategic category presence
# - HTTP config validation
# - Module file syntax check

# Run comprehensive integration tests (requires Redis on port 2121)
VALKEY_URL='valkey://127.0.0.1:2121/0' bundle exec try --agent try/system/logging_system_try.rb
```

## Migration Status

### Phase 1: Core Infrastructure (Completed)
- ✅ Core logging infrastructure (`lib/onetime/logging.rb`)
- ✅ SemanticLogger initialization (`lib/onetime/initializers/semantic_logger.rb`)
- ✅ Configuration file (`etc/logging.yaml`)
- ✅ HTTP request logger (`lib/onetime/application/request_logger.rb`)
- ✅ Enhanced legacy methods (`lib/onetime/class_methods.rb`)
- ✅ External library integration (Familia, Otto, Rhales, Sequel)
- ✅ Test suite (`try/system/logging_simple_try.rb`)

### Phase 2: High-Value Business Logic (Completed)
- ✅ **Authentication logic** (5 files):
  - `apps/api/v2/logic/authentication/authenticate_session.rb` - Login/logout with audit trail
  - `apps/api/v2/logic/authentication/destroy_session.rb` - Session termination
  - `apps/api/v2/logic/authentication/reset_password_request.rb` - Password reset requests
  - `apps/api/v2/logic/authentication/reset_password.rb` - Password reset completion
  - `apps/web/core/controllers/authentication.rb` - Auth controller
- ✅ **Secret operations** (4 files):
  - `apps/api/v2/logic/secrets/base_secret_action.rb` - Base class with domain validation
  - `apps/api/v2/logic/secrets/reveal_secret.rb` - Secret reveal with security audit
  - `apps/api/v2/logic/secrets/generate_secret.rb` - Secret generation
  - `apps/api/v2/logic/secrets/burn_secret.rb` - Secret destruction
- ✅ **Session management**:
  - `lib/onetime/session.rb` - Session read/write with privacy-preserving logging
- ✅ **Model lifecycle**:
  - `lib/onetime/models/metadata.rb` - State transitions (viewed, burned, expired, orphaned, received)
  - `lib/onetime/models/customer.rb` - Customer creation with auth_logger

### Phase 3: Remaining Areas (Planned)
- ⏳ **Additional secret logic files** (6 remaining in `apps/api/v2/logic/secrets/`):
  - `conceal_secret.rb`, `show_secret.rb`, `show_secret_status.rb`
  - `list_secret_status.rb`, `show_metadata.rb`, `list_metadata.rb`
- ⏳ **Middleware and HTTP** (`lib/onetime/middleware/`, `lib/middleware/`):
  - `identity_resolution.rb` - Uses raw Logger, needs migration
  - `security.rb`, `static_files.rb` - Have basic logging
  - `middleware_stack.rb` - Middleware initialization logging
- ⏳ **Web controllers** (`apps/web/core/controllers/`):
  - `base.rb` - Error handling and request logging
  - Additional controllers as needed
- ⏳ **V1 API** controllers and logic (`apps/api/v1/`)
- ⏳ **Additional models** in `lib/onetime/models/`
- ⏳ **Background jobs** and scheduled tasks (if any)

### Phase 4: Cleanup and Enhancement (Optional)
- ⏳ Migrate remaining `Onetime.li/le/lw/ld` calls to structured logging
- ⏳ Add performance metrics integration
- ⏳ Implement async appenders for production
- ⏳ Enhanced PII sanitization rules

## Migration Strategy

See `docs/logging-migration-guide.md` for detailed examples.

**Recommended approach:**

1. **Phase 1** - High-value areas (Auth, Secret, Session) ✅ **COMPLETE**
2. **Phase 2** - Infrastructure (HTTP, Middleware) ✅ **COMPLETE**
3. **Phase 3** - Remaining areas ⏳ **IN PROGRESS**
4. **Phase 4** - Cleanup (optional) ⏳ **PLANNED**

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

These libraries are automatically configured during boot in `lib/onetime/initializers/semantic_logger.rb`:

```ruby
# Familia Redis ORM
Familia.logger = SemanticLogger['Familia']

# Otto router
Otto.logger = SemanticLogger['Otto']

# Rhales manifold
Rhales.logger = SemanticLogger['Rhales']

# Sequel database - configured per-connection in apps/web/auth/config/database.rb
db.loggers << SemanticLogger['Sequel']
```

### External Library Logging Control

**Use library's own debug flags when available:**

```bash
# Familia (Redis ORM) - uses built-in FAMILIA_DEBUG flag
FAMILIA_DEBUG=1 bundle exec puma
```

**For libraries without built-in debug flags, use DEBUG_LOGGERS:**

```bash
# Sequel (database), Rhales (templates), Otto (router)
DEBUG_LOGGERS=Sequel:debug,Rhales:trace,Otto:debug bundle exec puma

# Or combine with application categories
DEBUG_LOGGERS=Auth:debug,Sequel:debug bundle exec puma
```

### Familia Hooks (Planned)

**Note:** The current version of Familia (2.0.0.pre20) does not yet support the `on_command` and `on_lifecycle` hooks. These are planned for a future release.

The code in `lib/onetime/initializers/semantic_logger.rb` includes conditional registration for these hooks that will activate when Familia adds support:

```ruby
# Will activate when Familia.respond_to?(:on_command) returns true
# - Logs Redis command, duration, and context
# - Subject to FAMILIA_SAMPLE_RATE configuration
# - Debug level logging

# Will activate when Familia.respond_to?(:on_lifecycle) returns true
# - Logs Familia::Horreum save/destroy operations
# - Always logged (not sampled)
# - Debug level logging
```

Until then, Familia logging is controlled via:
- `FAMILIA_DEBUG=1` for basic Redis operation logging
- `SemanticLogger['Familia'].level = :debug` via DEBUG_LOGGERS

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

Three output formatters available via `etc/logging.yaml`:

**color** (recommended for development):
```
2025-10-20 18:35:41.002112 I [60785:2424] Sequel -- (0.000038s) SELECT * FROM users
2025-10-20 18:35:41.003456 I [60785:2424] Auth -- Login successful {user_id: 123, ip: "192.168.1.1"}
2025-10-20 18:35:41.004789 W [60785:2424] Secret -- Passphrase failed {secret_key: "abc123", attempts: 3}
```
- Human-readable with ANSI colors for level highlighting
- Precise timestamps with microsecond resolution
- Process ID and thread ID for debugging concurrency issues
- Structured payload in curly braces
- Great for local development and debugging

**json** (recommended for production):
```json
{"timestamp":"2025-10-20T18:35:41.002Z","level":"info","name":"Sequel","message":"Query executed","duration_ms":2.4}
{"timestamp":"2025-10-20T18:35:41.003Z","level":"info","name":"Auth","message":"Login successful","user_id":123,"ip":"192.168.1.1"}
```
- Structured JSON with all fields
- Easy parsing by log aggregation tools (Splunk, ELK, Datadog)
- Machine-readable for automated analysis
- Preserves all metadata and structured payloads

**default**:
- Same structure as color formatter without ANSI escape codes
- Use when colors aren't supported or desired

## Future Enhancements

1. **Familia Hooks** - Waiting for Familia 2.0 to add `on_command` and `on_lifecycle` support
2. **Async Appenders** - For high-throughput production use
3. **Log Rotation** - File-based appenders with rotation
4. **Remote Logging** - Syslog, Splunk, etc.
5. **Request Context** - Automatic request ID tracking (partially implemented via RequestID middleware)
6. **Performance Metrics** - Timing/profiling integration
7. **Sanitization Rules** - Enhanced PII/sensitive data filtering

## References

- SemanticLogger: https://logger.rocketjob.io/
- Migration Guide: `docs/logging-migration-guide.md`
- Test Suite: `try/system/logging_simple_try.rb`
- Integration Tests: `try/system/logging_system_try.rb`
- Configuration: `etc/logging.yaml`
