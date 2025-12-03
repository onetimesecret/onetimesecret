---
title: Request Lifecycle
type: reference
status: draft
updated: 2025-11-30
parent: interaction-modes.md
summary: Explains the architectural shift from routing-branch to adaptive-rendering
---

# Request Lifecycle

From **Imperative Routing** ("Go to file X") to **Declarative Rendering** ("Render file X using Config Y").

*   **Old Way (Routing Branch):** The router acts like a traffic cop. It stops the request, checks the ID, and points to Road A (Canonical) or Road B (Branded). These are two totally different roads.
*   **New Way (Adaptive Rendering):** The router is just a highway. Everyone drives down the same road to the same destination. But the *destination* changes its appearance (adapts) based on who walks through the door.

### The Shift: From "Routing Branch" to "Adaptive Rendering"

Currently, we treat `domain_strategy` as a **Fork in the Road** at the Router level.
In the new model, `domain_strategy` is just **Context Data** that tells the component how to adapt.

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

*   **Old Way (Branching):** `HomepageContainer` checks domain → switches between `Homepage.vue` vs `BrandedHomepage.vue`.
*   **New Way (Unified):** Router loads `apps/secret/conceal/Homepage.vue` unconditionally.

#### 3. The Component (Adaptive)
The component (inside the Secret App) accepts the context and **adapts** its presentation. It does not need to be told *which* component to be; it just needs to know *how* to look.

```vue
<!-- apps/secret/conceal/Homepage.vue -->
<template>
  <div :class="layoutClasses">
    <!--
       If Canonical: Shows "The #1 way to share secrets..."
       If Custom: Adapts to show nothing, or custom logo
    -->
    <MarketingHero v-if="uiConfig.showMarketing" />

    <!--
       The core form is identical for both.
       The *styling* of the form adapts based on uiConfig.theme
    -->
    <SecretForm :theme="uiConfig.theme" />

    <!--
       If Canonical: Standard Footer
       If Custom: Adapts to Minimal "Powered by"
    -->
    <Footer :mode="uiConfig.footerMode" />
  </div>
</template>

<script setup>
// The logic lives here, not in the Router
const { uiConfig } = useSecretContext();
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
[Secret Context Composable] ──> Converts 'strategy' into 'UI Config'
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
│  │  useSecretContext() composable assembles ALL dimensions:        │ │
│  │    • domainStrategy (from window state)                         │ │
│  │    • authState (from auth store)                                │ │
│  │    • relationship (from route + ownership check)                │ │
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

### Why this supports the "Apps" Model

This fits perfectly because **only the Secret App listens to this signal.**

1.  **Secret App:** Eagerly consumes `domain_strategy`. It drastically changes the UI (Colors, Logos, Copy) based on the value.
2.  **Workspace App:** Ignores `domain_strategy`. If a user logs into `dashboard`, they get the standard `ImprovedLayout`. The context is "Management," so the branding is always canonical.
3.  **Kernel App:** Ignores `domain_strategy`.

### Conclusion
We do not need to change the middleware. The middleware provides the **Runtime Context**. The Frontend Architecture simply needs to stop treating that context as a reason to load a different file, and start treating it as a **prop** passed to a unified file.
