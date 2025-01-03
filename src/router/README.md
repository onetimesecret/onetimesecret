# Routing Layout Patterns

This guide explains the two layout patterns used in our routing system.

## Overview

We maintain two distinct layout patterns to efficiently handle different routing scenarios:

### 1. Composite Pattern

```js
{
  components: {
    default: DashboardContent,
    header: DashboardHeader,  // includes dashboard-specific navigation
    footer: DashboardFooter,
  }
}
```

- Composes page from multiple components
- Each section independently routable
- Typically used for complex, dynamic pages

**Best for:**
- Routes needing independent header/footer components
- Dashboard-style pages with complex navigation
- Pages where header/footer need their own state/logic

### 2. Container Pattern

```js
{
  component: SignInContent,
  meta: {
    layout: AuthLayout
  }
}
```

- Single content component within layout container
- Layout wraps and provides structure
- Best for consistent, themed pages

**Best for:**
- Simple pages with consistent layouts
- Auth pages, forms, static content
- Pages sharing identical header/footer

## Structure

┌─────────────────┐    ┌──────────────────────┐
│  Composite      │    │  Container           │
│                 │    │                      │
│  App            │    │  App                 │
│   ├── Header    │    │   └── Layout         │
│   ├── Main      │    │        └── Component │
│   └── Footer    │    │                      │
└─────────────────┘    └──────────────────────┘

### Method 1: Composite Pattern
```
App.vue
└── QuietLayout/DefaultLayout
    └── RouterView (named views)
        ├── "header": DefaultHeader
        ├── "default": DashboardIndex
        └── "footer": DefaultFooter
```

### Method 2: Container Pattern
```
App.vue
└── Component (specified in route.meta.layout)
    └── RouterView (single view)
        └── SignIn/Other Component
```

## Decision Guide

### Use Named Views when:
1. The header/footer need their own routing logic
2. Components need to manage their own state
3. You need dynamic loading of header/footer

### Use Layout Meta when:
1. The page follows a standard layout
2. Header/footer are consistent
3. Layout can be configured via props

The presence of both patterns provides flexibility without compromising maintainability, as each serves a distinct purpose.
