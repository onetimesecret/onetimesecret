# Vue 3 Error Handling Guide

Clear patterns for handling errors in Vue 3 applications.

## Core Concepts

### Component Errors
Vue's error boundaries catch template, render and lifecycle errors in synchronous code:

```ts
// Component level
errorCaptured(error, instance, info) {
  return false // Stop propagation
}

// Global level
app.config.errorHandler = (error) => {
  logError(error)
}
```

### Async Operations
Async errors are not caught by Vue's error boundaries. Always handle explicitly:

```ts
// ❌ Error escapes Vue's error handling
onMounted(async () => {
  await api.getData() // Uncaught error
})

// ✅ Proper async error handling
onMounted(async () => {
  try {
    await api.getData()
  } catch (error) {
    handleError(error)
  }
})
```

### Business Logic
Use try/catch for synchronous operations that may fail:

```ts
function processData(input: string) {
  try {
    return transform(input)
  } catch (error) {
    // Expected errors can be handled explicitly
    if (error instanceof ValidationError) {
      return handleValidation(error)
    }
    // Unexpected errors can be propagated to error boundaries
    throw error
  }
}
```

## Error Handling Hierarchy

1. Component-level errors -> Vue error boundaries
2. Async operations -> try/catch or .catch()
3. Expected business errors -> local try/catch
4. Uncaught async errors -> window.onunhandledrejection

Note: It can be helpful to separate error handling from business logic. For consistency across and for clarity in the business logic code.

This is why many Vue applications use error handling utilities or middleware to ensure consistent handling of async errors.

## Common Patterns

### API Error Handler
```ts
export function useApiError() {
  return {
    handleError(error: unknown) {
      if (error instanceof NetworkError) {
        notify('Connection lost')
        return
      }
      if (error instanceof ValidationError) {
        return { valid: false, errors: error.details }
      }
      throw error // Let error boundaries handle unknown errors
    }
  }
}
```

### Global Rejection Catch-all
```ts
window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled async error:', event.reason)
  event.preventDefault()
})
```

## Prompt

Prompt used to create this guide.

> Adapt the keystone content into the vue 3 error handling doc that is written with
> the intent to educate without being verbose or pedantic. Emphasize content that
> would be considered surprising -- don't describe it as such, but make sure it is
> clear and easy to understand.
