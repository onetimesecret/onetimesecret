# Routing & Page Composition

This guide explains the two kinds layouts used in our routing system and how props are made available to components.

## Overview

We maintain two distinct layout patterns to handle different routing scenarios:

### The Two Layout Patterns

#### 1. Composite (named views)

A list of named components. Typically used for complex, dynamic pages. e.g. Dashboards, Timelines, etc.

```js
{
  components: {
    default: DashboardContent,
    header: DashboardHeader,
    footer: DefaultFooter,
  }
}
```


#### 2. Container (layout meta)

A single component within a layout container. Usually used for pages that benefit from a consistent layout. e.g. Sign In, Sign Up, etc.

```js
{
  component: SignInContent,
  meta: {
    layout: AuthLayout
  }
}
```

### Visual Comparison

```plaintext
┌─────────────────┐    ┌──────────────────────┐
│  Composite      │    │  Container           │
│                 │    │                      │
│  App            │    │  App                 │
│   ├── Header    │    │   └── Layout         │
│   ├── Main      │    │        └── Component │
│   └── Footer    │    │                      │
└─────────────────┘    └──────────────────────┘
```

### Examples from the codebase


```
App.vue
└── QuietLayout<-BaseLayout
    └── RouterView
        ├── "header": DefaultHeader
        ├── "default": DashboardIndex
        └── "footer": DefaultFooter
```

### Method 2: Container Pattern
```
App.vue
└── Component (specified in route.meta.layout)
    └── RouterView
        └── SignIn.vue
```

### When to use each pattern

**Use Composite Named Views when:**
1. The header/footer need their own routing logic
2. Components need to manage their own state
3. You need dynamic loading of header/footer

**Use Container Layout Meta when:**
1. The page follows a standard layout
2. Header/footer are consistent
3. Layout can be configured via props


## Layouts and props

Key Points:
- Router config sets per-route layout and props
- App.vue merges window properties with route props
- Layouts receive combined props object
- Child components receive subset of props
- WindowService accessed at App.vue and some components

```
Router Config                        Window Properties
(meta.layoutProps)                   (WindowService)
       │                                   │
       │                                   │
       ▼                                   ▼
    App.vue ────────────────────► layoutProps = {
       │                           defaultProps + route.meta.layoutProps
       │                         }
       │
       ├──────────────┬─────────────┐
       │              │             │
DefaultLayout    QuietLayout    Other Layouts
       │
       ├──────────────┬─────────────┐
       │              │             │
 BaseLayout     DefaultHeader  DefaultFooter
(core structure) (auth, cust)  (auth, regions)
       │
       │
 <router-view>
(page components)

Props Flow:
App.vue [layoutProps] ─────┐
                           │
                           ▼
DefaultLayout [v-bind="props"] ─────┐
                                    │
                                    ▼
BaseLayout, DefaultHeader, DefaultFooter
[individual props from LayoutProps interface]

Layout Selection:
route.meta.layout determines which layout wraps page
route.meta.layoutProps overrides default layout props
```

## Route File Organization

Routes are organized by app domain under `src/apps/`, with cross-cutting routes in `src/router/`:

```
src/
├── apps/
│   ├── colonel/
│   │   └── routes.ts              # Admin routes
│   ├── secret/
│   │   └── routes/
│   │       ├── incoming.ts        # Secret creation (API-driven)
│   │       ├── metadata.ts        # Metadata views
│   │       └── secret.ts          # Secret reveal
│   ├── session/
│   │   └── routes.ts              # Auth routes (login, signup, etc.)
│   └── workspace/
│       └── routes/
│           ├── account.ts         # Account settings
│           ├── billing.ts         # Billing/subscription
│           ├── dashboard.ts       # Dashboard views
│           └── teams.ts           # Team management
└── router/
    ├── index.ts                   # Main router (assembles all routes)
    ├── guards.routes.ts           # Navigation guards
    ├── layout.config.ts           # Layout component config
    ├── public.routes.ts           # Public pages (home, feedback, etc.)
    └── queryParams.handler.ts     # Query param handling
```

The main router (`src/router/index.ts`) imports and assembles routes from all apps.
