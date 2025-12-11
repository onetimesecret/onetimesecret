---
title: Secret Lifecycle
type: reference
status: draft
updated: 2025-11-30
parent: interaction-modes.md
summary: FSM pattern separating environmental context from entity state
---

# Secret Lifecycle

This distinction is critical because it decouples **UX logic** (who sees what) from **Business logic** (is the data actually there).


### 3. Separation of Concerns: Context vs. Lifecycle

To avoid "god objects" and conditional soup (e.g., `v-if="isOwner && !isBurned && hasPassphrase"`), we separate the **Environment** from the **Entity**.

| Feature | **Secret Context** (`useSecretContext`) | **Secret Lifecycle** (`useSecretLifecycle`) |
| :--- | :--- | :--- |
| **Analogy** | **The Stage** (The lighting, the set, the audience). | **The Actor** (The script, the action, the drama). |
| **Question** | "Who is looking, and where are we?" | "What is the status of this data?" |
| **Inputs** | Window Config, URL, Auth Cookies. | API Response, Database State. |
| **Nature** | **Synchronous** (Calculated immediately). | **Asynchronous** (Requires network IO). |
| **Output** | Branding, UI Config, Permissions. | FSM State (Ready, Revealed, Burned). |

#### A. Secret Context (The Stage)
This composable is "pure" logic. It doesn't know if the secret exists. It only calculates the rules of engagement based on the environment.

**File:** `apps/secret/composables/useSecretContext.ts`

```typescript
export function useSecretContext() {
  const { domainStrategy, brand } = useBranding(); // Shared logic
  const auth = useAuthStore();

  // 1. Where are we? (Branding)
  const theme = computed(() => {
    return domainStrategy.value === 'custom'
      ? { mode: 'branded', colors: brand.colors }
      : { mode: 'canonical', colors: defaultColors };
  });

  // 2. Who is looking? (Identity)
  const actorRole = computed(() => {
    // Logic to determine CREATOR | RECIPIENT | ANON
  });

  // 3. What controls are allowed? (Permissions)
  const uiPermissions = computed(() => ({
    canBurn: actorRole.value === 'CREATOR',
    showUpgradeCTA: actorRole.value === 'ANON'
  }));

  return { theme, uiPermissions };
}
```

#### B. Secret Lifecycle (The Actor)
This composable implements a **Finite State Machine (FSM)**. It guarantees the secret cannot be in an invalid state (e.g., "Burned" but also "Ready to View").

**File:** `apps/secret/composables/useSecretLifecycle.ts`

```typescript
export type SecretState =
  | 'idle'          // Initial loading
  | 'passphrase'    // Exists, but requires password
  | 'ready'         // Exists, click to reveal
  | 'revealed'      // Content is visible
  | 'burned'        // Intentionally destroyed
  | 'expired'       // Time ran out naturally
  | 'unknown';      // 404

export function useSecretLifecycle(secretKey: string) {
  const state = ref<SecretState>('idle');
  const payload = ref<SecretData | null>(null);

  // Transition: idle -> [ready | passphrase | burned | expired]
  const fetch = async () => {
    try {
      const data = await api.getSecret(secretKey);
      if (data.state === 'burned') {
          state.value = 'burned';
      } else if (data.has_passphrase && !data.unlocked) {
          state.value = 'passphrase';
      } else {
          state.value = 'ready';
      }
    } catch (error) {
      state.value = mapErrorToState(error); // unknown | expired
    }
  };

  // Transition: ready -> revealed
  const reveal = async (passphrase?: string) => {
    const data = await api.revealSecret(secretKey, passphrase);
    payload.value = data;
    state.value = 'revealed';
  };

  return { state, payload, fetch, reveal };
}
```

#### C. Integration in the View

The View acts as the conductor. It uses **Context** to paint the frame and **Lifecycle** to determine which scene to play.

**File:** `apps/secret/reveal/ShowSecret.vue`

```vue
<script setup lang="ts">
import { useSecretContext } from '../composables/useSecretContext';
import { useSecretLifecycle } from '../composables/useSecretLifecycle';

// 1. Setup The Stage (Sync)
const { theme, uiPermissions } = useSecretContext();

// 2. Fetch The Actor (Async)
const { state, payload, reveal } = useSecretLifecycle(route.params.secret_key);
</script>

<template>
  <!-- CONTEXT: Controls the "Skin" (Colors, Logo, Footer) -->
  <SecretLayout :theme="theme">

    <div class="secret-stage">
      <!-- LIFECYCLE: Controls the "Scene" (State Switch) -->

      <!-- Scene 1: Locked -->
      <PassphraseForm
        v-if="state === 'passphrase'"
        @submit="reveal"
      />

      <!-- Scene 2: The Envelope -->
      <ClickToReveal
        v-else-if="state === 'ready'"
        @click="reveal"
      >
        <!-- Permission Check injected into Lifecycle Component -->
        <BurnButton v-if="uiPermissions.canBurn" />
      </ClickToReveal>

      <!-- Scene 3: The Content -->
      <SecretContent
        v-else-if="state === 'revealed'"
        :data="payload"
        :font="theme.monoFont"
      />

      <!-- Scene 4: The End -->
      <StateMessage
        v-else
        :status="state"
      />
    </div>

  </SecretLayout>
</template>
```

### Why this structure wins
1.  **Testability:** You can test `useSecretLifecycle` (does it handle 404s?) without mocking Window objects or Branding configs.
2.  **Clarity:** The View template becomes a readable switch statement of the FSM states.
3.  **Safety:** It is impossible to render the `SecretContent` component if the state is `passphrase`, because they are exclusive `v-if/v-else` branches driven by the FSM.
