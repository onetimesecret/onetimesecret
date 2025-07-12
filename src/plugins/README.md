# Vue and Pinia - A Quick Guide

## Overview

The Vue/Pinia ecosystem has two distinct plugin systems, plus state management through Pinia stores:

1. Vue Plugins extend the core Vue application functionality
2. Pinia Plugins add capabilities to Pinia stores
3. Pinia Stores themselves are not plugins - they are state management containers

### Vue Plugins
Vue plugins are application-level extensions that can add global features to a Vue application. They use the `app.use()` method to install themselves. A common example is an internationalization (i18n) plugin:

```typescript
interface VuePlugin {
  install: (app: App, options?: any) => void
}

export const i18nPlugin: VuePlugin = {
  install(app: App, options = { locale: 'en' }) {
    app.config.globalProperties.$translate = (key: string) => {
      return translations[options.locale][key]
    }

    app.provide('i18n', {
      locale: options.locale,
      translate: app.config.globalProperties.$translate
    })
  }
}
```

### Pinia Plugins
Pinia plugins enhance Pinia store functionality by adding new properties or capabilities to all stores. They're installed using `pinia.use()`:

```typescript
type PiniaPlugin = (context: PiniaPluginContext) => void

export const PiniaApiPlugin: PiniaPlugin = ({ store }) => {
  store.$api = markRaw(createApi())
}
```

### Pinia Stores
Pinia stores are state containers - they're not plugins at all. They manage application state and can be enhanced by Pinia plugins:

```typescript
const useUserStore = defineStore('user', {
  state: () => ({
    profile: null,
    preferences: {}
  }),
  actions: {
    async fetchProfile() {
      // Can use plugin-added properties
      this.profile = await $api.get('/profile')
    }
  }
})
```

## Error Handling

The application implements a three-layer error handling architecture:

1. **Application Level** (Global Error Boundary)
   - Catches and logs uncaught errors system-wide
   - Integrates with Vue's error handling system

2. **Store Level** (Async Error Boundary)
   - Standardizes error handling across Pinia stores
   - Manages store-specific loading states and context

3. **Operation Level** (Async Handler)
   - Handles individual async operations with error classification
   - Manages operation-specific loading states

```
┌─────────────────────────────────────┐
│     Global Error Boundary           │
│     (Application-wide catching)     │
├─────────────────────────────────────┤
│     Async Error Boundary            │
│     (Store-level handling)          │
├─────────────────────────────────────┤
│     Async Operation Handler         │
│     (Operation-level handling)      │
└─────────────────────────────────────┘
```

Each layer has distinct responsibilities, with errors flowing upward through the layers. Lower layers handle specific contexts while upper layers provide fallback handling.

### Files

```
src/
├── plugins/
│   ├── core/
│   │   └── globalErrorBoundary.ts     // Application-wide catch-all
│   └── pinia/
│       └── asyncOperationPlugin.ts    // Store operation handling
├── composables/
│   └── useAsyncHandler.ts             // Individual operations
└── utils/
    └── errors/
        ├── classifier.ts              // Error classification
        └── types.ts                   // Error definitions
```



## Setup Flow

```typescript
const app = createApp(App)
const pinia = createPinia()

// 1. Install Vue plugins
app.use(i18nPlugin, { locale: 'fr' })

// 2. Add Pinia plugins
pinia.use(apiPlugin)

// 3. Install Pinia itself
app.use(pinia)

// 4. Mount application
app.mount('#app')
```

In a component, you can then use both plugin features and stores:

```typescript
export default {
  setup() {
    // Access Vue plugin features
    const { translate } = inject('i18n')

    // Use a Pinia store
    const userStore = useUserStore()
    // The store has access to plugin-added features
    await userStore.fetchProfile()

    return {
      translate,
      userProfile: userStore.profile
    }
  }
}
```

## Dependency Injection

We use Vue's built-in dependency injection system rather than passing dependencies through Pinia plugins:

```typescript
// Application initialization
const api = createApi();
app.provide('api', api);

// In stores and components
const $api = inject('api') as AxiosInstance;
```
This approach maintains separation of concerns and follows Vue's idiomatic patterns.


### Store Initialization Pattern

Stores follow a two-phase initialization pattern:

1. **Synchronous Initialization**: Setup store structure only
   ```typescript
   function init() {
     // Structure setup only (no API calls)
     return { isInitialized: true };
   }
   ```

2. **Asynchronous Data Loading**: Explicitly triggered after initialization
   ```typescript
   async function loadData() {
     // Data fetching with proper loading state management
   }
   ```

### Pinia Auto-Init Plugin

The `autoInitPlugin` handles calling each store's `init()` method when the store is first instantiated:

```typescript
pinia.use(autoInitPlugin());
```

This ensures consistent initialization across all stores without requiring manual calls to `init()`.

### Testing Store Architecture

When testing stores:

1. Always provide mock services through Vue's DI system
2. Test initialization and data loading separately
3. Use `createTestingPinia` with `stubActions: false` to test real actions

```typescript
// Example test setup
beforeEach(() => {
  const app = createApp();
  app.provide('api', mockApiInstance);
  setActivePinia(createTestingPinia({ stubActions: false }));
});
```

## Related Resources

- [Vue Documentation](https://vuejs.org/guide/reusability/plugins.html)
- [Pinia Documentation](https://pinia.vuejs.org/core-concepts/)
