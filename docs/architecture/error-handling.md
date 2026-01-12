# Error Handling

## Core Concepts

### Vue Error Boundaries
Handle component errors (template, render, lifecycle):

```typescript
// Component level
errorCaptured(error, instance, info) {
  logError(error, { component: instance?.$options?.name })
  return false // Stop propagation
}

// Global level
app.config.errorHandler = (error) => {
  logError(error)
}
```

### Async Operations
Vue error boundaries don't catch async errors. Handle explicitly:

```typescript
// ❌ Uncaught error
onMounted(async () => {
  await api.getData()
})

// ✅ Proper handling
onMounted(async () => {
  try {
    await api.getData()
  } catch (error) {
    handleError(error)
  }
})
```

## Error Types

### Result Pattern for Expected Failures
```typescript
type Result<T, E> =
  | { status: 'success', data: T }
  | { status: 'error', error: E }

async function createSecret(data: SecretInput): Promise<Result<Secret, ValidationError>> {
  const result = await api.createSecret(data)

  if (result.status === 'error') {
    return failure(mapToValidationError(result.error))
  }

  return success(result.data)
}
```

### Exception for Programming Errors
```typescript
function requireUser(user: User | undefined): User {
  if (!user) throw new Error('User required but not found')
  return user
}
```

## Layer Responsibilities

### API Layer
Convert HTTP errors to domain types:

```typescript
export class ApiClient {
  async request<T>(endpoint: string): Promise<Result<T, ApiError>> {
    try {
      const response = await fetch(endpoint)
      if (!response.ok) {
        return failure(this.mapHttpError(await response.json()))
      }
      return success(await response.json())
    } catch (error) {
      return failure(this.mapNetworkError(error))
    }
  }
}
```

### Store Layer
Manage state errors, propagate with context:

```typescript
export const useSecretStore = defineStore('secret', () => {
  const error = ref<ApiError | null>(null)

  async function fetchSecret(id: string) {
    const result = await api.getSecret(id)

    if (result.status === 'error') {
      error.value = result.error
      return failure(result.error)
    }

    return success(result.data)
  }
})
```

### Composable Layer
Transform to domain errors:

```typescript
export function useSecretManagement() {
  async function createSecret(input: SecretInput): Promise<Result<Secret, DomainError>> {
    const result = await store.createSecret(input)

    if (result.status === 'error') {
      return failure(mapToDomainError(result.error))
    }

    return success(result.data)
  }
}
```

### Component Layer
Display errors to users:

```vue
<template>
  <div v-if="error" class="error">
    {{ getErrorMessage(error) }}
  </div>
</template>
```

## Global Handlers

### Unhandled Rejections
```typescript
window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled async error:', event.reason)
  logError(event.reason)
  event.preventDefault()
})
```

### Error Boundary Component
```vue
<script setup lang="ts">
const error = ref<Error | null>(null)

onErrorCaptured((err, instance, info) => {
  error.value = err
  logError(err, { component: instance?.$options?.name, info })
  return false
})
</script>

<template>
  <div v-if="error" class="error-boundary">
    <h2>Something went wrong</h2>
    <button @click="error = null">Try Again</button>
  </div>
  <slot v-else></slot>
</template>
```

## Decision Framework

**Use Result types when:**
- Failure is expected business logic
- Different error types need different handling
- Type safety is critical

**Use exceptions when:**
- Programming error that needs immediate attention
- Working at framework boundaries
- Unrecoverable states
