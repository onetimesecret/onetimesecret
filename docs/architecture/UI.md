# UI - Vue 3 Application Architecture Guide

## Introduction

Designing a Vue.js application with a clear and well-structured architecture is essential for building scalable and maintainable projects. This guide presents an approach to architecting a Vue 3 application by organizing it into distinct layers: **Schemas**, **Services**, **Stores**, **Composables**, and **Components**. Each layer has a specific role:

- **Schemas**: Define data structures and types, ensuring type safety and data validation.
- **Services**: Handle API communication, utilizing schemas for validating responses.
- **Stores**: Manage application state, leveraging services for data fetching and updating.
- **Composables**: Provide reusable logic by combining store functionalities, simplifying component code.
- **Components**: Focus on the presentation layer, using composables for logic and interaction.

This layered architecture promotes modularity, reusability, and testability. By leveraging TypeScript for type safety and [Zod](https://github.com/colinhacks/zod) schemas for runtime validation, data consistency is maintained, and errors are caught early in the development process. This structured approach facilitates easier maintenance, clearer code organization, and an efficient development workflow for building robust Vue.js applications.

## Table of Contents

- Architecture Overview
  - Schema Layer
  - Service Layer
  - Store Layer
  - Composable Layer
  - Component Layer
- Key Benefits
- Common Patterns
- Full Code Examples
- Contributing
- License

## Architecture Overview

### Schema Layer (Bottom)

Defines data structures, validates API responses, and provides TypeScript types.

```typescript
// schemas/user.ts
export const userSchema = z.object({ /* ... */ });
export type User = z.infer<typeof userSchema>;
```

- Defines the data structures and types.
- Validates API responses to ensure data integrity.
- Provides a single source of truth for data shapes.

### Service Layer (Next Up)

Handles API communication, uses schemas for validation, and returns typed responses.

```typescript
// services/userService.ts
export class UserService {
  async getUser(id: string): Promise<User> {
    // Implementation details
  }
}
```

- Isolates API logic, making it easier to manage and test.
- Uses schemas to validate data received from the API.
- Does not manage any application state.

### Store Layer (Middle)

Manages application state, uses services for data fetching, and handles loading/error states.

```typescript
// stores/useUserStore.ts
export const useUserStore = defineStore('user', () => {
  // State and actions
});
```

- Centralizes business logic and state management.
- Provides reactive data and computed properties.
- Handles asynchronous operations and error states.

### Composable Layer (Higher)

Combines store functionality, adds component-specific logic, and provides reusable logic.

```typescript
// composables/useUser.ts
export function useUser(userId?: string) {
  // Composable logic
}
```

- Simplifies component code by abstracting logic.
- Manages component lifecycle events.
- Provides a reusable interface for components.

### Component Layer (Top)

Uses composables for logic and focuses on the presentation and user interactions.

```vue
<!-- components/UserProfile.vue -->
<template>
  <!-- Template code -->
</template>

<script setup lang="ts">
// Component logic
</script>
```

- Focuses on the UI and presentation logic.
- Interacts with composables for data and actions.
- Handles user interactions and events.

## Key Benefits

### Type Safety Throughout

- Schemas define types that flow through all layers.
- Ensures compile-time checking and runtime validation.

### Separation of Concerns

- **Services**: Handle API communication.
- **Stores**: Manage application state.
- **Composables**: Provide reusable logic.
- **Components**: Focus on UI presentation.

### Testability

- Easy to test services:

  ```typescript
  // Example test
  test('UserService.getUser', async () => {
    // Test implementation
  });
  ```

- Easy to test stores:

  ```typescript
  // Example test
  test('useUserStore', () => {
    // Test implementation
  });
  ```

### Maintainability

- Clear responsibilities for each layer.
- Modular architecture allows easy refactoring.
- Reusable code components.

### Error Handling

- **Service Level**: Handles API errors and response validation.
- **Store Level**: Manages state-related errors.
- **Component Level**: Displays errors to the user.

## Common Patterns

### Data Flow

```
Component -> Composable -> Store -> Service -> API
     ↑          ↑           ↑         ↑
   render    useState    useState   validate
```

### Error Handling

```
API Error -> Service -> Store -> Composable -> Component
     ↓          ↓         ↓          ↓
 validate   transform   state    UI display
```

### State Management

```
Service (stateless)
  ↓
Store (global state)
  ↓
Composable (local state)
  ↓
Component (UI state)
```

## Full Code Examples

Below are illustrative full code examples for each layer. Note that these examples are for demonstration purposes and may not directly correspond to the actual implementation in the project. They serve to showcase the architectural patterns and coding style recommendations.

### Schema Layer

```typescript
// schemas/user.ts
import { z } from 'zod';

export const userSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string(),
  role: z.enum(['admin', 'user']),
  createdAt: z.string().datetime()
});

export const createUserSchema = userSchema.omit({
  id: true,
  createdAt: true
});

export type User = z.infer<typeof userSchema>;
export type CreateUserInput = z.infer<typeof createUserSchema>;
```

### Service Layer

```typescript
// services/userService.ts
import { HttpApiClient } from '@/utils/apiClient';
import { User, CreateUserInput, userSchema } from '@/schemas/user';

export class UserService {
  constructor(private api: HttpApiClient) {}

  async getUser(id: string): Promise<User> {
    const response = await this.api.get(`/users/${id}`, userSchema);
    return response.data;
  }

  async createUser(data: CreateUserInput): Promise<User> {
    const response = await this.api.post('/users', data, userSchema);
    return response.data;
  }

  async updateUser(id: string, data: Partial<CreateUserInput>): Promise<User> {
    const response = await this.api.put(`/users/${id}`, data, userSchema);
    return response.data;
  }
}
```

### Store Layer

```typescript
// stores/useUserStore.ts
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { User } from '@/schemas/user';
import { UserService } from '@/services/userService';
import { createApi } from '@/utils/apiClient';

export const useUserStore = defineStore('user', () => {
  // State
  const currentUser = ref<User | null>(null);
  const users = ref<User[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);

  // Service instance
  const userService = new UserService(createApi());

  // Getters
  const isAdmin = computed(() => currentUser.value?.role === 'admin');

  const sortedUsers = computed(() =>
    [...users.value].sort((a, b) => a.name.localeCompare(b.name))
  );

  // Actions
  async function fetchUser(id: string) {
    loading.value = true;
    error.value = null;

    try {
      currentUser.value = await userService.getUser(id);
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Failed to fetch user';
      throw e;
    } finally {
      loading.value = false;
    }
  }

  async function createUser(data: CreateUserInput) {
    loading.value = true;
    error.value = null;

    try {
      const newUser = await userService.createUser(data);
      users.value.push(newUser);
      return newUser;
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Failed to create user';
      throw e;
    } finally {
      loading.value = false;
    }
  }

  return {
    currentUser,
    users,
    loading,
    error,
    isAdmin,
    sortedUsers,
    fetchUser,
    createUser
  };
});
```

### Composable Layer

```typescript
// composables/useUser.ts
import { ref, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useUserStore } from '@/stores/useUserStore';
import { CreateUserInput } from '@/schemas/user';

export function useUser(userId?: string) {
  const userStore = useUserStore();
  const { currentUser, loading, error } = storeToRefs(userStore);
  const saveError = ref<string | null>(null);

  async function handleCreateUser(data: CreateUserInput) {
    saveError.value = null;
    try {
      await userStore.createUser(data);
    } catch (e) {
      saveError.value = e instanceof Error ? e.message : 'Failed to save user';
      throw e;
    }
  }

  // Load user data if ID is provided
  onMounted(async () => {
    if (userId) {
      await userStore.fetchUser(userId);
    }
  });

  return {
    user: currentUser,
    loading,
    error,
    saveError,
    createUser: handleCreateUser,
    isAdmin: userStore.isAdmin
  };
}
```

### Component Layer

```vue
<!-- components/UserProfile.vue -->
<template>
  <div>
    <div v-if="loading">Loading...</div>
    <div v-else-if="error">{{ error }}</div>
    <div v-else-if="user">
      <h2>{{ user.name }}</h2>
      <p>{{ user.email }}</p>
      <span v-if="isAdmin" class="badge">Admin</span>
    </div>

    <div v-if="saveError" class="error">
      {{ saveError }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { useUser } from '@/composables/useUser';
import { CreateUserInput } from '@/schemas/user';

const props = defineProps<{
  userId?: string;
}>();

const {
  user,
  loading,
  error,
  saveError,
  createUser,
  isAdmin
} = useUser(props.userId);

async function handleSubmit(formData: CreateUserInput) {
  try {
    await createUser(formData);
    // Handle success
  } catch (e) {
    // Handle error
  }
}
</script>
```

## Contributing

Contributions are welcome! Please follow the project's contribution guidelines when submitting changes.

## License

This project is open-source and available under the MIT License.
