
# NEW CONFIGURATION SYSTEM ANALYSIS

## Overview of New Configuration Architecture

The new configuration system represents a fundamental shift from a simple YAML-based approach to a sophisticated, schema-validated, two-stage validation system with service-based architecture. This analysis covers the critical components and testing implications for the JSON payload structure and window property injection.

## Key Components

### 1. Configurator Class (`lib/onetime/configurator.rb`)

**Core Pipeline**: ENV normalize → Read → ERB → YAML → Validate → Process → Revalidate → Freeze

**Two-Stage Validation Pattern:**
- Stage 1: Schema validation with defaults (declarative)
- Stage 2: Business processing (imperative)
- Stage 3: Re-validation to ensure processing didn't break schema

**Critical Features:**
- Uses JSONSchemer for schema validation
- Supports ERB templating in YAML configuration
- Applies defaults during initial validation
- Tracks configuration changes at each pipeline stage using `then_with_diff`
- Deep freezes final configuration to prevent runtime mutations

### 2. Boot Orchestration (`lib/onetime/boot.rb`)

**Initialization Sequence:**
1. Load configuration via Configurator
2. Run init.d scripts during processing hook (config still mutable)
3. Start system services after config freeze
4. Create ConfigProxy for application-wide access

**Key Security Feature:**
- Configuration becomes immutable after processing hook
- Init scripts run with mutable config, services run with frozen config
- Graceful error handling with mode-specific behavior

### 3. Init.d Script System (`etc/init.d/`)

**Section-Based Processing:**
- One script per top-level config section (e.g., `site.rb` for `site:` section)
- Scripts execute during mutable phase, can modify their section's config
- Context provides access to `config` (mutable) and `global` (immutable snapshot)
- Security validation (e.g., `site.rb` checks for nil global secret)

**Script Context (`lib/onetime/boot/init_script_context.rb`):**
- Provides controlled access to configuration sections
- Includes helper methods for logging and debugging
- Enforces string-based access patterns for consistency

### 4. Service Registry & Config Proxy (`lib/onetime/services/`)

**ServiceRegistry (`service_registry.rb`):**
- Thread-safe configuration and service state management
- Uses Concurrent::Map for safe multi-threaded access
- Provides hot-reload capability for configuration changes

**ConfigProxy (`config_proxy.rb`):**
- Unified access to static (YAML) and dynamic (Redis) configuration
- Automatic fallback to static config when dynamic unavailable
- Supports nested configuration access via `dig` method
- Available globally as `OT.conf`

**RuntimeConfigService (`system/runtime_config_service.rb`):**
- Merges static YAML config with dynamic MutableConfig from Redis
- Provides unified configuration view across application
- Handles Redis connectivity gracefully

### 5. Schema Validation (`etc/-config.schema.yaml`)

**JSON Schema 2020-12 Specification:**
- Comprehensive validation for all configuration sections
- Default value injection during validation
- Type coercion (symbols to strings for backward compatibility)
- Structured error reporting with path information

**Validation Utilities (`lib/onetime/configurator/utils.rb`):**
- Format validation errors into user-friendly messages
- Extract problematic paths for debugging
- Apply defaults to configuration peers
- Symbol-to-string coercion for YAML compatibility

### 6. Frontend Data Injection

**Window Property System:**
- Configuration data flows through UIContext to frontend
- Data injected via `<data window="onetime">` tags in Rhales templates
- TypeScript definitions in `src/types/declarations/window.d.ts`
- Accessed via `WindowService.get()` with type safety

**UIContext (`lib/onetime/services/ui/ui_context.rb`):**
- Authoritative source for all frontend data
- Builds complete `onetime_window` data structure
- Handles authentication, branding, localization, diagnostics
- Provides structured access to merged configuration

## Critical Testing Implications

### 1. Configuration Validation Testing

**Schema Validation:**
- Test all configuration sections against schema
- Verify default value injection works correctly
- Test type coercion (symbols to strings)
- Validate error reporting includes correct paths

**Two-Stage Validation:**
- Test that initial validation applies defaults
- Verify processing hook can modify configuration
- Ensure re-validation catches processing errors
- Test deep freezing prevents runtime mutations

### 2. Init Script Testing

**Script Execution:**
- Test each init.d script with various configuration states
- Verify mutable vs immutable access patterns
- Test error handling and graceful degradation
- Validate security checks (e.g., nil global secret handling)

**Context Access:**
- Test string-based configuration access
- Verify global vs config scope isolation
- Test helper methods (logging, debugging)
- Validate script failure handling

### 3. Service Registry Testing

**Thread Safety:**
- Test concurrent access to configuration state
- Verify Concurrent::Map behavior under load
- Test hot-reload functionality
- Validate service provider registration/deregistration

**State Management:**
- Test static vs dynamic configuration merging
- Verify fallback behavior when Redis unavailable
- Test configuration refresh mechanisms
- Validate service health checking

### 4. Frontend Data Injection Testing

**Window Property Structure:**
- Test complete onetime_window data structure
- Verify type safety in TypeScript definitions
- Test data serialization/deserialization
- Validate CSP compliance with nonce handling

**UIContext Data Flow:**
- Test authentication-dependent data injection
- Verify domain strategy and branding handling
- Test localization data structure
- Validate diagnostics configuration exposure

### 5. Error Handling Testing

**Structured Error Classes:**
- Test ConfigValidationError with paths and messages
- Verify error propagation through pipeline
- Test graceful degradation in different modes
- Validate error logging and debugging output

**Boot Error Handling:**
- Test different error types during boot
- Verify mode-specific error handling (app vs cli vs test)
- Test exit vs raise behavior
- Validate error reporting completeness

## Security Considerations

### 1. Configuration Security

**Secret Management:**
- Global secret validation and nil checks
- Rotated secrets support in experimental section
- Environment variable-based secret injection
- Secure defaults for all security-related settings

**Input Validation:**
- Schema-based validation prevents malformed input
- Type coercion prevents injection attacks
- Path validation in error reporting
- Sanitization of user-provided configuration

### 2. Frontend Security

**CSP Compliance:**
- Nonce-based script execution
- Type-safe window property access
- Structured data injection prevents XSS
- Validation of frontend-bound data

**Data Exposure:**
- Controlled exposure of configuration to frontend
- Filtering of sensitive backend configuration
- Authentication-dependent data access
- Secure handling of diagnostic information

## Differences from Old System

### 1. Configuration Loading

**Old System:**
- Simple YAML loading with minimal validation
- Direct access to configuration hash
- No schema validation or type checking
- Limited error handling

**New System:**
- Multi-stage pipeline with validation
- Schema-driven defaults and type safety
- Structured error reporting
- Comprehensive validation at multiple stages

### 2. Service Architecture

**Old System:**
- Direct configuration access throughout codebase
- No service registry or provider pattern
- Limited hot-reload capability
- Monolithic configuration handling

**New System:**
- Service-based architecture with registry
- Provider pattern for system services
- Hot-reload capability with graceful fallback
- Separation of concerns between configuration and services

### 3. Frontend Integration

**Old System:**
- Manual data preparation in view classes
- Limited type safety
- Direct configuration exposure
- Minimal structure validation

**New System:**
- Structured UIContext with business logic
- Full TypeScript integration
- Controlled data exposure
- Comprehensive data validation

This new system provides significantly better testability, security, and maintainability while supporting complex deployment scenarios and dynamic configuration management.

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
