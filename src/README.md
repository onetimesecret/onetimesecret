# Vue 3 Frontend Architecture

## Interaction Modes Architecture

The frontend is organized by **interaction mode** - what the user is doing - rather than domain or branding. This provides clear separation of concerns and better maintainability.

> **Design Principle**: Create a "Pit of Success" - a way of organizing files and folders that makes it hard to put code in the wrong place.

### Apps (`src/apps/`)

Each app represents a distinct user interaction mode:

```
apps/
├── secret/              # Transactional: creating and revealing secrets
│   ├── conceal/         # Homepage, secret creation, incoming secrets
│   ├── reveal/          # ShowSecret, ShowMetadata, Burn
│   ├── support/         # Feedback forms
│   ├── components/      # Secret-specific components
│   ├── composables/     # useHomepageMode, etc.
│   └── routes/          # Route definitions
│
├── workspace/           # Management: dashboard, settings, organizations
│   ├── dashboard/       # Secret management dashboard
│   ├── account/         # Account settings, profile
│   ├── billing/         # Subscription and payment
│   ├── members/         # Organization member management
│   ├── domains/         # Custom domain configuration
│   └── routes/          # Route definitions
│
├── session/             # Authentication: login, signup, MFA
│   ├── views/           # Auth flow pages
│   └── routes.ts        # Route definitions
│
└── colonel/             # Admin: system administration interface
    ├── views/           # Admin pages
    └── routes.ts        # Route definitions
```

## The Three Dimensions

Three independent dimensions control how views render. Conflating them was a source of architectural confusion.

### Dimension 1: Interaction Mode (Design-Time)

Determines which app handles the request. Set when routes are defined.

