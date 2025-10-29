# Logging Architecture

## OneTimeSecret Custom Logging System

OneTimeSecret uses a **custom logging architecture** based on SemanticLogger with strategic operational categories. This document explains why we don't use the standard `SemanticLogger::Loggable` mixin and how our system works.

> **Note**: This document describes architectural concepts and patterns. For specific implementation details, refer to:
> - `lib/onetime/logging.rb` - Logging mixin with category inference
> - `lib/onetime/initializers/semantic_logger.rb` - Configuration and cached loggers
> - `lib/middleware/logging.rb` - Middleware logging support
> - `apps/web/auth/lib/logging.rb` - Auth-specific logging helpers
> - `etc/defaults/logging.defaults.yaml` - Default log level configuration

## Why Not SemanticLogger::Loggable?

SemanticLogger provides a `Loggable` mixin that automatically adds logger methods to classes. However, **we intentionally don't use it** because:

### 1. Strategic Categories vs Class Names

**Loggable limitation:**
```ruby
class V2::Logic::Authentication::AuthenticateSession
  include SemanticLogger::Loggable
  # Logger name: "V2::Logic::Authentication::AuthenticateSession" ❌
  # Too granular, hard to filter logs operationally
end
```

**Our superior pattern:**
```ruby
class V2::Logic::Authentication::AuthenticateSession
  include Onetime::Logging
  # Logger name: "Auth" ✅
  # All auth code logs to one strategic category
end
```

Our strategic categories enable:
- **Operational monitoring** - `grep` logs by business function (Auth, Session, HTTP, etc.)
- **Level control** - `DEBUG_AUTH=1` affects all authentication code at once
- **Compliance** - Authentication audit trails in one category
- **Performance** - Reduced log volume via category filtering

### 2. Cached Logger Instances

SemanticLogger::Loggable caches one logger per class, while our system uses shared cached instances per category:

**Loggable**: Creates `@logger` instance variable per class
**Onetime::Logging**: Returns cached instance from `Onetime.get_logger(category)`

Our cached instances:
- Preserve configured log levels from YAML/env vars
- Reduce memory overhead (~10 category instances vs hundreds of class instances)
- Enable runtime level changes that affect all code using that category

### 3. Thread-Local Category Override

Our system supports dynamic category switching:

```ruby
class RequestProcessor
  include Onetime::Logging

  def handle(request)
    with_log_category(request.category) do
      logger.info "Processing"  # Logs to dynamic category
    end
  end
end
```

**SemanticLogger::Loggable cannot do this** - logger name is fixed at class definition time.

## Our Logging Architecture

### Strategic Categories

All logging goes through these operational categories:

| Category | Purpose | Example Usage |
|----------|---------|---------------|
| `Auth` | Authentication/authorization | Login, logout, MFA, password reset |
| `Session` | Session management | Session create, destroy, validation |
| `HTTP` | HTTP requests/responses | Request logging, middleware |
| `Familia` | Redis ORM operations | Model CRUD, relationship queries |
| `Otto` | Routing and request handling | Route matching, auth strategies |
| `Rhales` | Rhales framework | Framework internals |
| `Secret` | Secret lifecycle | Secret create, view, expire |
| `Sequel` | Database operations | SQL queries, migrations |
| `App` | General application | Fallback for uncategorized code |

### Usage Pattern

```ruby
class V2::Logic::Authentication::AuthenticateSession
  include Onetime::Logging

  def perform
    # Automatic category inference → Auth logger
    logger.info "Login attempt", email: email

    # Explicit category accessor
    auth_logger.debug "Validating credentials"

    # Thread-local override
    with_log_category('HTTP') do
      logger.warn "Rate limit exceeded"  # → HTTP logger
    end
  end
end
```

### Logger Access Methods

**Never use:** `SemanticLogger['CategoryName']` - creates uncached instances

**Always use:** `Onetime.get_logger('CategoryName')` - returns cached instance

**Or use the mixin:**
```ruby
include Onetime::Logging

# Automatic category from class name
logger.info "message"

# Explicit category accessors
auth_logger.info "auth message"
session_logger.debug "session message"
http_logger.warn "http message"
sequel_logger.debug "database query"
```

### Category Inference

The `Onetime::Logging` mixin automatically infers categories from class names using pattern matching:

- Classes with "Authentication" or "Auth" → `Auth` category
- Classes with "Session" → `Session` category
- Classes with "HTTP", "Request", "Response", or "Controller" → `HTTP` category
- Classes with "Familia" → `Familia` category
- Classes with "Otto" → `Otto` category
- Classes with "Secret" or "Metadata" → `Secret` category
- Classes with "Sequel" → `Sequel` category
- All others → `App` category (default)

See `lib/onetime/logging.rb` for the complete implementation.

## Configuration

Log levels for each category are configured in `etc/defaults/logging.defaults.yaml` under the `loggers` section. Each category can have its own level (debug, info, warn, error).

Runtime overrides using environment variables:
```bash
DEBUG_AUTH=1 bundle exec puma     # Set Auth logger to debug
DEBUG_SEQUEL=1 bundle exec puma   # Set Sequel logger to debug
```

The configuration supports setting default levels and per-category levels. See `lib/onetime/initializers/semantic_logger.rb` for the configuration loading implementation.

### SemanticLogger Reference

Official docs: https://logger.rocketjob.io/appenders.html#custom-formatting

Quick reference from SemanticLogger source:

%c  # Class/category name
%C  # Class name (without module)
%d  # Date (ISO8601 format)
%e  # Exception with backtrace
%f  # File name
%l  # Log level (DEBUG, INFO, etc.)
%L  # Line number
%m  # Message
%M  # Method name
%p  # Process ID
%P  # Process name
%t  # Thread name
%T  # Time (milliseconds since epoch)
%h  # Hostname
%X{key}  # Named tag value

```bash
# Or in code:
bundle open semantic_logger
# Look at: lib/semantic_logger/formatters/default.rb
```

### SemanticLogger::Loggable Reference

For completeness, here's how SemanticLogger::Loggable works (we don't use this):

```ruby
class MyClass
  include SemanticLogger::Loggable
  # Automatically gets logger method using class name
end

MyClass.logger         # Class-level logger
MyClass.new.logger     # Instance-level logger
```

**When to use Loggable (rare cases):**
- External integrations where full class path is useful for debugging
- Throwaway diagnostic code
- Non-core utilities that don't fit strategic categories

**For core application code:** Always use `Onetime::Logging`
