# Vue Frontend Testing Guidelines - Data Boundary Validation

## Critical Implementation Details

### Window State Access Pattern
- **Current Implementation**: Uses `window.onetime` (not `window.__ONETIME_STATE__`)
- **Service Layer**: All access goes through `WindowService` - never access `window.onetime` directly
- **State Key**: Defined as `const STATE_KEY: string = 'onetime'` in WindowService

### Sensitive Data Considerations

#### Data NOT Exposed to Frontend
These fields should **NEVER** appear in window state tests:
```typescript
// NEVER test for these - they indicate a security breach
const FORBIDDEN_KEYS = [
  'database_password', 'redis_password', 'stripe_secret_key',
  'mail_password', 'global_secret', 'secret_key_base',
  'database_url', 'redis_url'  // full connection strings
];
```

#### Security Tokens That ARE Exposed
- `shrimp`: CSRF token (changes per request, safe to expose)
- `nonce`: CSP nonce (safe, designed for frontend)
- `apitoken`: User's API token (only when authenticated, user's own token)

### Test Architecture Patterns

#### WindowService Integration Tests
**File**: `services/window-service-integration.spec.ts`
**Purpose**: Tests the service layer that abstracts window access
**Key Patterns**:
- Test error conditions (undefined window, missing state)
- Test both `get()` and `getMultiple()` patterns
- Validate type safety at runtime
- Performance testing for large property requests

#### Zod Schema Validation Tests
**File**: `services/window-state-validation.spec.ts`
**Purpose**: Runtime validation of JSON payload structure
**Key Patterns**:
- Comprehensive schema definition covering all window properties
- Tests with realistic data that matches actual Ruby output
- Error validation for type mismatches and missing fields
- Compatibility checks with TypeScript interfaces

### Critical Type Safety Considerations

#### User State Variations
Tests must cover these user states:
```typescript
// Anonymous user
cust: null, authenticated: false, custid: null

// Authenticated user
cust: CustomerObject, authenticated: true, custid: "string"

// Edge case: corrupted state
cust: {}, authenticated: true  // should be handled gracefully
```

#### Plan Structure Validation
Plans have complex nested structure - validate:
```typescript
plan: {
  identifier: string,
  planid: string,
  price: number,
  options: {
    ttl: number,
    size: number,
    api: boolean,
    // Optional enterprise features
    email?: boolean,
    custom_domains?: boolean,
    dark_mode?: boolean
  }
}
```

### Internationalization Data Structure

#### Critical i18n Fields
Always present and required for Vue i18n:
- `locale`: Current user locale
- `default_locale`: Fallback locale
- `supported_locales`: Array of available locales
- `fallback_locale`: Complex object or string for vue-i18n

#### Fallback Locale Structure
Can be either:
```typescript
// Simple string fallback
fallback_locale: "en"

// Complex regional fallback
fallback_locale: {
  "fr-CA": ["fr_CA", "fr_FR", "en"],
  "de-AT": ["de_AT", "de", "en"],
  "default": ["en"]
}
```

### Configuration Section Validation Priorities

#### High Priority (Required for App Function)
1. `authentication`: Controls login/signup availability
2. `secret_options`: TTL limits and secret size limits
3. `locale`/`i18n_enabled`: Required for text rendering
4. `ot_version`: Used for compatibility checks

#### Medium Priority (Feature Flags)
1. `domains_enabled`: Custom domain features
2. `regions_enabled`: Geographic data handling
3. `plans_enabled`: Subscription features
4. `d9s_enabled`: Diagnostics and error reporting

#### Low Priority (UI Enhancement)
1. `ui.header`: Branding customization
2. `ui.footer_links`: Footer configuration
3. `global_banner`: Admin messages
4. `domain_branding`: Visual customization

### Test Data Management

#### Fixture Strategy
- **Primary Fixture**: `fixtures/window.fixture.ts` - comprehensive realistic data
- **Setup Functions**: `setupWindow.ts` - test utilities for state manipulation
- **Zod Schema**: Embedded in validation tests for runtime checking

#### Cross-Branch Testing Strategy
Tests should:
1. Focus on structure, not specific values (config values change between branches)
2. Validate presence and types of all required fields
3. Test error conditions and edge cases
4. Ensure security boundaries are maintained

### Error Handling Patterns

#### WindowService Error Scenarios
```typescript
// SSR scenarios
window === undefined  // Should throw clear error

// Missing state
window.onetime === undefined  // Should throw clear error

// Corrupted state
window.onetime === "string"  // Type assertion will fail gracefully
```

#### Graceful Degradation
Tests should verify:
- Missing optional fields don't break the app
- Invalid nested objects are handled
- Array type validation (ttl_options, supported_locales)
- Null vs undefined handling consistency

### Performance Considerations

#### WindowService Caching
- No caching between `get()` calls (each call re-reads window.onetime)
- `getMultiple()` makes single window access per call
- Large property requests should complete < 50ms

#### Memory Usage
- Window state is read-only after injection
- Tests should not modify window.onetime directly
- Use setupWindow utilities for test state management

### Debugging Tips

#### Common Test Failures
1. **Type mismatches**: Check Zod schema vs TypeScript interface alignment
2. **Missing properties**: Verify fixture completeness vs OnetimeWindow interface
3. **Setup issues**: Ensure setupWindowState() called before WindowService usage
4. **Async issues**: Window state is synchronous, no async setup needed

#### Development Workflow
1. Add new window properties to `OnetimeWindow` interface first
2. Update Zod schema in validation tests
3. Add to fixture data
4. Update integration tests to cover new property
5. Verify Ruby backend provides the new property
