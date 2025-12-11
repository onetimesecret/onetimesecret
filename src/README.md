# Vue 3 Frontend Architecture

## Interaction Modes Architecture

The frontend is organized by **interaction mode** - what the user is doing - rather than domain or branding. This provides clear separation of concerns and better maintainability.

### Apps (`src/apps/`)

Each app represents a distinct user interaction mode:

```
apps/
├── secret/              # Transactional: creating and revealing secrets
│   ├── conceal/         # Homepage, secret creation, incoming secrets
│   ├── reveal/          # ShowSecret, ShowMetadata, Burn
│   ├── support/         # Feedback forms
│   ├── components/      # Secret-specific components
│   └── branding/        # Brand presentation logic
│
├── workspace/           # Management: dashboard, settings, teams
│   ├── dashboard/       # Secret management dashboard
│   ├── account/         # Account settings, profile
│   ├── billing/         # Subscription and payment
│   ├── teams/           # Team management
│   └── domains/         # Custom domain configuration
│
├── session/             # Authentication: login, signup, MFA
│   ├── views/           # Auth flow pages
│   └── logic/           # Auth utilities
│
└── kernel/              # Admin: colonel/admin interface
    └── views/           # Admin pages
```

### Shared Resources (`src/shared/`)

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

### Other Directories

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
| `.fixture.ts` | Test fixtures | `metadata.fixture.ts` |
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

## Documentation

Each major directory should contain a `README.md` documenting:
- Directory purpose
- Code conventions
- Important patterns
- Usage examples
