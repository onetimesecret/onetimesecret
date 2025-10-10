---
labels: frontend, vue3, pinia, architecture
---
# Frontend Architecture

**Last Updated:** 2025-10-10
**Framework:** Vue 3.5 (Composition API)
**State Management:** Pinia 3
**Build Tool:** Vite 5.4
**Language:** TypeScript 5.6

## Overview

The frontend is a Vue 3 SPA using Composition API (`<script setup>`) with TypeScript. State management uses Pinia stores, and data flows from Ruby backendwindow stateVue components.

## Architecture Pattern: Backend-to-Frontend Bridge

```
1. Page Load
   Ruby backend renders index.html template
   Injects window.__ONETIME_STATE__ via JSON script tag
   Location: apps/web/core/views.rb (VuePoint/ExportWindow)

2. Vue App Initialization
   Location: src/main.ts, src/plugins/core/appInitializer.ts
   Order:
   - Diagnostics (if enabled)
   - Error boundary
   - Pinia (state management)
   - API client (Axios)
   - i18n
   - Router

3. Store Initialization
   Location: src/plugins/pinia/autoInitPlugin.ts
   - Pinia auto-init plugin calls store.init() if available
   - Stores read from WindowService
   - WindowService reads from window.__ONETIME_STATE__

4. Component Access
   Location: src/components/**/*.vue
   - Components use WindowService directly OR
   - Components use Pinia stores
   - Both sources read from window.__ONETIME_STATE__

5. State Refresh (every 15 minutes)
   Location: src/stores/authStore.ts
   - checkWindowStatus() fetches /window endpoint
   - Updates entire window.__ONETIME_STATE__
   - Components using computed() react automatically
```

## Window State Bridge

**Backend Injection:**
- **Location:** `apps/web/core/views.rb`
- **Classes:** `VuePoint` (page loads), `ExportWindow` (API endpoint)
- **Serializers:** ConfigSerializer, AuthenticationSerializer, DomainSerializer, I18nSerializer, MessagesSerializer, SystemSerializer

**Frontend Access:**
- **Service:** `src/services/window.service.ts`
- **Type Definition:** `src/types/declarations/window.d.ts`

**Example:**
```typescript
// Reading window state (reactive)
const windowProps = computed(() => WindowService.getMultiple([
  'authenticated',
  'cust',
  'ui',
]));

// Template access (auto-unwrapped)
<template>
  <div v-if="windowProps.authenticated">
    {{ windowProps.cust.email }}
  </div>
</template>
```

**State Refresh:**
- **Endpoint:** `GET /window` (apps/web/core/routes:28)
- **Frequency:** Every 15 minutes (±90s jitter)
- **Triggers:**
  - Automatic: `authStore.checkWindowStatus()` timer
  - Manual: After login via `useAuth.login()`
- **Updates:** Entire `window.__ONETIME_STATE__` including customer data, config, CSRF token

## State Management (Pinia)

**Store Locations:** `src/stores/*.ts`

**Key Stores:**
- `authStore.ts` - Authentication state, periodic window refresh
- `csrfStore.ts` - CSRF token management
- `customerStore.ts` - Customer data
- `languageStore.ts` - i18n locale
- `notificationsStore.ts` - Toast notifications
- `secretStore.ts` - Secret management
- `domainsStore.ts` - Custom domain management
- `brandStore.ts` - Branding configuration

**Store Pattern (Composition API):**
```typescript
export const useExampleStore = defineStore('example', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const data = ref<string>('');
  const _initialized = ref(false);

  // Getters (computed)
  const isReady = computed(() => _initialized.value);

  // Actions
  function init(options?: StoreOptions) {
    if (_initialized.value) return;

    // Read from window state via WindowService
    const windowData = WindowService.get('property');
    data.value = windowData;

    _initialized.value = true;
  }

  async function fetchData() {
    const response = await $api.get('/endpoint');
    data.value = response.data;
  }

  return { data, isReady, init, fetchData };
});
```

**Auto-Init Plugin:**
- **Location:** `src/plugins/pinia/autoInitPlugin.ts`
- Automatically calls `store.init()` when store is created
- Passes API client and options to stores

## Router Architecture

**Location:** `src/router/index.ts`

