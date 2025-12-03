# Vue Frontend Gap Analysis

Comparison of current Vue architecture against Interaction Modes target architecture.

**Generated**: 2025-12-01
**Inputs**:
- Current State: `docs/product/assessments/vue-frontend-discovery-state.md`
- Target State: `docs/product/interaction-modes.md`

---

## Executive Summary

The current architecture organizes code by **Domain Context** (canonical/branded), while the target organizes by **Interaction Mode** (what the user is doing). This fundamental shift requires restructuring from `src/views/` and `src/components/` into `src/apps/` with four distinct apps: Secret, Workspace, Kernel, and Session.

**Key findings**:
- 3 container components exist but lack generalized abstraction
- Only `secrets/` has canonical/branded separation (4 files, 2 pairs)
- 37 flat components need categorization
- No `src/apps/` structure exists
- State flow via `window.__ONETIME_STATE__` aligns well with target

---

## Gap Inventory

### Structural Gaps (Directory Organization)

| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| **Top-level structure** | `src/views/`, `src/components/` | `src/apps/secret/`, `workspace/`, `kernel/`, `session/` | Restructure | L | Router migration |
| **Secret app** | `views/secrets/canonical/`, `views/secrets/branded/` | `apps/secret/conceal/`, `apps/secret/reveal/` | Restructure | M | useSecretContext composable |
| **Workspace app** | `views/dashboard/`, `views/account/`, `views/teams/` | `apps/workspace/dashboard/`, `account/`, `teams/`, `domains/` | Restructure | M | Router migration |
| **Billing app** | `views/billing/` | `apps/billing/views/` | Restructure | S | Router migration |
| **Kernel app** | `views/colonel/` | `apps/colonel/views/` | Restructure | S | Router migration |
| **Session app** | `views/auth/` | `apps/session/views/` | Restructure | S | Router migration, traffic-controller |
| **Shared components** | `components/` (163 files, 37 flat) | `shared/components/`, `shared/branding/` | Restructure | L | Component audit |
| **Layouts** | `layouts/` (6 files) | `shared/layouts/` named by purpose | Refactor | S | Layout naming convention |

### Composable/Logic Gaps

| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| **Secret context** | `identityStore` + container component logic | `useSecretContext()` returning `actorRole`, `uiConfig` | New | M | Actor role matrix design |
| **Homepage mode** | Partial in `HomepageContainer` | `useHomepageMode()` composable | New | S | Backend `homepage_mode` in window state |
| **Brand presentation** | `useBranding()` + `brandStore` (mixed concerns) | `apps/secret/branding/useBrandPresentation.ts` | Refactor | M | Separate data from presentation |
| **Secret lifecycle** | Inline in components | `useSecretLifecycle()` FSM | New | M | State machine definition |
| **Traffic controller** | None (scattered redirects) | `apps/session/logic/traffic-controller.ts` | New | S | Auth flow documentation |

### Component Gaps

| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| **Container pattern** | 3 manual containers (`HomepageContainer`, `ShowSecretContainer`, `DashboardContainer`) | Composable-driven (`useSecretContext`) | Refactor | M | useSecretContext |
| **Branded components** | Canonical (185 lines) vs branded (131 lines) | Unified components with brand context | Refactor | M | useBrandPresentation |
| **Flat components** | 37 in `components/` root | Categorized in `shared/components/` | Restructure | M | Component audit |
| **Homepage** | `HomepageContainer` → variants | Single `Homepage.vue` with layout composition | Refactor | S | useHomepageMode, Layout components |
| **Access denied** | `DisabledHomepage`, `DisabledUI` | `AccessDenied.vue` in `apps/secret/views/reveal/` | Restructure | S | Homepage mode |

### Router Gaps

| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| **Router structure** | Single `router/index.ts` with feature files | Per-app `router.ts` aggregated in main router | Restructure | M | Apps structure |
| **Route order** | Implicit | Explicit: Session → Kernel → Workspace → Secret | Refactor | S | Router restructure |
| **Homepage routing** | `beforeEnter` sets `componentMode` | Guard redirects to `AccessDenied` | Refactor | S | useHomepageMode |

### State Management Gaps

| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| **Store organization** | 19 stores in `stores/` | Stores per-app + shared | Restructure | M | Apps structure |
| **Identity store** | `identityStore` exposes raw booleans | `useSecretContext()` exposes `uiConfig` | Refactor | M | Actor role matrix |
| **Brand store** | `brandStore` mixes data + API | Separate API (`shared/api/brand.ts`) from presentation | Refactor | S | Branding split |

---

## Gap Categories

### New (Must Create)

1. **`src/apps/` directory structure** — The foundational restructure
2. **`useSecretContext()` composable** — Actor role matrix (CREATOR/AUTH_RECIPIENT/ANON_RECIPIENT)
3. **`useHomepageMode()` composable** — Homepage mode gating (open/internal/external)
4. **`useSecretLifecycle()` composable** — Secret state FSM
5. **`traffic-controller.ts`** — Auth flow orchestration
6. **Per-app `router.ts` files** — Modular routing

### Restructure (Move/Reorganize)

1. **Views to Apps** — `views/secrets/` → `apps/secret/`, etc.
2. **Components** — 37 flat → categorized; domain components → app-specific
3. **Layouts** — Rename by purpose (TransactionalLayout, ManagementLayout)
4. **Stores** — Reorganize per-app where appropriate

### Refactor (Change Implementation)

1. **Container pattern** — Replace manual containers with composable-driven rendering
2. **Branded components** — Unify canonical/branded into single components with context
3. **Brand logic** — Split data fetching from presentation logic
4. **Homepage** — Single component with layout composition
5. **Router guards** — Align with new composables

