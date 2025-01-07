# Pinia development

## Overview
Pinia stores with composition API style provide reactive state management with
TypeScript support. Stores are reactive objects that maintain reactivity through
direct references or proper destructuring techniques.

## Core Concepts

### Features
- **Getters**: Computed values for store state
- **Actions**: Methods that support async operations
- **Plugins**: Functions that extend store functionality
- **State Reset**: `$reset()` for reverting to initial state
- **Batch Updates**: `$patch` for multiple changes
- **State Subscriptions**: `$subscribe()` for change monitoring
- **Plugins**: Extend store functionality with custom logic

### Store Requirements
- All state properties must be returned in setup stores
- Private state properties are not supported
- State properties must be mutable for SSR and devtools functionality
- App-level properties can be accessed via `inject()`

### State Management

 A store is an object wrapped with reactive, meaning there is no need to
 write .value after getters but (like props in setup), destructuring
 reactive objects breaks reactivity:

```ts
    const store = reactive({ count: 0 })
```

 ❌ Destructuring breaks reactivity:

 ```ts
    const { count } = store
    console.log(count) // 0
    store.count = 1
    console.log(count) // Still 0 - didn't update
```

 ✅ Direct reference maintains reactivity:
```ts
    console.log(store.count) // 0
    store.count = 1
    console.log(store.count) // 1 - properly updates

    // Or use toRefs:
    let { count } = toRefs(store); // count is now a reactive ref
```

 ✅ Destructuring with toRefs() maintains reactivity:

 ```ts
    console.log(count.value) // 1
    store.count = 2
    console.log(count.value) // 2 - updates as expected
```

 ✅ Or use storeToRefs() to extract properties with reactivity:
 ```ts
    const { name, doubleCount } = storeToRefs(store)
```


## Defining Stores

Stores are defined using `defineStore` with a unique name (aka `id`) and store definition:

### Setup Stores (2022 - Composition API style) ✅

When passed a Setup function:

```ts
    import { defineStore } from 'pinia'

    // You can name the return value of `defineStore()` anything you want,
    // but it's best to use the name of the store and surround it with `use`
    // and `Store` (e.g. `useUserStore`, `useCartStore`, `useProductStore`)
    // the first argument is a unique id of the store across your application
    export const useBlounterStore = defineStore('blounter', () => {
      const $api = inject('api') as AxiosInstance;
      const count = ref(0)
      const name = ref('Blounter')
      const doubleCount = computed(() => count.value * 2)
      function increment() {
        count.value++
      }

      return { count, name, doubleCount, increment }
    })
```

### Option Stores (2019 - Option API style) ❌

When passed an Options object:

```ts
    import { defineStore } from 'pinia'

    export const useCounterStore = defineStore('counter', {
      state: () => ({ count: 0, name: 'Eduardo' }),
      getters: {
        doubleCount: (state) => state.count * 2,
      },
      actions: {
        increment() {
          this.count++
        },
      },
    })
```