**Route Modules:**
- `public.routes.ts` - Public pages (home, feedback)
- `auth.routes.ts` - Authentication (signin, signup)
- `secret.routes.ts` - Secret sharing/viewing
- `dashboard.routes.ts` - Dashboard (authenticated)
- `account.routes.ts` - Account settings
- `colonel.routes.ts` - Admin area

**Route Guards:**
- **Location:** `src/router/guards.routes.ts`
- **Pattern:** Runs before each navigation
- **Responsibilities:**
  - Query parameter processing
  - Authentication validation via `authStore.checkWindowStatus()`
  - Locale preference loading
  - Redirect logic (authenticated users away from auth pages)

**Guard Flow:**
```typescript
router.beforeEach(async (to) => {
  // 1. Process query params
  processQueryParams(to.query);

  // 2. Root redirect (//dashboard if authenticated)
  if (to.path === '/') {
    return authStore.isAuthenticated ? { name: 'Dashboard' } : true;
  }

  // 3. Auth route redirect (authenticated usersdashboard)
  if (isAuthRoute(to) && authStore.isAuthenticated) {
    return { name: 'Dashboard' };
  }

  // 4. Protected route validation
  if (requiresAuthentication(to)) {
    const isAuthenticated = await validateAuthentication(authStore, to);
    if (!isAuthenticated) return redirectToSignIn(to);

    // Load user preferences
    const prefs = await fetchCustomerPreferences();
    if (prefs.locale) languageStore.setCurrentLocale(prefs.locale);
  }

  return true;
});
```

## Composables

**Location:** `src/composables/*.ts`

**Authentication:**
- `useAuth.ts` - Login, signup, logout, password reset operations

**UI Components:**
- `useDropdown.ts` - Dropdown menu state
- `useClickOutside.ts` - Click-outside detection
- `useClipboard.ts` - Copy-to-clipboard
- `useTheme.ts` - Dark/light mode

**Forms:**
- `useFormSubmission.ts` - Form submission handling
- `useSecretForm.ts` - Secret creation form
- `usePasswordChange.ts` - Password change form

**Business Logic:**
- `useSecret.ts` - Secret operations
- `useDomain.ts` - Domain operations
- `useMetadata.ts` - Metadata management

**Utilities:**
- `useAsyncHandler.ts` - Async error handling
- `useFetchData.ts` - Data fetching patterns

## Component Architecture

**Pattern:** Composition API with `<script setup lang="ts">`

**Example Structure:**
```vue
<script setup lang="ts">
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';

// i18n
const { t } = useI18n();

// Window state (reactive)
const windowProps = computed(() => WindowService.getMultiple(['cust', 'authenticated']));

// Local state
const isOpen = ref(false);

// Props with defaults
const props = withDefaults(defineProps<{
  title?: string;
  enabled?: boolean;
}>(), {
  enabled: true,
});

// Computed
const displayTitle = computed(() => props.title || t('default.title'));

// Methods
function handleClick() {
  isOpen.value = !isOpen.value;
}
</script>

<template>
  <div v-if="props.enabled">
    <h1>{{ displayTitle }}</h1>
    <p v-if="windowProps.authenticated">{{ windowProps.cust.email }}</p>
    <button @click="handleClick">{{ t('toggle') }}</button>
  </div>
</template>
```

**Rules:**
-  Use `computed()` for WindowService access (reactive)
-  Use `$t()` for all text (i18n)
-  Use Tailwind classes for styling
-  Use TypeScript strict mode
- L No hardcoded text
- L No direct window state access (use WindowService)
- L Max 100 characters per line

## API Client

**Location:** `src/api/index.ts`

**Configuration:**
- Base URL from `window.__ONETIME_STATE__.baseuri`
- Axios instance with interceptors
- CSRF token injection via `csrfStore`
- Error handling via interceptors

**Interceptors:**
- **Location:** `src/plugins/axios/interceptors.ts`
- **Request:** Inject CSRF token from `csrfStore.shrimp`
- **Response:** Update CSRF token from `X-Shrimp` header
- **Error:** Handle 401 (logout), 403 (forbidden), network errors

**Usage:**
```typescript
// In composables/stores
const $api = inject('api') as AxiosInstance;

// Make request
const response = await $api.post('/auth/login', {
  u: email,
  p: password,
  shrimp: csrfStore.shrimp,
});
```

