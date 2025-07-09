# Vue Frontend Testing Guidelines - Data Boundary Validation

**PROCESSING NOTE**: Content up to "Detailed Implementation Guidelines" section contains CRITICAL context for immediate testing decisions. Content below that section provides detailed reference material - consult only when specific implementation details are needed.

## CRITICAL: Window State Access & Security Boundaries

### 🚨 Window State Access Pattern - MUST FOLLOW
```typescript
// CORRECT: Always use WindowService
import { WindowService } from '@/services/window-service';
const value = WindowService.get('property');

// WRONG: Never access directly
const value = window.onetime.property;  // ❌ FORBIDDEN
```

**Key Facts:**
- Window state lives at `window.onetime` (NOT `window.__ONETIME_STATE__`)
- ALL access MUST go through `WindowService` - no exceptions
- State key is `const STATE_KEY: string = 'onetime'` in WindowService

### 🔒 SECURITY CRITICAL: Forbidden Keys
These fields indicate a **SECURITY BREACH** if found in window state:
```typescript
const FORBIDDEN_KEYS = [
  'database_password', 'redis_password', 'stripe_secret_key',
  'mail_password', 'global_secret', 'secret_key_base',
  'database_url', 'redis_url'  // full connection strings
];

// In tests: ALWAYS verify these are absent
expect(window.onetime).not.toHaveProperty('database_password');
```

**Safe Tokens** (designed for frontend exposure):
- `shrimp`: CSRF token (rotates per request)
- `nonce`: CSP nonce (for script security)
- `apitoken`: User's own API token (only when authenticated)

### 📋 Essential Test Patterns

#### 1. WindowService Error Handling
```typescript
// SSR scenario - window undefined
expect(() => WindowService.get('any')).toThrow('Window is not defined');

// Missing state object
window.onetime = undefined;
expect(() => WindowService.get('any')).toThrow('Window state not initialized');

// Type mismatch handling
window.onetime = "corrupted";  // Wrong type
expect(() => WindowService.get('any')).toThrow();
```

#### 2. User State Variations (MUST TEST ALL)
```typescript
// Anonymous user - most common case
{ cust: null, authenticated: false, custid: null }

// Authenticated user
{ cust: CustomerObject, authenticated: true, custid: "cus_12345" }

// Corrupted state - must handle gracefully
{ cust: {}, authenticated: true }  // Missing custid!
```

#### 3. Type Safety with Zod Validation
```typescript
// Always validate runtime data matches TypeScript types
const result = OnetimeWindowSchema.safeParse(window.onetime);
if (!result.success) {
  console.error('Window state validation failed:', result.error);
}
```

### 🎯 Key Type Safety Considerations

#### Complex Nested Objects
```typescript
// Plan structure - validate ALL fields
plan: {
  identifier: string,      // e.g., "professional"
  planid: string,         // e.g., "pro_monthly"
  price: number,          // in cents
  options: {
    ttl: number,          // max TTL in seconds
    size: number,         // max secret size
    api: boolean,         // API access enabled
    // Optional enterprise features
    email?: boolean,
    custom_domains?: boolean,
    dark_mode?: boolean
  }
}

// i18n fallback structure - can be string OR complex object
fallback_locale: "en" | {
  "fr-CA": ["fr_CA", "fr_FR", "en"],
  "de-AT": ["de_AT", "de", "en"],
  "default": ["en"]
}
```

#### Array Type Validation
```typescript
// These MUST be arrays, never null/undefined
ttl_options: number[]        // e.g., [300, 1800, 3600]
supported_locales: string[]  // e.g., ["en", "fr", "de"]
recent_burnafterreading: boolean[] // feature flags per secret
```

---

## 📚 Quick Reference Index

### Test File Organization
- **Integration Tests**: `services/window-service-integration.spec.ts`
- **Validation Tests**: `services/window-state-validation.spec.ts`
- **Fixtures**: `fixtures/window.fixture.ts`
- **Setup Utilities**: `setupWindow.ts`

### Detailed Sections Below
1. **Internationalization Data Structure** → Essential i18n fields and fallback patterns
2. **Configuration Validation Priorities** → High/Medium/Low priority config fields
3. **Test Data Management Strategy** → Fixtures, setup functions, cross-branch testing
4. **Error Handling Patterns** → WindowService errors and graceful degradation
5. **Performance Considerations** → Caching behavior and memory usage
6. **Debugging Tips & Workflow** → Common failures and development process

---

## Detailed Implementation Guidelines

### 1. Internationalization Data Structure

#### Critical i18n Fields
Always present and required for Vue i18n:
- `locale`: Current user locale (e.g., "en", "fr-CA")
- `default_locale`: System fallback locale
- `supported_locales`: Array of available locales
- `fallback_locale`: Complex object or string for vue-i18n

#### Fallback Locale Structure
Can be either:
```typescript
// Simple string fallback
fallback_locale: "en"

// Complex regional fallback (production pattern)
fallback_locale: {
  "fr-CA": ["fr_CA", "fr_FR", "en"],
  "de-AT": ["de_AT", "de", "en"],
  "default": ["en"]
}
```

### 2. Configuration Section Validation Priorities

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

### 3. Test Data Management Strategy

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

### 4. Error Handling Patterns

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

### 5. Performance Considerations

#### WindowService Caching
- No caching between `get()` calls (each call re-reads window.onetime)
- `getMultiple()` makes single window access per call
- Large property requests should complete < 50ms

#### Memory Usage
- Window state is read-only after injection
- Tests should not modify window.onetime directly
- Use setupWindow utilities for test state management

### 6. Debugging Tips & Development Workflow

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
