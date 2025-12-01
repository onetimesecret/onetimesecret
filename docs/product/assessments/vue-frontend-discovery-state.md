# Current Architecture Summary

## Directory Map

```
src/
├── api/                    # API client abstractions
├── assets/                 # Static assets (fonts, images, styles)
├── build/                  # Build configuration plugins
├── components/             # Vue components (163 total)
│   ├── [37 flat]          # Top-level components (legacy pattern)
│   ├── [126 categorized]  # Organized by feature domain
│   ├── account/           # Account management UI
│   ├── auth/              # Authentication forms
│   ├── base/              # Legacy base components
│   ├── billing/           # Billing/subscription UI
│   ├── closet/            # Loading skeletons
│   ├── colonel/           # Admin UI components
│   ├── common/            # Shared utilities
│   ├── ctas/              # Call-to-action components
│   ├── dashboard/         # Dashboard-specific UI
│   ├── icons/             # Icon system
│   ├── incoming/          # Incoming secret UI
│   ├── layout/            # Layout components (headers, footers)
│   ├── logos/             # Logo variants
│   ├── modals/            # Modal dialogs
│   ├── navigation/        # Navigation components
│   ├── organizations/     # Organization management
│   ├── secrets/           # Secret-related components
│   │   ├── branded/      # Custom domain variant (3 components)
│   │   ├── canonical/    # Standard variant (3 components)
│   │   ├── form/         # Secret creation forms
│   │   └── metadata/     # Secret metadata display
│   ├── teams/             # Team management
│   └── ui/                # Base UI primitives
├── composables/            # Vue composables (37 files)
│   └── helpers/           # Helper utilities
├── layouts/                # Page layout templates (6 files)
├── locales/                # i18n translations (24 languages)
├── plugins/                # Vue plugins
├── router/                 # Vue Router configuration
├── schemas/                # Zod validation schemas
├── scripts/                # Build scripts
├── services/               # Business logic services
├── sources/                # Static data sources
├── stores/                 # Pinia state stores (19 stores)
├── tests/                  # Test files
├── types/                  # TypeScript type definitions
├── utils/                  # Utility functions
└── views/                  # Route-level views (75 files)
    ├── account/           # Account pages
    ├── auth/              # Authentication pages
    ├── billing/           # Billing pages
    ├── colonel/           # Admin pages
    ├── dashboard/         # Dashboard pages
    ├── errors/            # Error pages
    ├── incoming/          # Incoming secret pages
    ├── secrets/           # Secret display pages
    │   ├── branded/      # Custom domain views
    │   └── canonical/    # Standard views
    └── teams/             # Team pages
```

## Component Categories

**Flat components (37):** Legacy pattern with components directly in `/components`
- Examples: `ActivityFeed.vue`, `ConfirmDialog.vue`, `CopyButton.vue`
- Pain point: No clear organization, harder to navigate

**Categorized components (126):** Modern pattern organized by domain
- `secrets/` (26 components): Largest category, split between canonical/branded
- `layout/` (18 components): Headers, footers, navigation
- `auth/` (9 components): Sign-in, sign-up, MFA
- `dashboard/` (8 components): Dashboard-specific UI
- `icons/` (9 components): Icon system with sprite collections
- `teams/` (4 components): Team management
- `billing/` (1 component): Billing prompts

**Container Pattern (3 files):** Components that orchestrate variant selection
- `/views/HomepageContainer.vue` → Homepage | BrandedHomepage | DisabledHomepage | DisabledUI
- `/views/secrets/ShowSecretContainer.vue` → ShowSecretCanonical | ShowSecretBranded
- `/views/dashboard/DashboardContainer.vue` → DashboardBasic | DashboardEmpty | SingleTeamDashboard | DashboardIndex

