# Composables Error Handling Architecture

## Overview

This document describes the standardized error handling pattern used across all composables in this application. Following this pattern ensures consistent user experience, proper error classification, and maintainable code.

## Architecture

### Error Flow

```
┌─────────────┐
│   Store     │ ──── throws errors (Zod validation, Axios, createError)
└─────────────┘
       │
       ▼
┌─────────────┐
│ Composable  │ ──── catches with useAsyncHandler
└─────────────┘
       │
       ▼
┌─────────────┐
│  Classifier │ ──── categorizes: human | security | technical
└─────────────┘
       │
       ├──► User Notification (human/security errors)
       ├──► Error Logging (technical/security errors)
       └──► Sentry (technical/security errors)
```

### Key Principles

1. **Stores throw, composables catch**: Business logic in stores throws errors; composables handle them via `useAsyncHandler`
2. **Structured classification**: All errors are typed as `human`, `security`, or `technical`
3. **Consistent UX**: Error messages follow i18n patterns, notifications are standardized
4. **Observability**: Technical/security errors are logged; human errors are not

## Using useAsyncHandler

### Basic Pattern

```typescript
import { useAsyncHandler } from '@/composables/useAsyncHandler';
import { useNotificationsStore } from '@/stores';

export function useMyFeature() {
  const notifications = useNotificationsStore();
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  // Configure handler
  const { wrap } = useAsyncHandler({
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => isLoading.value = loading,
    onError: (err) => error.value = err
  });

  // Wrap async operations
  async function fetchData() {
    const result = await wrap(async () => {
      const response = await store.fetchSomething();
      return response;
    });
    return result ?? null;
  }

  return { isLoading, error, fetchData };
}
```

### AsyncHandlerOptions

| Option | Type | Purpose | Default |
|--------|------|---------|---------|
| `notify` | `(message, severity) => void \| false` | User notifications | Console logging |
| `log` | `(error: ApplicationError) => void \| false` | Error logging | loggingService.error |
| `setLoading` | `(isLoading: boolean) => void` | Loading state | noop |
| `onError` | `(error: ApplicationError) => void` | Pre-throw callback | undefined |
| `sentry` | `SentryInstance` | Error tracking | Auto-injected |

### Auth-Specific Pattern

Auth composables have special requirements (inline errors, no auto-notification):

```typescript
export function useAuth() {
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const fieldError = ref<[string, string] | null>(null);

  const { wrap } = useAsyncHandler({
    // Don't auto-notify - auth shows errors inline
    notify: false,
    setLoading: (loading) => isLoading.value = loading,
    onError: (err) => {
      // IMPORTANT: Clear all error state first to prevent stale data
      // from previous errors showing alongside new errors
      error.value = null;
      fieldError.value = null;

      // Set new error state
      error.value = err.message;
      if (err.details?.['field-error']) {
        fieldError.value = err.details['field-error'];
      }
    }
  });

  async function login(email: string, password: string) {
    const result = await wrap(async () => {
      const response = await $api.post('/auth/login', { login: email, password });
      const validated = loginResponseSchema.parse(response.data);

      if (isAuthError(validated)) {
        throw createError(validated.error, 'human', 'error', {
          'field-error': validated['field-error']
        });
      }

      await authStore.setAuthenticated(true);
      return true;
    });

    return result ?? false;
  }
}
```

**Key principle**: When handling multiple error-related state fields (error, fieldError, lockoutStatus, etc.), always clear ALL of them in `onError` before setting new values. Otherwise, fields from previous errors can persist when the new error doesn't include them.

## Error Classification

### Classification Rules

The error classifier uses a **message-driven approach** for client errors (4xx), trusting the backend to signal intent:

1. **Field errors always = human**: If `field-error` is present, it's form validation → human error
2. **User-friendly message + 4xx = human** (except 429): Backend sending a friendly error message signals it's user-actionable
3. **Rate limiting (429) = security**: Always classified as security, even with a message
4. **No message = status-based**: Falls back to HTTP status code classification rules
5. **5xx errors = technical**: Server errors are always technical

This approach is **backend-controlled**: the backend decides classification by choosing to include a user-friendly message or not.

### Error Types

- **`human`**: User-facing errors that users can understand and act on
  - Shown to user via notifications or inline
  - NOT logged or sent to Sentry
  - Examples: "Email already exists", "Password too short", "Account pending verification", "Invalid email format"
  - Triggers: 4xx with `field-error`, 4xx with user message, 404, 422, 400

- **`security`**: Security policy enforcement and rate limiting
  - Generic message shown to user (or specific if provided)
  - Logged and sent to Sentry
  - Examples: "Too many requests", "Access denied" (generic 401/403 without message)
  - Triggers: 429 (always), 401/403/423 without friendly message

- **`technical`**: System errors and infrastructure issues
  - Generic message shown to user
  - Logged and sent to Sentry
  - Examples: "Network error", "Server error", "Service unavailable"
  - Triggers: 5xx errors, network failures, no response

### Rodauth Error Format

Backend responses follow Rodauth's format with `error` field (not `message`):

```json
{
  "error": "The account you tried to create is currently awaiting verification",
  "field-error": ["email", "already_exists"]
}
```

The error classifier automatically extracts messages from both `error` and `message` fields for compatibility.

**Key insight**: If Rodauth (or any backend) sends a user-friendly `error` message for a 4xx status, it's automatically classified as human-actionable, regardless of whether it's 400, 403, 409, or 422.

### Creating Custom Errors

