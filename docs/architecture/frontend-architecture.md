# Frontend Architecture

## Layered Design

Vue 3 application organized in distinct layers with clear responsibilities:

```
Component → Composable → Store → Service → API
```

### Schema Layer
Defines data structures and validation:

```typescript
// schemas/user.ts
export const userSchema = z.object({
  id: z.string().uuid(),
  email: z.email(),
  name: z.string(),
  createdAt: z.string().datetime(),
});

export type User = z.infer<typeof userSchema>;
```

### Service Layer
Handles API communication with validation:

```typescript
// services/userService.ts
export class UserService {
  async getUser(id: string): Promise<User> {
    const response = await this.api.get(`/users/${id}`, userSchema);
    return response.data;
  }
}
```

### Store Layer
Manages application state:

```typescript
// stores/useUserStore.ts
export const useUserStore = defineStore('user', () => {
  const currentUser = ref<User | null>(null);
  const loading = ref(false);

  async function fetchUser(id: string) {
    loading.value = true;
    try {
      currentUser.value = await userService.getUser(id);
    } finally {
      loading.value = false;
    }
  }

  return { currentUser, loading, fetchUser };
});
```

### Composable Layer
Provides reusable business logic:

```typescript
// composables/useUser.ts
export function useUser(userId?: string) {
  const userStore = useUserStore();
  const { currentUser, loading } = storeToRefs(userStore);

  onMounted(async () => {
    if (userId) await userStore.fetchUser(userId);
  });

  return { user: currentUser, loading };
}
```

### Component Layer
Focuses on presentation:

```vue
<template>
  <div v-if="loading">Loading...</div>
  <div v-else-if="user">
    <h2>{{ user.name }}</h2>
    <p>{{ user.email }}</p>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{ userId?: string }>();
const { user, loading } = useUser(props.userId);
</script>
```

## Key Benefits

**Separation of Concerns**: Each layer has a single responsibility.

**Type Safety**: Types flow from schemas through all layers.

**Testability**: Easy to test each layer independently.

**Reusability**: Composables provide shared logic across components.

## Common Patterns

### Data Flow
1. Component calls composable
2. Composable uses store
3. Store calls service
4. Service validates with schema

### Error Boundaries
- Service: API errors and validation
- Store: State-related errors
- Composable: Business logic errors
- Component: UI error display

### State Management
- Services are stateless
- Stores manage global state
- Composables handle local state
- Components manage UI state