## State Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Backend Injection                         │
│                 window.__ONETIME_STATE__                     │
│  (domain_strategy, domain_branding, authenticated, etc.)     │
└──────────────────────┬──────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  WindowService (read-only)                   │
│         Type-safe access to server-injected props            │
└──────────┬──────────────────────┬────────────────────────────┘
          │                      │
          ▼                      ▼
    ┌──────────┐         ┌──────────────┐
    │ Stores   │         │ Composables  │
    │          │         │              │
    │ • auth   │         │ • useBranding│
    │ • brand  │         │ • useAuth    │
    │ • identity│        │ • useDomain  │
    │ • domain │         │              │
    └────┬─────┘         └──────┬───────┘
        │                      │
        ▼                      ▼
    ┌─────────────────────────────────┐
    │      Components & Views         │
    │                                 │
    │ Container components query      │
    │ stores/composables to decide    │
    │ which variant to render         │
    └─────────────────────────────────┘
```

### Key State Stores

1. **identityStore** (`useProductIdentity`):
   - **Source:** `window.__ONETIME_STATE__`
   - **Manages:** `domainStrategy`, `isCustom`, `isCanonical`, `displayDomain`, `brand`, `primaryColor`
   - **Used by:** Container components to select variants

2. **brandStore** (`useBrandStore`):
   - **Manages:** Domain-specific branding settings (colors, fonts, logos, instructions)
   - **API operations:** `fetchSettings()`, `updateSettings()`, `uploadLogo()`
   - **Used by:** `/dashboard/domains/:id/brand` for branding editor

3. **authStore** (`useAuthStore`):
   - **Manages:** Authentication state, periodic session checks
   - **Features:** 15-minute heartbeat with jitter, 3-strike failure policy
   - **Used by:** Router guards, auth composables

4. **domainsStore:**
   - **Manages:** Custom domain CRUD operations
   - **Used by:** Dashboard domain management

## Routing

### Route Structure

- `router/index.ts` - Main router factory
- `router/guards.routes.ts` - Auth guards, locale setup, MFA checks
- Feature-specific route files:
  - `public.routes.ts` - Homepage (uses beforeEnter to set componentMode)
  - `dashboard.routes.ts` - Dashboard, domains
  - `auth.routes.ts` - Sign-in, sign-up, MFA
  - `account.routes.ts` - Account settings
  - `secret.routes.ts` - Secret display
  - `teams.routes.ts` - Team management
  - `billing.routes.ts` - Billing pages
  - `colonel.routes.ts` - Admin pages

### Route-Level Branching

- **`/` (Home):** `beforeEnter` hook determines `componentMode` → `HomepageContainer` renders variant
- **Authentication:** `requiresAuth` meta field enforced by global guard
- **Layouts:** Route meta specifies layout component and props
- **MFA:** Special guard redirects to `/mfa-verify` when `awaiting_mfa` is true

### Domain Strategy Flow

1. Backend sets `domain_strategy` in `window.__ONETIME_STATE__`
2. `identityStore` exposes computed flags: `isCanonical`, `isCustom`, `isSubdomain`
3. Container components read these flags to select variant
4. No route-level branching based on domain strategy (handled at component level)

## Key Composables

### Branding & Domain

- `useBranding(domainId?)` - Fetch/update domain branding, locale management
- `useDomain()` - Domain identity helpers
- `useDomainDropdown()` - Domain selection UI
- `useDomainsManager()` - Full domain CRUD operations
- `useDomainStatus()` - Domain verification status

### Authentication

- `useAuth()` - Login, signup, logout, password reset
- `useMfa()` - TOTP/WebAuthn management
- `useWebAuthn()` - Passkey operations
- `useMagicLink()` - Passwordless login

### State Management

- `useAsyncHandler()` - Error handling wrapper (human/security/technical classification)
- `useCapabilities()` - Feature flag checks based on organization tier

### UI Utilities

- `useTheme()` - Dark mode toggle
- `useLanguage()` - i18n locale switching
- `useClipboard()` - Copy to clipboard
- `usePageTitle()` - Document title management

### Secret Operations

- `useSecret()` - Secret creation/retrieval
- `useMetadata()` - Secret metadata display
- `useSecretForm()` - Secret form state
- `useIncomingSecret()` - Incoming secret workflow

## Pain Points Observed

1. **Duplicated Components:**
   - `secrets/canonical/BaseSecretDisplay.vue` (23 lines, minimal slot-based)
   - `secrets/branded/BaseSecretDisplay.vue` (164 lines, complex branding logic)
   - Similar duplication in `SecretConfirmationForm.vue` and `SecretDisplayCase.vue`

2. **Flat Component Structure:**
   - 37 components directly in `/components` (legacy pattern)
   - 126 components organized by category (modern pattern)
   - No clear migration path between patterns

3. **Container Pattern Limitations:**
   - Only 3 containers exist (Homepage, ShowSecret, Dashboard)
   - Each container manually implements variant selection logic
   - No shared abstraction for interaction mode detection

4. **State Initialization Complexity:**
   - `window.__ONETIME_STATE__` consumed by both stores and composables
   - WindowService provides access layer but no centralized initialization
   - Each store implements its own `init()` pattern

5. **Branding Logic Scattered:**
   - `identityStore` handles basic branding state
   - `brandStore` handles API operations
   - `useBranding()` composable bridges the two
   - Container components duplicate domain strategy checks

6. **No Clear Boundaries:**
   - Components in `/components/base/` reference both canonical and branded variants
   - No enforcement of separation between interaction modes
   - Unclear which components belong to which mode

## Alignment with Interaction Modes Doc

### What matches the proposed architecture

- ✅ Container pattern exists (HomepageContainer, ShowSecretContainer, DashboardContainer)
- ✅ Canonical/branded folder structure in `components/secrets/` and `views/secrets/`
- ✅ `domainStrategy` detection via `identityStore`
- ✅ Composable layer abstracts state management
- ✅ Window service provides centralized access to server state

### What differs from the proposed architecture

- ❌ No `src/apps/` structure (components are in flat/categorized structure)
- ❌ Only secrets have canonical/branded variants, not full app separation
- ❌ Container pattern not generalized - each container implements custom logic
- ❌ No "interaction mode" abstraction - domain strategy handled per-container
- ❌ Mixed organization: some components flat, some categorized, no apps
- ❌ Branded components contain complex logic (164 lines) vs canonical stubs (23 lines)

## Key Architectural Patterns

### Container-Variant Pattern

```typescript
// Container determines which variant to render
const currentComponent = computed(() => {
  return domainStrategy === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
```

### Window State Hydration

```typescript
// Backend injects state → WindowService reads → Stores hydrate
const domainStrategy = WindowService.get('domain_strategy');
const brand = WindowService.get('domain_branding');
```

### Error Classification Pattern

```typescript
// All async operations use useAsyncHandler wrapper
const { wrap } = useAsyncHandler({
  notify: (message, severity) => notifications.show(message, severity),
  setLoading: (loading) => isLoading.value = loading,
  onError: (err) => error.value = err
});
```

### Store Initialization Pattern

```typescript
// Stores implement init() to avoid reactive circular dependencies
const store = useMyStore();
store.init(); // Call after store creation
```

## Component Count Analysis

- Total Vue components: **163**
- Total Vue views: **75**
- Flat components: **37** (23%)
- Categorized components: **126** (77%)
- Container components: **3**
- Canonical/branded duplicates: **6** components (3 canonical + 3 branded in secrets)

## Notable Architectural Decisions

1. **Server-driven state:** `window.__ONETIME_STATE__` is the source of truth
2. **Composition API everywhere:** `<script setup lang="ts">` pattern throughout
3. **Strict i18n:** All text via `$t()` keys, no hardcoded strings
4. **Pinia setup stores:** Composition API style, not Options API
5. **Error-first design:** Structured error handling via `useAsyncHandler`
6. **Capability-based features:** `useCapabilities()` gates functionality by tier
7. **Layout composition:** Layouts use slot-based composition from BaseLayout
8. **Route meta patterns:** Layouts, auth, and component modes specified in route meta

---

**Summary:** The architecture demonstrates a transition in progress - from flat component organization to domain-categorized structure, with experimental canonical/branded separation only in the secrets domain. The container pattern exists but isn't generalized. The proposed interaction modes architecture would formalize and extend these patterns across the entire application.