As with [Vue's Composition API and Options API](https://vuejs.org/guide/introduction.html#which-to-choose), pick the one that you feel the most comfortable with.

#### Typing

refs are typed using generic parameters:
`const selectedComponents = ref<ServerConfigComponent[]>([]);`

[source - Boussadjra Brahim](https://stackoverflow.com/questions/77935811/type-annotation-to-state-with-setup-store/77935834#77935834)


### Passing Arguments

#### Safe Store Initialization Pattern

Add an action and call upon creation because having it as an argument could
be misleading as it's only used **if the store created that time**.

✅ Use an init method to pass arguments:

```ts
const store = useStore()
store.init(arguments)
```

##### Core Principle: Avoid Reactive State Initialization Conflicts

Prevent:
- Circular dependencies
- Stack overflows from reactive chains
- Initialization order problems

##### Example Implementation

```typescript
// services/auth.ts
export const AuthService = {
  getInitialState() {
    return window.authenticated === true;
  }
};

// stores/auth.ts
export function useAuthStore() {
  const _initialized = ref(false);
  const isAuthenticated = ref(false);

    interface StoreOptions {
      deviceLocale?: string;
      storageKey?: string;
      api?: AxiosInstance;
    }

  function init(options?: StoreOptions) {
    if (_initialized.value) return;

    // Use non-reactive service for initial state
    isAuthenticated.value = AuthService.getInitialState();

    // Setup reactive relationships AFTER initialization
    watch(() => {
      // Safe to access other stores here
    });

    _initialized.value = true;
  }
}
```

##### Best Practices

1. Use non-reactive services for initial state
2. Separate initialization from reactive relationships
3. Mark store as initialized
4. Setup reactive relationships afterward


[source - posva](https://github.com/vuejs/pinia/discussions/826#discussioncomment-1690020)


## Resetting State

Use `$reset()` (with sigil) to revert state to its initial value in Option Stores:

```ts
    const store = useStore()
    store.$reset()
```

https://stackoverflow.com/questions/71690883/pinia-reset-alternative-when-using-setup-syntax/71760032#71760032


## More detail

Note that you must return all state properties in setup stores for Pinia
 to pick them up as state. In other words, you cannot have private state
 properties in stores. Not returning all state properties or making them
 readonly will break SSR, devtools, and other plugins.
 Any property provided at the App level can be accessed from the store
 using inject(), just like in components.

 Getters are exactly the equivalent of computed values for the state of
 a Store. In `setup` you can directly access any getter as a property of
 the store (exactly like state properties).

 Actions are the equivalent of methods in components. Unlike getters,
 actions can be asynchronous, you can await inside of actions any API
 call or even other actions (e.g. https://github.com/posva/mande). To
 consume another store, you can directly use it inside of the action.

 A Pinia plugin is a function that optionally returns properties to
 be added to a store. It takes one optional argument, a context. This
 function is then passed to pinia: `pinia.use(myPiniaPlugin)`. Plugins
 only apply to stores created after plugin registration and pinia
 app initialization. See Augmenting-a-Store in docs for advanced usage.

 Pinia stores rely on the pinia instance to share the same store instance
 across all calls. Behind the scenes, useStore() injects the pinia
 instance you gave to your app. This means that if the pinia instance
 cannot be automatically injected, you have to manually provide it to
 the useStore() function. If you are not doing any SSR, any call of
 useStore() after installing the pinia plugin with app.use(pinia) will
 work. The easiest way to ensure this is to defer useStore() calls by
 placing them inside functions that will execute after pinia is
 installed (e.g. inside `router.beforeEach`).

 WARNING: Do not return properties like route or appProvided (from the example
 above)as they do not belong to the store itself and you can directly access
 them withincomponents with useRoute() and inject('appProvided').

 NOTE: In Option Stores, you can reset the state to its initial value by
 calling $reset(). Internally, this calls the state() function to create
 a new state object and replaces the current state with it. In Setup
 Stores, you need to create your own $reset.

 Beyond direct store mutations (store.count++), $patch allows applying multiple
 changes at once via a partial state object. For complex mutations like array
 operations, $patch also accepts a function to avoid creating new collections.
 $patch() groups multiple changes into a single devtools entry, while still
 supporting time travel debugging (Vue 2 only).

### Watching state

Watch store state changes via $subscribe(), similar to Vuex subscriptions. More
efficient than watch() as it triggers once after patches. Uses Vue's watch()
under the hood and accepts same options like { flush: 'sync' }.
State subscriptions auto-unmount with components unless {detached: true} is
passed. You can also watch entire pinia state with a single watch():

```ts
watch(
  pinia.state,
  (state) => {
    // persist the whole state to the local storage whenever it changes
    localStorage.setItem('piniaState', JSON.stringify(state))
  },
  { deep: true }
)
```

### Subscribing to actions

It is possible to observe actions and their outcome with store.$onAction(). The callback
passed to it is executed before the action itself. after handles promises and allows
you to execute a function after the action resolves. In a similar way, onError allows
you to execute a function if the action throws or rejects. These are useful for
tracking errors at runtime, similar to this tip in the Vue docs.

Here is an example directly from the docs that logs before running actions and after
they resolve/reject.

```ts
const unsubscribe = someStore.$onAction(
  ({
    name, // name of the action
    store, // store instance, same as `someStore`
    args, // array of parameters passed to the action
    after, // hook after the action returns or resolves
    onError, // hook if the action throws or rejects
  }) => {
    // a shared variable for this specific action call
    const startTime = Date.now()
    // this will trigger before an action on `store` is executed
    console.log(`Start "${name}" with params [${args.join(', ')}].`)

    // this will trigger if the action succeeds and after it has fully run.
    // it waits for any returned promised
    after((result) => {
      console.log(
        `Finished "${name}" after ${
          Date.now() - startTime
        }ms.\nResult: ${result}.`
      )
    })

    // this will trigger if the action throws or returns a promise that rejects
    onError((error) => {
      console.warn(
        `Failed "${name}" after ${Date.now() - startTime}ms.\nError: ${error}.`
      )
    })
  }
)

// manually remove the listener
unsubscribe()
```


### For more information

- [Option Stores Documentation](https://pinia.vuejs.org/core-concepts/#Option-Stores)
- [State Management Documentation](https://pinia.vuejs.org/core-concepts/state.html)
- [Plugins Documentation](https://pinia.vuejs.org/core-concepts/plugins.html#Typing-plugins)
- https://pinia.vuejs.org/cookbook/composing-stores.html#Nested-Stores
- https://pinia.vuejs.org/cookbook/composables.html#Setup-Stores

> [!WARNING]
> Differently from regular state, ref<HTMLVideoElement>() contains a non-serializable
> reference to the DOM element. This is why we don't return it directly. Since it's
> client-only state, we know it won't be set on the server and will always start as
> undefined on the client.

## HMR (Hot Module Replacement)

### Overview
Pinia's HMR support enables real-time store modifications while preserving state
during development. While Vite provides basic HMR, Pinia's HMR implementation
offers enhanced state management capabilities.

### Implementation

```ts
import { defineStore, acceptHMRUpdate } from 'pinia'

export const useStore = defineStore('store', {
  // store definition...
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useStore, import.meta.hot))
}
```

### Key Features
- State preservation across hot reloads
- Consistent store references
- Safe modification of store definitions (actions, state, getters)
- Clean updates without side effects

### Use Cases
- Adding/removing state properties
- Modifying store actions or getters
- Complex state management changes
- Large applications with multiple stores

### Technical Notes
- Required for each store file individually
- Only active in development environments
- Removed automatically in production builds
- Currently optimized for Vite (supports any bundler implementing `import.meta.hot` spec)

### Best Practices
- Place HMR code immediately after store definition
- Include in all store files for consistency
- Ensure correct store reference in `acceptHMRUpdate`
- Implement in development for reliable state management

## Bundler Support
- Officially supported: Vite
- Other bundlers: Must implement `import.meta.hot` spec
- Webpack uses: `import.meta.webpackHot`

For more information:
- [Testing Pinia Stores](https://pinia.vuejs.org/cookbook/testing.html)