```typescript
import { createError } from '@/composables/useAsyncHandler';

// Human error with details
throw createError(
  'Invalid email format',
  'human',
  'error',
  { 'field-error': ['email', 'invalid'] }
);

// Security error
throw createError(
  'Rate limit exceeded',
  'security',
  'warning',
  { retryAfter: 60 }
);

// Technical error
throw createError(
  'Database connection failed',
  'technical',
  'error'
);
```


### Real-World Examples

1. Backend-controlled: Backend decides classification by including a user-friendly message
2. No special cases: Works for 400, 401, 403, 409, 422 - any 4xx
3. Clear heuristic: User message = user can act on it
4. Flexible: Backend can change message presence without frontend changes
5. Backward compatible: Falls back to status-code rules when no message


```
| Scenario          | Status | Message                 | Classification | Why                  |
|-------------------|--------|-------------------------|----------------|----------------------|
| Account pending   | 403    | "awaiting verification" | human          | Has message          |
| Generic forbidden | 403    | (none)                  | security       | No message           |
| Email exists      | 409    | "already in use"        | human          | Has message          |
| Rate limited      | 429    | "too many requests"     | security       | Exception rule       |
| Wrong password    | 401    | "invalid credentials"   | human          | Has message          |
| Server error      | 500    | (any)                   | technical      | 5xx always technical |
```

## Common Patterns

### Pattern 1: Simple Store Call

```typescript
async function fetchList() {
  return await wrap(async () => {
    return await store.fetchList();
  });
}
```

### Pattern 2: With Post-Processing

```typescript
async function getDomain(name: string) {
  return await wrap(async () => {
    const data = await store.getDomain(name);
    // Additional processing
    const canVerify = data.lastUpdated > threshold;
    return { ...data, canVerify };
  });
}
```

### Pattern 3: With Navigation

```typescript
async function deleteDomain(id: string) {
  const result = await wrap(async () => {
    await store.deleteDomain(id);
    notifications.show('Domain deleted', 'success');
    return true;
  });

  if (result) {
    router.push('/domains');
  }
}
```

### Pattern 4: Custom Error Handling

```typescript
const { wrap } = useAsyncHandler({
  notify: (message, severity) => notifications.show(message, severity),
  setLoading: (loading) => isLoading.value = loading,
  onError: (err) => {
    // Custom logic based on error type
    if (err.code === 404) {
      router.push({ name: 'NotFound' });
    }
    error.value = err;
  }
});
```

## Anti-Patterns to Avoid

### ❌ Manual Try/Catch

```typescript
// DON'T DO THIS
async function login() {
  try {
    isLoading.value = true;
    const response = await api.login();
    return response.data;
  } catch (err) {
    error.value = err.message;
    return null;
  } finally {
    isLoading.value = false;
  }
}
```

### ❌ Direct Notification Calls

```typescript
// DON'T DO THIS
async function save() {
  const result = await wrap(async () => {
    await store.save();
    notifications.show('Saved!', 'success'); // ❌
    return true;
  });
}

// DO THIS INSTEAD
async function save() {
  const result = await wrap(async () => {
    await store.save();
    return true;
  });

  if (result) {
    notifications.show('Saved!', 'success'); // ✅
  }
}
```

### ❌ Swallowing Errors

```typescript
// DON'T DO THIS
try {
  await fetchData();
} catch {
  // Silent failure - no classification, no logging
}

// DO THIS INSTEAD
await wrap(async () => {
  await fetchData();
});
```

## Migration Checklist

When migrating existing composables to use `useAsyncHandler`:

- [ ] Import `useAsyncHandler` from `@/composables/useAsyncHandler`
- [ ] Configure handler options (`notify`, `setLoading`, `onError`)
- [ ] Replace all try/catch blocks with `wrap()` calls
- [ ] Remove manual `isLoading.value = true/false` assignments
- [ ] Remove direct calls to `notifications.show()` inside wrapped operations
- [ ] Ensure errors thrown in stores use `createError()` with proper type
- [ ] Test error scenarios (network failures, validation errors, auth failures)
- [ ] Verify loading states work correctly
- [ ] Check that user notifications appear as expected

## Testing Error Handling

### Unit Tests

```typescript
import { describe, it, expect, vi } from 'vitest';

describe('useMyFeature', () => {
  it('handles errors via useAsyncHandler', async () => {
    const { fetchData, error } = useMyFeature();

    // Mock store to throw error
    vi.spyOn(store, 'fetchSomething').mockRejectedValue(
      new Error('Network error')
    );

    await fetchData();

    expect(error.value).toBeTruthy();
    expect(error.value?.type).toBe('technical');
  });
});
```

### Manual Testing Scenarios

- Wrong credentials → human error, inline message
- Server down → technical error, generic notification
- Rate limited → security error, notification + log
- Validation failure → human error, field-specific message

## Reference Implementations

- **`src/composables/useDomainsManager.ts`** - Full implementation with custom error handling
- **`src/composables/useSecret.ts`** - Clean, minimal usage
- **`src/composables/useMetadata.ts`** - Error state management
- **`src/composables/usePasswordChange.ts`** - Form-based error handling

## Related Files

- `src/composables/useAsyncHandler.ts` - Core composable
- `src/schemas/errors/classifier.ts` - Error classification logic
- `src/schemas/errors/guards.ts` - Type guards
- `src/plugins/core/globalErrorBoundary.ts` - Global Vue error handler
- `src/stores/notificationsStore.ts` - User notifications
