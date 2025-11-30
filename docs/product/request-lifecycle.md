

Our current request flow provides the exact "raw material" needed to power the new mental model.

The difference is not in **what** data we receive (middleware), but **where** and **how** that data is consumed (frontend).

### The Shift: From "Routing Branch" to "State Consumption"

Currently, we treat `domain_strategy` as a **Fork in the Road** at the Router level.
In the new model, `domain_strategy` is just **Context Data** fed into the Matrix.

Here is how the flow evolves:

#### 1. The Request (Unchanged)
The backend does its job perfectly. It identifies the environment.
```text
Rack::DetectHost 
   ↓ 
window.__ONETIME_STATE__.domain_strategy = 'subdomain' | 'canonical'
```

#### 2. The Router (Simplified)
Instead of asking "Which component do I load?", the Router now simply asks "Which App is this?"

*   **Old Way:** `HomepageContainer` checks domain → switches between `Homepage` vs `BrandedHomepage`.
*   **New Way:** Router loads `apps/exchange/views/Homepage.vue` unconditionally.

#### 3. The Component (The Matrix)
The component (inside the Exchange App) consumes the state to decide its *presentation*, not its existence.

```javascript
// apps/exchange/views/Homepage.vue

<template>
  <div :class="layoutClasses">
    <!-- 
       If Canonical: Shows "The #1 way to share secrets..."
       If Custom: Shows nothing, or custom logo 
    -->
    <MarketingHero v-if="matrix.showMarketing" />

    <!-- 
       The core form is identical for both.
       The *styling* of the form changes based on matrix.theme 
    -->
    <SecretForm :theme="matrix.theme" />
    
    <!-- 
       If Canonical: Standard Footer
       If Custom: Minimal "Powered by" 
    -->
    <Footer :mode="matrix.footerMode" />
  </div>
</template>

<script setup>
// The Matrix logic lives here
const { matrix } = useExchangeContext(); 
</script>
```

---

### Visualization of the Change

We are moving the decision logic **down** from the Router/Container level into the Component/Composable level.

#### Current State (The Fork)
```text
window.domain_strategy
       │
       ▼
[Container Component] 
       │
       ├─ (Canonical) ──> [Canonical Component] (Duplicate Logic)
       │
       └─ (Custom) ─────> [Branded Component] (Duplicate Logic)
```

#### New State (The Injection)
```text
window.domain_strategy
       │
       ▼
[Exchange Context Composable] ──> Converts 'strategy' into 'UI Config'
       │
       ▼
[Unified Component] 
(Renders differently based on Config)
```

### Full Request Lifecycle

```text
┌──────────────────────────────────────────────────────────────────────┐
│                      REVISED REQUEST FLOW                            │
├──────────────────────────────────────────────────────────────────────┤
│  HTTP Request                                                        │
│       ↓                                                              │
│  Rack::DetectHost (extract domain) ─────────────────┐                │
│       ↓                                             │                │
│  DomainStrategy (canonical | custom | etc.)         │                │
│       ↓                                             │                │
│  window.__ONETIME_STATE__ ◄─────────────────────────┘                │
│       ↓                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  useUserContext() composable assembles ALL dimensions:          │ │
│  │    • domainStrategy (from window state)                         │ │
│  │    • authState (from auth store)                                │ │
│  │    • contentRelationship (from route + ownership check)         │ │
│  │    • capabilities (from user profile)                           │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│       ↓                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  Single ShowSecret.vue                                          │ │
│  │    • Reads context via composable                               │ │
│  │    • Computes presentation config from all dimensions           │ │
│  │    • Renders adaptively (v-if, dynamic classes, slot content)   │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```


### Why this supports the "Audience" Model

This fits perfectly because **only the Exchange App listens to this signal.**

1.  **Exchange App:** Eagerly consumes `domain_strategy`. It drastically changes the UI (Colors, Logos, Copy) based on the value.
2.  **Workspace App:** Ignores `domain_strategy`. If a user logs into `dashboard`, they get the standard `ImprovedLayout`. The context is "Management," so the branding is always canonical.
3.  **Kernel App:** Ignores `domain_strategy`.

### Conclusion
We do not need to change the middleware. The middleware provides the **Runtime Context**. The Frontend Architecture simply needs to stop treating that context as a reason to load a different file, and start treating it as a **prop** passed to a unified file.