| Route         | App       | Mode    | Designed For                               |
|---------------|-----------|---------|--------------------------------------------|
| /             | Secret    | Conceal | Creator (anon or auth) submitting the form |
| /secret/:key  | Secret    | Reveal  | Recipient viewing shared content           |
| /receipt/:key | Secret    | Reveal  | Creator checking delivery status           |
| /dashboard/*  | Workspace | Manage  | Account holder managing history            |
| /colonel/*    | Colonel   | Admin   | System administrator                       |
| /signin       | Session   | Gateway | Identity verification                      |

### Dimension 2: Domain Context (Runtime)

Detected per-request by middleware. Determines presentation, not structure.

| Domain Type | Detection                     | Affects                               |
|-------------|-------------------------------|---------------------------------------|
| Canonical   | Config-defined, static        | Default branding, full marketing copy |
| Custom      | Per-request header inspection | Custom branding, minimal chrome       |

Each custom domain carries its branding configuration and belongs to exactly one organization.

#### Domain Scope (Workspace Extension)

Within Workspace, Domain Context can be elevated to a **persistent scope** for users managing multiple custom domains:

| Concept        | Role                              | Applies To    |
|----------------|-----------------------------------|---------------|
| Domain Context | Presentation wrapper (runtime)    | Secret app    |
| Domain Scope   | Management filter + defaults      | Workspace app |

When Domain Scope is active:
- Privacy defaults (TTL, passphrase requirements) are scoped to the selected domain
- Secrets created from the dashboard use the scoped domain automatically
- The scope persists across navigation within the session

### Dimension 3: Homepage Mode (Deployment-Time)

A scoped gatekeeper configured at deployment. Only applies to the Conceal context.

| Mode     | Who Can Create       | Who Can View | Homepage Shows        |
|----------|----------------------|--------------|-----------------------|
| Open     | Anyone               | Anyone       | Form + explainer      |
| Internal | Internal IPs/headers | Anyone       | Form + explainer      |
| External | Nobody               | Anyone       | "Nothing to see here" |

### Dimensional Matrix

Each dimension answers a different question at a different time:

| Dimension        | Binding Time    | Question                     | Role                          |
|------------------|-----------------|------------------------------|-------------------------------|
| Interaction Mode | Design-time     | "What is the user doing?"    | Router — selects the App      |
| Domain Context   | Runtime         | "How should it look?"        | Wrapper — adapts presentation |
| Domain Scope     | Session         | "Which domain am I managing?"| Filter — scopes Workspace     |
| Homepage Mode    | Deployment-time | "Is creation permitted?"     | Gatekeeper — gates access     |

**Request flow for Conceal (Homepage):**

```
Request to /
      │
      ▼
┌─────────────────────┐
│  Homepage Mode      │ ◄── GATE (Open? Internal? External?)
│  (Deployment-time)  │
└─────────────────────┘
      │
      ├─ External ──────► AccessDenied.vue (stop here)
      │
      ▼ Open/Internal
┌─────────────────────┐
│  Domain Context     │ ◄── WRAPPER (Canonical? Custom?)
│  (Runtime)          │
└─────────────────────┘
      │
      ▼
┌─────────────────────┐
│  Homepage.vue       │ ◄── Unified component, adapts to context
└─────────────────────┘
```

**Complete matrix for Conceal:**

```
                          HOMEPAGE MODE (deployment-time)
                          ┌──────────┬──────────┬──────────┐
                          │  Open    │ Internal │ External │
┌─────────────────────────┼──────────┴──────────┼──────────┤
│ DOMAIN      │ Canonical │    Form + copy      │ Disabled │
│ CONTEXT     ├───────────┼─────────────────────┼──────────┤
│ (runtime)   │ Custom    │    Form + brand     │ Branded  │
│             │           │                     │ Disabled │
└─────────────┴───────────┴─────────────────────┴──────────┘
```

## Actor & Role Systems

The frontend uses distinct role systems at different levels:

### Transaction Roles (Secret App)

The `useSecretContext` composable (in `shared/composables/`) resolves who is viewing a specific secret:

| Role | Description | UI Behavior |
|------|-------------|-------------|
| `CREATOR` | Owner viewing their own secret | Dashboard link, burn control |
| `RECIPIENT_AUTH` | Logged-in user viewing another's secret | Dashboard link, no upgrade CTA |
| `RECIPIENT_ANON` | Anonymous visitor | Signup CTA, entitlements upgrade |

The asymmetry is intentional: `CREATOR` is singular because creating a secret is a singular act—auth state is handled at the customer level. Recipients have variants because the receiving experience legitimately differs based on auth state.

### Organization Roles (Workspace App)

`OrganizationRole` controls permissions within groups:

| Role | Description |
|------|-------------|
| `OWNER` | Full control, can delete organization |
| `ADMIN` | Management permissions, can manage members |
| `MEMBER` | Standard access |

### Account Roles (Customer Level)

`CustomerRole` defines the account type system-wide:

| Role | Description |
|------|-------------|
| `CUSTOMER` | Regular authenticated user |
| `COLONEL` | System administrator (grants access to `/colonel/*`) |
| `RECIPIENT` | Recipient-only account (limited entitlements) |
| `USER_DELETED_SELF` | Soft-deleted account |

### Secret vs Workspace Logic

| Concern | Secret App | Workspace App |
|---------|------------|---------------|
| Auth Variance | High (anon, auth, owner) | Low (always auth) |
| Logic Model | Dimensional Matrix | Standard RBAC |
| Question | "Who are you relative to *this secret*?" | "What permissions do you have?" |

## Shared Resources (`src/shared/`)

Cross-app shared resources:

```
shared/
├── components/          # Categorized UI components
│   ├── base/            # Foundational components
│   ├── ui/              # General UI (buttons, badges, toggles)
│   ├── forms/           # Form elements and validation
│   ├── modals/          # Modal dialogs
│   ├── icons/           # Icon components
│   └── ...              # Other categories
│
├── composables/         # Shared Vue composables
│   ├── useAuth.ts
│   ├── useSecretContext.ts  # Transaction role resolution
│   ├── useBranding.ts       # Domain context detection
│   ├── useTheme.ts
│   └── ...
│
├── stores/              # Pinia state management
│   ├── authStore.ts
│   ├── secretStore.ts
│   └── ...
│
├── layouts/             # Page layout components
│   ├── TransactionalLayout.vue
│   ├── ManagementLayout.vue
│   └── ...
│
└── branding/            # Brand data and utilities
```

### App-Specific Composables

Some composables belong to specific apps rather than shared:

| Composable | Location | Why |
|------------|----------|-----|
| `useHomepageMode` | `apps/secret/composables/` | Only Secret app gates on homepage mode |
| `useSecretContext` | `shared/composables/` | Used by Secret views and tests |
| `useBranding` | `shared/composables/` | Used by both Secret (render) and Workspace (manage) |

## Other Directories

```
src/
├── api/                 # API client and endpoints
├── assets/              # Static assets, global styles
├── locales/             # i18n translation files (34+ languages)
├── plugins/             # Vue plugin configurations
├── router/              # Route definitions
├── schemas/             # Zod validation schemas
├── services/            # Business logic services
├── types/               # TypeScript definitions
├── utils/               # Helper functions
├── tests/               # Vitest unit tests
├── App.vue              # Root component
├── main.ts              # Application entry point
└── i18n.ts              # i18n configuration
```

## File Naming Conventions

### Core Rules

- **PascalCase** for components, layouts, stores, views: `UserProfile.vue`
- **Discriminator suffixes** indicate file type/purpose: `auth.routes.ts`
- **kebab-case** for non-Vue specific utilities: `color-utils.ts`

### Common Suffixes

| Suffix | Purpose | Example |
|--------|---------|---------|
| `.vue` | Vue components | `SecretForm.vue` |
| `.routes.ts` | Route definitions | `secret.routes.ts` |
| `Store.ts` | Pinia stores | `authStore.ts` |
| `.spec.ts` | Unit tests | `useAuth.spec.ts` |
| `.fixture.ts` | Test fixtures | `receipt.fixture.ts` |
| `.d.ts` | Type declarations | `window.d.ts` |

## Key Patterns

### Composables

Composables encapsulate reusable logic. Located in `shared/composables/` for cross-app use or within app directories for app-specific logic.

```typescript
// shared/composables/useAuth.ts
export function useAuth() {
  const authStore = useAuthStore();
  const isAuthenticated = computed(() => authStore.isAuthenticated);
  // ...
  return { isAuthenticated, login, logout };
}
```

### Stores

Pinia stores in `shared/stores/` manage global state. Each store follows a consistent pattern:

```typescript
// shared/stores/secretStore.ts
export const useSecretStore = defineStore('secret', () => {
  const record = ref<SecretRecord | null>(null);
  // state, getters, actions
  return { record, /* ... */ };
});
```

### Layouts

Layout components wrap pages with consistent structure:

- `TransactionalLayout` - For secret flows (supports branding)
- `ManagementLayout` - For workspace/dashboard
- `AuthLayout` - For authentication pages

### Import Aliases

```typescript
import Component from '@/shared/components/ui/Component.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { useAuthStore } from '@/shared/stores/authStore';
import SecretView from '@/apps/secret/reveal/ShowSecret.vue';
```

## Clarifications

### Branding: Data vs Presentation

| Concern | Who Needs It | Location |
|---------|--------------|----------|
| Brand types, API calls, data fetching | Secret (render), Workspace (manage) | `shared/api/`, `shared/types/` |
| Brand presentation logic | Secret only | `apps/secret/branding/` |

Workspace imports brand *data* to populate forms. It doesn't import presentation logic because Workspace is always OTS-branded.

### Receipt View Location

`/receipt/:receiptIdentifier` belongs in Secret app. Although it requires "ownership," it is still Transaction mode, not Management. Ownership is historically based on having the unguessable URL, not authentication state.

### Session as an App

Think of `apps/session` as the airport security checkpoint—a distinct physical space. You enter from the street (Public), pass through Security (Session), and emerge into the terminal (Workspace).

### Router Composition

Routes are explicitly imported and ordered in the main router (first match wins):

```ts
// src/router/index.ts
export const router = createRouter({
  routes: [
    ...sessionRoutes,   // Gateway - check first
    ...colonelRoutes,   // Admin - high specificity
    ...workspaceRoutes, // Dashboard - auth required
    ...secretRoutes,    // Public - contains catch-all 404
  ],
});
```

## Testing

Tests are located in `src/tests/` mirroring the source structure:

```
tests/
├── components/          # Component tests
├── composables/         # Composable tests
├── stores/              # Store tests
├── router/              # Route tests
├── views/               # View tests
├── fixtures/            # Shared test fixtures
└── setup.ts             # Test configuration
```

Run tests: `pnpm test`

## Development Commands

```bash
pnpm run dev          # Start dev server with HMR
pnpm run build        # Production build
pnpm run type-check   # TypeScript validation
pnpm run lint         # ESLint
pnpm test             # Run Vitest tests
```

## Related Documentation

- **[Secret Lifecycle](../docs/product/secret-lifecycle.md)** — FSM pattern for secret state management