### Remove (Delete/Deprecate)

1. **Container components** — `HomepageContainer`, `ShowSecretContainer`, `DashboardContainer` (after refactor)
2. **Duplicate components** — 4 canonical/branded files (2 pairs) in `secrets/`
3. **Flat component placement** — Move, don't keep in root

---

## Migration Priority

### Phase 1: Foundation (Effort: L)
**Goal**: Establish `src/apps/` structure without breaking existing code

1. Create `src/apps/` directory skeleton
2. Implement `useSecretContext()` composable
3. Implement `useHomepageMode()` composable
4. Create per-app router files (initially just re-exports)

**Dependencies**: None
**Risk**: Low (additive changes)

### Phase 2: Secret App Migration (Effort: M)
**Goal**: Move secret-related code to `apps/secret/`

1. Move `views/secrets/` → `apps/secret/reveal/`
2. Move homepage views → `apps/secret/conceal/`
3. Refactor container components to use `useSecretContext()`
4. Unify canonical/branded components

**Dependencies**: Phase 1 composables
**Risk**: Medium (changes visible routes)

### Phase 3: Session App Extraction (Effort: S)
**Goal**: Isolate authentication as standalone app

1. Move `views/auth/` → `apps/session/views/`
2. Create `traffic-controller.ts`
3. Update auth router

**Dependencies**: Phase 1 router structure
**Risk**: Low (auth is already somewhat isolated)

### Phase 4: Workspace App Migration (Effort: M)
**Goal**: Consolidate management views

1. Move `views/dashboard/`, `views/account/`, `views/teams/` → `apps/workspace/`
2. Move `views/billing/` → `apps/billing/`
3. Organize workspace into `dashboard/`, `account/`, `teams/`, `domains/` subfolders
4. Update workspace and billing routers

**Dependencies**: Phase 1 router structure
**Risk**: Medium (many views affected)

### Phase 5: Kernel App Migration (Effort: S)
**Goal**: Isolate admin views

1. Move `views/colonel/` → `apps/colonel/views/`
2. Update kernel router

**Dependencies**: Phase 1 router structure
**Risk**: Low (admin is already isolated)

### Phase 6: Shared Infrastructure (Effort: L)
**Goal**: Reorganize shared code

1. Categorize 37 flat components → `shared/components/`
2. Split branding: `shared/api/brand.ts` + `apps/secret/branding/`
3. Rename layouts by purpose
4. Reorganize stores

**Dependencies**: All app migrations complete
**Risk**: Medium (widespread import changes)

---

## Alignment Summary

### Already Aligned ✅

| Pattern | Current Implementation |
|---------|----------------------|
| Server-driven state | `window.__ONETIME_STATE__` → WindowService → Stores |
| Composition API | `<script setup lang="ts">` throughout |
| Store initialization | `store.init()` pattern |
| Error handling | `useAsyncHandler()` wrapper |
| Capability checks | `useCapabilities()` composable |

### Partially Aligned ⚠️

| Pattern | Current | Gap |
|---------|---------|-----|
| Container pattern | 3 containers exist | Not generalized, manual logic |
| Canonical/branded split | Only in `secrets/` | Need across Secret app |
| Domain strategy detection | Via `identityStore` | Need `useSecretContext()` abstraction |
| Layout composition | Slot-based from BaseLayout | Need purpose-named layouts |

### Not Aligned ❌

| Pattern | Current | Target |
|---------|---------|--------|
| Directory structure | `views/` + `components/` | `apps/` by interaction mode |
| Branding logic | Scattered across stores/composables | Centralized in `apps/secret/branding/` |
| Actor role matrix | Container components calculate | `useSecretContext()` returns `uiConfig` |
| Homepage mode | Partial in container | Dedicated composable + guard |
| Router organization | Single aggregated file | Per-app routers, ordered |

---

## Component Counts

| Category | Current | After Migration |
|----------|---------|-----------------|
| Total Vue components | 163 | ~163 (reorganized) |
| Total Vue views | 75 | ~75 (reorganized) |
| Flat components | 37 | 0 |
| Container components | 3 | 0 (replaced by composables) |
| Duplicate canonical/branded | 4 | 0 (unified) |
| New composables needed | 0 | 4 (`useSecretContext`, `useHomepageMode`, `useSecretLifecycle`, traffic-controller) |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Route breakage during migration | Medium | High | Parallel router files, feature flags |
| Import path errors | High | Low | Automated find/replace, TypeScript errors |
| Branding regression | Medium | Medium | E2E tests on branded domains |
| Auth flow disruption | Low | High | Session app migration last before Workspace |
| Performance regression | Low | Low | Bundle analysis before/after |

---

## Success Criteria

1. **Structure**: All code lives in `src/apps/{secret,workspace,kernel,session}/` or `src/shared/`
2. **Composables**: `useSecretContext()` returns `actorRole` and `uiConfig`, not raw booleans
3. **Containers**: No manual container components; variant selection via composables
4. **Branding**: `apps/secret/branding/` owns presentation; `shared/api/brand.ts` owns data
5. **Routing**: Per-app router files, aggregated in explicit order
6. **Flat components**: Zero components in `src/components/` root

---

## Next Steps

1. **Create migration plan** with detailed file-by-file mapping
2. **Implement Phase 1 composables** in isolation (can be tested without restructure)
3. **Pilot Secret app migration** with `apps/secret/reveal/ShowSecret.vue`
4. **Validate with branded domain** before proceeding
