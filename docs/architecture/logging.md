# Logging Architecture

## OneTimeSecret Custom Logging System

OneTimeSecret uses a **custom logging architecture** based on SemanticLogger with strategic operational categories. This document explains why we don't use the standard `SemanticLogger::Loggable` mixin and how our system works.

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

**Critical difference:**
```ruby
# SemanticLogger::Loggable creates new instances per class
def logger
  @logger ||= SemanticLogger[self.class.name]  # One per class
end

# Our Onetime::Logging uses shared cached instances
def logger
  category = infer_category
  Onetime.get_logger(category)  # Shared instance with preserved config
end
```

Our cached instances:
- Preserve configured log levels from YAML/env vars
- Reduce memory overhead (10 instances vs hundreds)
- Enable runtime level changes that affect all code

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
| `App` | General application | Fallback for uncategorized code |
| `Sequel` | Database operations | SQL queries, migrations |

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
```

### Category Inference

The `Onetime::Logging` mixin automatically infers categories from class names:

```ruby
# lib/onetime/logging.rb
def infer_category
  class_name = self.class.name

  return 'Auth'    if class_name =~ /Authentication|Auth(?!or)/i
  return 'Session' if class_name =~ /Session/i
  return 'HTTP'    if class_name =~ /HTTP|Request|Response|Controller/i
  return 'Familia' if class_name =~ /Familia/i
  return 'Otto'    if class_name =~ /Otto/i
  return 'Secret'  if class_name =~ /Secret|Metadata/i

  'App'  # Default fallback
end
```

### Configuration

Log levels are configured in `etc/defaults/logging.defaults.yaml`:

```yaml
loggers:
  Auth: info          # Authentication events
  Session: info       # Session lifecycle
  HTTP: warn          # HTTP requests (reduce noise)
  Familia: warn       # Redis operations
  Otto: info          # Routing
  Secret: info        # Secret operations
  App: info           # General application
  Sequel: warn        # Database queries
```

Override at runtime:
```bash
DEBUG_AUTH=1 bundle exec puma  # Set Auth logger to debug
```

## SemanticLogger::Loggable Reference

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

## Architecture Benefits

1. **Operational Visibility** - Business-aligned log organization
2. **Cached Instances** - Level settings preserved, reduced memory
3. **Thread-Local Override** - Dynamic category switching per request
4. **Category-Specific Accessors** - Explicit `auth_logger.info` when needed
5. **Automatic Inference** - `logger.info` works without manual wiring

This architecture is specifically designed for a Familia/Redis-based Ruby application with complex authentication flows and operational monitoring requirements.