## i18n

**Location:** `src/locales/*.json`, `src/i18n/index.ts`

**Pattern:**
- Hierarchical keys (e.g., `web.secrets.enterPassphrase`)
- Loaded from `src/locales/en.json`
- Fallback locale: `en`
- Available locales from `window.__ONETIME_STATE__.supported_locales`

**Usage:**
```vue
<template>
  <h1>{{ $t('web.COMMON.header_sign_in') }}</h1>
  <p>{{ $t('web.secrets.enterPassphrase') }}</p>
</template>

<script setup lang="ts">
const { t } = useI18n();
const message = t('web.COMMON.verification_sent');
</script>
```

## Error Handling

**Global Error Boundary:**
- **Location:** `src/plugins/core/globalErrorBoundary.ts`
- Catches unhandled errors
- Logs to console in development
- Shows user-friendly error messages

**Async Error Handler:**
- **Location:** `src/composables/useAsyncHandler.ts`
- Wraps async operations
- Provides loading/error states
- Integrates with notifications store

**Pattern:**
```typescript
const { execute, isLoading, error } = useAsyncHandler();

const result = await execute(async () => {
  return await $api.post('/endpoint', data);
});

if (error.value) {
  notificationsStore.show(error.value.message, 'error');
}
```

## Styling

**Framework:** Tailwind CSS 3.4

**Pattern:**
- Utility-first classes
- Dark mode support via `dark:` prefix
- Responsive design via breakpoints (sm, md, lg, xl)
- Custom colors in `tailwind.config.js`

**Example:**
```vue
<template>
  <div class="container mx-auto p-4">
    <button class="bg-brand-500 hover:bg-brand-600 text-white px-4 py-2 rounded
                   dark:bg-brand-400 dark:hover:bg-brand-500">
      {{ $t('submit') }}
    </button>
  </div>
</template>
```

## Build & Development

**Commands:**
```bash
# Development server (HMR)
pnpm run dev

# Type checking
pnpm run type-check
pnpm run type-check:watch

# Linting
pnpm run lint
pnpm run lint:fix

# Build
pnpm run build

# Preview production build
pnpm run preview
```

**Vite Configuration:**
- **Location:** `vite.config.ts`
- **Features:**
  - Vue plugin with JSX support
  - Path aliases (`@/``src/`)
  - CSS preprocessing
  - Build optimization

## Testing

**Unit Tests:**
- **Framework:** Vitest 2.1.8
- **Location:** `src/**/__tests__/*.spec.ts`
- **Pattern:** Component testing with Vue Test Utils

**E2E Tests:**
- **Framework:** Playwright
- **Location:** `tests/e2e/*.spec.ts`
- **Commands:**
  ```bash
  pnpm run playwright
  PLAYWRIGHT_BASE_URL=https://dev.onetime.dev pnpm exec playwright test
  ```

## Key Patterns

### Reactive Window State
Use `computed()` to make window state reactive:
```typescript
//  Reactive - updates when window state changes
const windowProps = computed(() => WindowService.get('cust'));

// L Static - won't update
const windowProps = WindowService.get('cust');
```

### Store Initialization
Initialize stores via auto-init plugin:
```typescript
export const useMyStore = defineStore('my', () => {
  const _initialized = ref(false);

  function init(options?: StoreOptions) {
    if (_initialized.value) return;
    // Initialize from window state or API
    _initialized.value = true;
  }

  return { init, /* ... */ };
});
```

### Composable Pattern
Extract reusable logic into composables:
```typescript
export function useFeature() {
  const isLoading = ref(false);
  const error = ref<string | null>(null);

  async function doSomething() {
    isLoading.value = true;
    try {
      // Logic here
    } catch (e) {
      error.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  return { isLoading, error, doSomething };
}
```

## References

- **Vue 3 Documentation:** https://vuejs.org/
- **Pinia Documentation:** https://pinia.vuejs.org/
- **Vite Documentation:** https://vitejs.dev/
- **TypeScript Documentation:** https://www.typescriptlang.org/
- **Tailwind CSS:** https://tailwindcss.com/
- **Backend Architecture:** `docs/architecture/authentication.md`
- **Store Patterns:** `src/stores/README.md`
