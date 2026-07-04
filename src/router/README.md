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
- bootstrapStore accessed via Pinia

```
Router Config                        Window Properties
(meta.layoutProps)                   (bootstrapStore)
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
│   │       ├── receipt.ts        # Metadata views
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
    ├── piiQueryGuard.ts           # Dev-only "no PII in query" warning
    ├── public.routes.ts           # Public pages (home, feedback, etc.)
    └── queryParams.handler.ts     # Query param handling
```

The main router (`src/router/index.ts`) imports and assembles routes from all apps.

## Query-string policy: no PII in the URL

**Never put personally-identifiable data (email, tokens, passwords, one-time
codes) in a URL query string.** A URL is not a private channel — it leaks out of
the application through:

- browser history and bfcache (persists on the device, may sync across browsers),
- the `Referer` header on any outbound request or external link,
- proxy / CDN / web-server access logs, and
- Sentry breadcrumbs and `event.request.url`.

This is finding **F6** of the disclosure matrix
(`docs/specs/issue-3424-disclosure-matrix.html`): *"The URL is the bearer secret
— and it leaks."*

**Instead, hand PII to the next page via router history `state`:**

```ts
// ✗ Don't — email is PII and now lives in the URL, history, logs, Sentry.
router.push({ path: '/check-email', query: { email } });

// ✓ Do — state travels with the navigation but never enters the URL.
router.push({ path: '/check-email', state: { checkEmailAddress: email } });
```

Read it back through the history object (there is no typed `route.state`):

```ts
const router = useRouter();
const email = sanitizeDisplayEmail(
  (router.options.history.state as Record<string, unknown>)?.checkEmailAddress
);
```

A plain reload **preserves** history `state` — the browser keeps
`window.history.state` on the current entry and vue-router restores it, so the
email persists across a refresh (harmlessly: state never enters the URL). State
is absent only on a genuinely fresh entry — a shared link, a new tab, or an
address-bar navigation — so design the page to degrade gracefully there (e.g.
`/check-email` falls back to generic copy). Non-PII context (billing
`product`/`interval`, a `redirect` path) is fine in the query — it *should*
survive refresh and sharing.

This policy is enforced in depth:

| Layer | Mechanism | File |
| ----- | --------- | ---- |
| Author time | `ots/no-pii-in-query` ESLint rule flags `query: { email }` literals | `src/build/eslint/no-pii-in-query.ts` |
| Dev runtime | Navigation guard warns when a PII key rides in `to.query` | `src/router/piiQueryGuard.ts` |
| Prod runtime | Diagnostics scrubber redacts query emails from Sentry on every route | `src/plugins/core/enableDiagnostics.ts` |

The shared key list and the display sanitizer live in `src/utils/pii.ts`.

Existing `?email=` prefill on `/signin` and `/signup` is grandfathered (it
predates this policy and is scrubbed at the diagnostics layer); do not extend the
pattern to new routes.
