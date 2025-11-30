
Keep Secret State separate from Exchange Context.

Mixing "Environmental Context" (Branding/Audience) with "Entity State" (Secret Lifecycle) violates Single Responsibility Principle and creates testing nightmares.

useExchangeContext() answers: "Where are we?" (Domain) and "Who is looking?" (Identity).
useSecretLifecycle() answers: "What is the status of this specific data?"

You should model the Secret Lifecycle as a Finite State Machine (FSM).

**Separate them.**

Mixing "Environmental Context" (Branding/Audience) with "Entity State" (Secret Lifecycle) violates Single Responsibility Principle and creates testing nightmares.

**`useExchangeContext()`** answers: "Where are we?" (Domain) and "Who is looking?" (Identity).
**`useSecretLifecycle()`** answers: "What is the status of this specific data?"

You should model the Secret Lifecycle as a **Finite State Machine (FSM)**.

### 1. The Separation of Concerns

#### A. The Context (The Stage)
**`useExchangeContext.ts`**
Synchronous. Driven by Window config, URL params, and Cookies.
*   **Responsibility:** Determines the "Skin" of the application.
*   **Outputs:** `isBranded`, `brandColors`, `isAuthenticated`, `displayMode` (Canonical vs Custom).

#### B. The State (The Actor)
**`useSecretLifecycle.ts`**
Asynchronous. Driven by API responses.
*   **Responsibility:** Manages the transitions defined in your matrix.
*   **Outputs:** `currentState`, `secretContent`, `metadata`, `error`.

---

### 2. Implementing the State Machine

Your matrix is effectively a state chart. Implement it as such to prevent impossible UI states (e.g., showing a "Burn" button on an "Expired" secret).

```typescript
// src/apps/exchange/composables/useSecretLifecycle.ts

export type SecretState = 
  | 'idle'          // Initial loading
  | 'passphrase'    // Exists, but locked
  | 'ready'         // Exists, ready to reveal (click to view)
  | 'revealed'      // Content is visible
  | 'burned'        // Intentionally destroyed
  | 'expired'       // Time ran out
  | 'unknown';      // 404

export function useSecretLifecycle(secretKey: string) {
  const state = ref<SecretState>('idle');
  const secret = ref<SecretPayload | null>(null);
  
  // Actions that transition state
  const fetch = async () => {
    try {
      const data = await api.getSecret(secretKey);
      
      if (data.state === 'burned') return state.value = 'burned';
      if (data.has_passphrase && !data.unlocked) return state.value = 'passphrase';
      
      state.value = 'ready';
    } catch (e) {
      state.value = e.status === 404 ? 'unknown' : 'expired'; // Simplified logic
    }
  };

  const reveal = async (passphrase?: string) => {
    // Transition: ready | passphrase -> revealed
    const data = await api.revealSecret(secretKey, passphrase);
    secret.value = data;
    state.value = 'revealed';
  };

  return { state, secret, fetch, reveal };
}
```

### 3. Wiring them in the View

This is where the power of separation shines. The **View** acts as the controller that meshes the Context (Style) with the State (Data).

**`src/apps/exchange/reveal/ShowSecret.vue`**

```vue
<script setup lang="ts">
import { useExchangeContext } from '@/shared/branding';
import { useSecretLifecycle } from '../composables/useSecretLifecycle';

// 1. Setup Environment (Sync)
const { theme, isOwner } = useExchangeContext();

// 2. Setup Data (Async)
const { state, reveal, secret } = useSecretLifecycle(route.params.id);
</script>

<template>
  <!-- The Frame: Controlled by Context -->
  <ExchangeLayout :theme="theme">
    
    <!-- The Content: Controlled by State -->
    <div class="secret-card">
      
      <!-- STATE: PASSPHRASE -->
      <PassphraseForm 
        v-if="state === 'passphrase'"
        @submit="reveal"
      />

      <!-- STATE: READY (Recipient) -->
      <ClickToReveal 
        v-else-if="state === 'ready' && !isOwner"
        @click="reveal"
      />

      <!-- STATE: READY (Creator/Metadata View) -->
      <MetadataView 
        v-else-if="state === 'ready' && isOwner"
        :metadata="secret" 
      />

      <!-- STATE: REVEALED -->
      <SecretContent 
        v-else-if="state === 'revealed'"
        :content="secret.value"
        :font="theme.monoFont" 
      />
      
      <!-- STATE: 404/BURNED -->
      <StateMessage 
        v-else 
        :type="state" 
      />
      
    </div>
  </ExchangeLayout>
</template>
```

### Recommendation

1.  **Keep `useExchangeContext` pure.** It should not know if the secret exists. It only knows that *if* we show a secret, it should be blue and have a square logo.
2.  **Pass Context into State (Optional).** If the API requires context (e.g., verifying a domain signature for the secret), pass the context values as arguments to the `fetch()` function of the lifecycle hook, rather than importing the lifecycle hook inside the context hook.
3.  **Handle the "Owner" Check in Lifecycle.** While Context knows if the user is *logged in*, the Lifecycle knows if this specific secret *belongs* to that user (often via a `metadata_key` match or API flag). The View should combine `context.isAuthenticated` + `lifecycle.isOwner` to determine if administrative controls (Burn/Receipt) are shown.
