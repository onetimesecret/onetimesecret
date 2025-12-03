---
title: Interaction Modes Migration Manifest
type: migration-plan
status: pending
created: 2025-12-01
consumes: assessments/vue-frontend-gap-analysis.md
target: interaction-modes.md
approach: big-bang
---

# Interaction Modes Migration Manifest

Complete file-by-file mapping for restructuring from `src/views/` + `src/components/` to `src/apps/`.

## Pre-Migration Checklist

- [ ] All tests passing
- [ ] No uncommitted changes
- [ ] Create migration branch: `git checkout -b refactor/interaction-modes-migration`
- [ ] Backup current structure: `cp -r src src.backup`

---

## 1. Directory Structure Creation

```bash
mkdir -p src/apps/secret/{conceal,reveal,support,composables,branding}
mkdir -p src/apps/workspace/{dashboard,account,billing,teams,domains}
mkdir -p src/apps/colonel/views
mkdir -p src/apps/session/{views,logic}
mkdir -p src/shared/{components,layouts,branding,api}
```

Target structure:
```
src/apps/
├── secret/                    # Transactional (branded/canonical)
│   ├── conceal/               # Homepage, Incoming
│   ├── reveal/                # ShowSecret, ShowMetadata, Burn
│   ├── support/               # Feedback
│   ├── composables/           # useSecretContext, useSecretLifecycle
│   ├── branding/              # useBrandPresentation, BrandStyles
│   └── router.ts
├── workspace/                 # Management (always OTS-branded)
│   ├── dashboard/
│   ├── account/
│   ├── teams/
│   ├── domains/
│   └── router.ts
├── billing/                   # Commerce (subscription management)
│   ├── views/
│   └── router.ts
├── kernel/                    # Admin
│   ├── views/
│   └── router.ts
└── session/                   # Authentication gateway
    ├── views/
    ├── logic/
    └── router.ts

src/shared/
├── components/                # Reorganized from src/components
│   ├── base/
│   ├── ui/
│   ├── forms/
│   ├── feedback/
│   └── ...
├── layouts/
│   ├── TransactionalLayout.vue
│   ├── ManagementLayout.vue
│   ├── AdminLayout.vue
│   └── MinimalLayout.vue
├── branding/                  # Brand data + utilities (not presentation)
│   └── api/
└── composables/               # Shared composables
```

---

## 2. File Moves: Secret App

### 2.1 Conceal (Homepage + Incoming)

| Current | Target | Action |
|---------|--------|--------|
| `views/HomepageContainer.vue` | `apps/secret/conceal/Homepage.vue` | Refactor: merge container logic into composable |
| `views/Homepage.vue` | DELETE | Merged into Homepage.vue |
| `views/BrandedHomepage.vue` | DELETE | Merged into Homepage.vue |
| `views/DisabledHomepage.vue` | `apps/secret/conceal/AccessDenied.vue` | Rename |
| `views/DisabledUI.vue` | `apps/secret/conceal/DisabledUI.vue` | Move |
| `views/incoming/IncomingSecretForm.vue` | `apps/secret/conceal/IncomingForm.vue` | Rename |
| `views/incoming/IncomingSuccessView.vue` | `apps/secret/conceal/IncomingSuccess.vue` | Rename |

### 2.2 Reveal (Secrets + Metadata)

| Current | Target | Action |
|---------|--------|--------|
| `views/secrets/ShowSecretContainer.vue` | `apps/secret/reveal/ShowSecret.vue` | Refactor: merge branded/canonical |
| `views/secrets/branded/ShowSecret.vue` | DELETE | Merged |
| `views/secrets/canonical/ShowSecret.vue` | DELETE | Merged |
| `views/secrets/branded/UnknownSecret.vue` | DELETE | Merged |
| `views/secrets/canonical/UnknownSecret.vue` | `apps/secret/reveal/UnknownSecret.vue` | Refactor: unify |
| `views/secrets/ShowMetadata.vue` | `apps/secret/reveal/ShowMetadata.vue` | Move |
| `views/secrets/UnknownMetadata.vue` | `apps/secret/reveal/UnknownMetadata.vue` | Move |
| `views/secrets/BurnSecret.vue` | `apps/secret/reveal/BurnSecret.vue` | Move |

### 2.3 Support

| Current | Target | Action |
|---------|--------|--------|
| `views/Feedback.vue` | `apps/secret/support/Feedback.vue` | Move |

### 2.4 Secret Components

| Current | Target | Action |
|---------|--------|--------|
| `components/secrets/` | `apps/secret/components/` | Move entire directory |
| `components/secrets/branded/` | DELETE | Merge into unified components |
| `components/secrets/canonical/` | DELETE | Merge into unified components |
| `components/incoming/` | `apps/secret/components/incoming/` | Move |

---

## 3. File Moves: Workspace App

### 3.1 Dashboard

| Current | Target | Action |
|---------|--------|--------|
| `views/dashboard/DashboardContainer.vue` | DELETE | Logic moves to composables |
| `views/dashboard/DashboardIndex.vue` | `apps/workspace/dashboard/DashboardIndex.vue` | Move |
| `views/dashboard/DashboardRecent.vue` | `apps/workspace/dashboard/DashboardRecent.vue` | Move |
| `views/dashboard/DashboardEmpty.vue` | `apps/workspace/dashboard/DashboardEmpty.vue` | Move |
| `views/dashboard/DashboardBasic.vue` | `apps/workspace/dashboard/DashboardBasic.vue` | Move |
| `views/dashboard/SingleTeamDashboard.vue` | `apps/workspace/dashboard/SingleTeamDashboard.vue` | Move |

### 3.2 Domains

| Current | Target | Action |
|---------|--------|--------|
| `views/dashboard/DashboardDomains.vue` | `apps/workspace/domains/DomainsList.vue` | Rename |
| `views/dashboard/DashboardDomainAdd.vue` | `apps/workspace/domains/DomainAdd.vue` | Rename |
| `views/dashboard/DashboardDomainVerify.vue` | `apps/workspace/domains/DomainVerify.vue` | Rename |
| `views/dashboard/DashboardDomainBrand.vue` | `apps/workspace/domains/DomainBrand.vue` | Rename |

### 3.3 Account

| Current | Target | Action |
|---------|--------|--------|
| `views/account/AccountIndex.vue` | `apps/workspace/account/AccountIndex.vue` | Move |
| `views/account/AccountSettings.vue` | `apps/workspace/account/AccountSettings.vue` | Move |
| `views/account/ActiveSessions.vue` | `apps/workspace/account/ActiveSessions.vue` | Move |
| `views/account/ChangePassword.vue` | `apps/workspace/account/ChangePassword.vue` | Move |
| `views/account/CloseAccount.vue` | `apps/workspace/account/CloseAccount.vue` | Move |
| `views/account/DataRegion.vue` | `apps/workspace/account/DataRegion.vue` | Move |
| `views/account/MfaSettings.vue` | `apps/workspace/account/MfaSettings.vue` | Move |
| `views/account/RecoveryCodes.vue` | `apps/workspace/account/RecoveryCodes.vue` | Move |
| `views/account/region/` | `apps/workspace/account/region/` | Move directory |
| `views/account/settings/` | `apps/workspace/account/settings/` | Move directory |

### 3.4 Billing

| Current | Target | Action |
|---------|--------|--------|
| `views/billing/BillingOverview.vue` | `apps/workspace/billing/BillingOverview.vue` | Move |
| `views/billing/InvoiceList.vue` | `apps/workspace/billing/InvoiceList.vue` | Move |
| `views/billing/PlanSelector.vue` | `apps/workspace/billing/PlanSelector.vue` | Move |

### 3.5 Teams

| Current | Target | Action |
|---------|--------|--------|
| `views/teams/TeamsHub.vue` | `apps/workspace/teams/TeamsHub.vue` | Move |
| `views/teams/TeamView.vue` | `apps/workspace/teams/TeamView.vue` | Move |
| `views/teams/TeamMembers.vue` | `apps/workspace/teams/TeamMembers.vue` | Move |
| `views/teams/TeamSettings.vue` | `apps/workspace/teams/TeamSettings.vue` | Move |

### 3.6 Workspace Components

| Current | Target | Action |
|---------|--------|--------|
| `components/dashboard/` | `apps/workspace/components/dashboard/` | Move |
| `components/account/` | `apps/workspace/components/account/` | Move |
| `components/billing/` | `apps/workspace/components/billing/` | Move |
| `components/teams/` | `apps/workspace/components/teams/` | Move |
| `components/organizations/` | `apps/workspace/components/organizations/` | Move |

---

## 4. File Moves: Kernel App

| Current | Target | Action |
|---------|--------|--------|
| `views/colonel/ColonelIndex.vue` | `apps/colonel/views/ColonelIndex.vue` | Move |
| `views/colonel/ColonelUsers.vue` | `apps/colonel/views/ColonelUsers.vue` | Move |
| `views/colonel/ColonelSecrets.vue` | `apps/colonel/views/ColonelSecrets.vue` | Move |
| `views/colonel/ColonelDomains.vue` | `apps/colonel/views/ColonelDomains.vue` | Move |
| `views/colonel/ColonelSystem.vue` | `apps/colonel/views/ColonelSystem.vue` | Move |
| `views/colonel/ColonelSystemAuthDB.vue` | `apps/colonel/views/ColonelSystemAuthDB.vue` | Move |
| `views/colonel/ColonelSystemDatabase.vue` | `apps/colonel/views/ColonelSystemDatabase.vue` | Move |
| `views/colonel/ColonelSystemMainDB.vue` | `apps/colonel/views/ColonelSystemMainDB.vue` | Move |
| `views/colonel/ColonelSystemRedis.vue` | `apps/colonel/views/ColonelSystemRedis.vue` | Move |
| `views/colonel/ColonelUsageExport.vue` | `apps/colonel/views/ColonelUsageExport.vue` | Move |
| `views/colonel/ColonelBannedIPs.vue` | `apps/colonel/views/ColonelBannedIPs.vue` | Move |
| `views/colonel/SystemSettings.vue` | `apps/colonel/views/SystemSettings.vue` | Move |
| `components/colonel/` | `apps/colonel/components/` | Move |

---

## 5. File Moves: Session App

| Current | Target | Action |
|---------|--------|--------|
| `views/auth/Signin.vue` | `apps/session/views/Login.vue` | Rename |
| `views/auth/Signup.vue` | `apps/session/views/Register.vue` | Rename |
| `views/auth/EmailLogin.vue` | `apps/session/views/EmailLogin.vue` | Move |
| `views/auth/MfaVerify.vue` | `apps/session/views/MfaChallenge.vue` | Rename |
| `views/auth/PasswordReset.vue` | `apps/session/views/PasswordReset.vue` | Move |
| `views/auth/PasswordResetRequest.vue` | `apps/session/views/PasswordResetRequest.vue` | Move |
| `views/auth/VerifyAccount.vue` | `apps/session/views/VerifyAccount.vue` | Move |
| `components/auth/` | `apps/session/components/` | Move |

---

## 6. File Moves: Shared Infrastructure

### 6.1 Layouts

| Current | Target | Action |
|---------|--------|--------|
| `layouts/DefaultLayout.vue` | `shared/layouts/TransactionalLayout.vue` | Rename (Secret app) |
| `layouts/ImprovedLayout.vue` | `shared/layouts/ManagementLayout.vue` | Rename (Workspace app) |
| `layouts/ColonelLayout.vue` | `shared/layouts/AdminLayout.vue` | Rename (Kernel app) |
| `layouts/QuietLayout.vue` | `shared/layouts/MinimalLayout.vue` | Rename (Session app) |
| `layouts/AccountLayout.vue` | `shared/layouts/AccountLayout.vue` | Move (keep name) |
| `layouts/BaseLayout.vue` | `shared/layouts/BaseLayout.vue` | Move (keep name) |

### 6.2 Shared Components (37 flat → categorized)

| Current | Target | Action |
|---------|--------|--------|
| `components/base/` | `shared/components/base/` | Move |
| `components/ui/` | `shared/components/ui/` | Move |
| `components/common/` | `shared/components/common/` | Move |
| `components/icons/` | `shared/components/icons/` | Move |
| `components/logos/` | `shared/components/logos/` | Move |
| `components/layout/` | `shared/components/layout/` | Move |
| `components/navigation/` | `shared/components/navigation/` | Move |
| `components/modals/` | `shared/components/modals/` | Move |
| `components/ctas/` | `shared/components/ctas/` | Move |
| `components/closet/` | `shared/components/closet/` | Move |

### 6.3 Flat Components → Categorized

| Current (flat) | Target | Category |
|----------------|--------|----------|
| `components/ActivityFeed.vue` | `shared/components/ui/ActivityFeed.vue` | UI |
| `components/ButtonGroup.vue` | `shared/components/ui/ButtonGroup.vue` | UI |
| `components/CopyButton.vue` | `shared/components/ui/CopyButton.vue` | UI |
| `components/SplitButton.vue` | `shared/components/ui/SplitButton.vue` | UI |
| `components/ConfirmDialog.vue` | `shared/components/modals/ConfirmDialog.vue` | Modal |
| `components/SimpleModal.vue` | `shared/components/modals/SimpleModal.vue` | Modal |
| `components/DetailField.vue` | `shared/components/ui/DetailField.vue` | UI |
| `components/EmptyState.vue` | `shared/components/ui/EmptyState.vue` | UI |
| `components/ErrorDisplay.vue` | `shared/components/ui/ErrorDisplay.vue` | UI |
| `components/InfoTooltip.vue` | `shared/components/ui/InfoTooltip.vue` | UI |
| `components/MoreInfoText.vue` | `shared/components/ui/MoreInfoText.vue` | UI |
| `components/QuoteBlock.vue` | `shared/components/ui/QuoteBlock.vue` | UI |
| `components/QuoteSection.vue` | `shared/components/ui/QuoteSection.vue` | UI |
| `components/StatusBar.vue` | `shared/components/ui/StatusBar.vue` | UI |
| `components/StarsRating.vue` | `shared/components/ui/StarsRating.vue` | UI |
| `components/BasicFormAlerts.vue` | `shared/components/forms/BasicFormAlerts.vue` | Forms |
| `components/PasswordStrengthChecker.vue` | `shared/components/forms/PasswordStrengthChecker.vue` | Forms |
| `components/DomainForm.vue` | `apps/workspace/components/domains/DomainForm.vue` | Workspace |
| `components/DomainInput.vue` | `apps/workspace/components/domains/DomainInput.vue` | Workspace |
| `components/DomainsTable.vue` | `apps/workspace/components/domains/DomainsTable.vue` | Workspace |
| `components/DomainVerificationInfo.vue` | `apps/workspace/components/domains/DomainVerificationInfo.vue` | Workspace |
| `components/VerifyDomainDetails.vue` | `apps/workspace/components/domains/VerifyDomainDetails.vue` | Workspace |
| `components/CustomDomainPreview.vue` | `apps/workspace/components/domains/CustomDomainPreview.vue` | Workspace |
| `components/FeedbackForm.vue` | `apps/secret/components/support/FeedbackForm.vue` | Secret |
| `components/FeedbackModalForm.vue` | `apps/secret/components/support/FeedbackModalForm.vue` | Secret |
| `components/FeedbackToggle.vue` | `apps/secret/components/support/FeedbackToggle.vue` | Secret |
| `components/HomepageTaglines.vue` | `apps/secret/components/conceal/HomepageTaglines.vue` | Secret |
| `components/DisabledHomepageTaglines.vue` | `apps/secret/components/conceal/DisabledHomepageTaglines.vue` | Secret |
| `components/HomepageAccessToggle.vue` | `apps/secret/components/conceal/HomepageAccessToggle.vue` | Secret |
| `components/GlobalBroadcast.vue` | `shared/components/ui/GlobalBroadcast.vue` | UI |
| `components/GithubCorner.vue` | `shared/components/ui/GithubCorner.vue` | UI |
| `components/MovingGlobules.vue` | `shared/components/ui/MovingGlobules.vue` | UI |
| `components/ThemeToggle.vue` | `shared/components/ui/ThemeToggle.vue` | UI |
| `components/LanguageToggle.vue` | `shared/components/ui/LanguageToggle.vue` | UI |
| `components/JurisdictionToggle.vue` | `shared/components/ui/JurisdictionToggle.vue` | UI |
| `components/MinimalDropdownMenu.vue` | `shared/components/ui/MinimalDropdownMenu.vue` | UI |
| `components/EmailObfuscator.vue` | `shared/components/ui/EmailObfuscator.vue` | UI |

### 6.4 Errors

| Current | Target | Action |
|---------|--------|--------|
| `views/errors/ErrorNotFound.vue` | `shared/components/errors/ErrorNotFound.vue` | Move |
| `views/errors/ErrorPage.vue` | `shared/components/errors/ErrorPage.vue` | Move |
| `views/NotFound.vue` | DELETE | Use ErrorNotFound |

---

## 7. New Files to Create

### 7.1 Composables

| File | Purpose |
|------|---------|
| `apps/secret/composables/useSecretContext.ts` | Actor role matrix (CREATOR/AUTH_RECIPIENT/ANON_RECIPIENT) → uiConfig |
| `apps/secret/composables/useHomepageMode.ts` | Homepage gating (open/internal/external) |
| `apps/secret/composables/useSecretLifecycle.ts` | Secret FSM (idle → passphrase → ready → revealed → burned) |
| `apps/session/logic/traffic-controller.ts` | Auth flow orchestration (where to redirect after login/logout) |

### 7.2 Routers

| File | Purpose |
|------|---------|
| `apps/secret/router.ts` | Routes: `/`, `/secret/*`, `/receipt/*`, `/incoming/*`, `/feedback` |
| `apps/workspace/router.ts` | Routes: `/dashboard/*`, `/account/*`, `/teams/*`, `/domains/*` |
| `apps/billing/router.ts` | Routes: `/billing/*` |
| `apps/colonel/router.ts` | Routes: `/colonel/*` |
| `apps/session/router.ts` | Routes: `/signin`, `/signup`, `/logout`, `/forgot`, `/reset-password`, `/mfa-verify` |

> **Note**: After migration, these router.ts files are **placeholder stubs** with TODO comments. Routes remain in `src/router/*.routes.ts` until manual route consolidation.

### 7.3 Branding

| File | Purpose |
|------|---------|
| `apps/secret/branding/useBrandPresentation.ts` | Applies brand to UI (CSS vars, theme) |
| `apps/secret/branding/BrandStyles.ts` | CSS variable injection |
| `shared/branding/api/brand.ts` | Brand data fetching (used by Workspace for config) |

---

## 8. Router Refactoring

### Current Router Structure
```
router/
├── index.ts              # Main aggregator
├── account.routes.ts
├── auth.routes.ts
├── billing.routes.ts
├── colonel.routes.ts
├── dashboard.routes.ts
├── guards.routes.ts
├── incoming.routes.ts
├── layout.config.ts
├── metadata.routes.ts
├── public.routes.ts
├── secret.routes.ts
└── teams.routes.ts
```

### Target Router Structure
```
router/
├── index.ts              # Aggregates app routers in order
└── guards.ts             # Global guards only

apps/secret/router.ts     # TODO: Combine public.routes + secret.routes + incoming.routes + metadata.routes
apps/workspace/router.ts  # TODO: Combine dashboard.routes + account.routes + teams.routes
apps/billing/router.ts    # TODO: Combine billing.routes
apps/colonel/router.ts     # TODO: Combine colonel.routes
apps/session/router.ts    # TODO: Combine auth.routes
```

### New `router/index.ts`
```typescript
import { createRouter, createWebHistory } from 'vue-router';
import { routes as sessionRoutes } from '@/apps/session/router';
import { routes as kernelRoutes } from '@/apps/colonel/router';
import { routes as workspaceRoutes } from '@/apps/workspace/router';
import { routes as secretRoutes } from '@/apps/secret/router';

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    // Order matters: most specific first
    ...sessionRoutes,    // /signin, /signup, etc.
    ...kernelRoutes,     // /colonel/*
    ...workspaceRoutes,  // /dashboard/*, /account/*, etc.
    ...secretRoutes,     // /, /secret/*, /receipt/* (includes catch-all)
  ],
});
```

---

## 9. Import Rewrite Patterns

### Path Alias Updates

| Old Import | New Import |
|------------|------------|
| `@/views/secrets/` | `@/apps/secret/reveal/` |
| `@/views/dashboard/` | `@/apps/workspace/dashboard/` |
| `@/views/account/` | `@/apps/workspace/account/` |
| `@/views/billing/` | `@/apps/workspace/billing/` |
| `@/views/teams/` | `@/apps/workspace/teams/` |
| `@/views/colonel/` | `@/apps/colonel/views/` |
| `@/views/auth/` | `@/apps/session/views/` |
| `@/views/incoming/` | `@/apps/secret/conceal/` |
| `@/components/secrets/` | `@/apps/secret/components/` |
| `@/components/dashboard/` | `@/apps/workspace/components/dashboard/` |
| `@/components/account/` | `@/apps/workspace/components/account/` |
| `@/components/billing/` | `@/apps/workspace/components/billing/` |
| `@/components/teams/` | `@/apps/workspace/components/teams/` |
| `@/components/colonel/` | `@/apps/colonel/components/` |
| `@/components/auth/` | `@/apps/session/components/` |
| `@/layouts/` | `@/shared/layouts/` |

### Automated Rewrite Script
```bash
# Run from src/ directory
find . -name "*.vue" -o -name "*.ts" | xargs sed -i '' \
  -e "s|@/views/secrets/|@/apps/secret/reveal/|g" \
  -e "s|@/views/dashboard/|@/apps/workspace/dashboard/|g" \
  -e "s|@/views/account/|@/apps/workspace/account/|g" \
  -e "s|@/views/billing/|@/apps/workspace/billing/|g" \
  -e "s|@/views/teams/|@/apps/workspace/teams/|g" \
  -e "s|@/views/colonel/|@/apps/colonel/views/|g" \
  -e "s|@/views/auth/|@/apps/session/views/|g" \
  -e "s|@/views/incoming/|@/apps/secret/conceal/|g" \
  -e "s|@/layouts/|@/shared/layouts/|g"
```

---

## 10. Files to Delete After Migration

| File | Reason |
|------|--------|
| `views/HomepageContainer.vue` | Logic merged into Homepage.vue + useSecretContext |
| `views/Homepage.vue` | Merged into apps/secret/conceal/Homepage.vue |
| `views/BrandedHomepage.vue` | Merged |
| `views/secrets/ShowSecretContainer.vue` | Logic merged into ShowSecret.vue + useSecretContext |
| `views/secrets/branded/ShowSecret.vue` | Merged with canonical |
| `views/secrets/branded/UnknownSecret.vue` | Merged with canonical |
| `views/dashboard/DashboardContainer.vue` | Logic moves to composables |
| `views/NotFound.vue` | Use shared ErrorNotFound |
| `router/public.routes.ts` | Merged into apps/secret/router.ts |
| `router/secret.routes.ts` | Merged into apps/secret/router.ts |
| `router/incoming.routes.ts` | Merged into apps/secret/router.ts |
| `router/metadata.routes.ts` | Merged into apps/secret/router.ts |
| `router/dashboard.routes.ts` | Merged into apps/workspace/router.ts |
| `router/account.routes.ts` | Merged into apps/workspace/router.ts |
| `router/billing.routes.ts` | Merged into apps/billing/router.ts |
| `router/teams.routes.ts` | Merged into apps/workspace/router.ts |
| `router/colonel.routes.ts` | Merged into apps/colonel/router.ts |
| `router/auth.routes.ts` | Merged into apps/session/router.ts |
| `router/layout.config.ts` | No longer needed (layouts per-app) |

---

## 11. Validation Checklist

### Post-Migration Tests

- [ ] `pnpm run type-check` passes
- [ ] `pnpm run lint` passes
- [ ] `pnpm run build` succeeds
- [ ] `pnpm test` passes
- [ ] Manual smoke test: Homepage loads
- [ ] Manual smoke test: Create secret works
- [ ] Manual smoke test: View secret works (canonical)
- [ ] Manual smoke test: View secret works (branded domain)
- [ ] Manual smoke test: Dashboard loads
- [ ] Manual smoke test: Login/logout works
- [ ] Manual smoke test: Colonel admin loads
- [ ] E2E tests: `pnpm playwright` passes

### Structure Validation

- [ ] No files remain in `src/views/` (directory deleted)
- [ ] No flat components in `src/components/` root
- [ ] All imports resolve (no broken paths)
- [ ] Router loads all routes correctly
- [ ] Layouts render correctly per-app

---

## 12. Execution Order

```
1. Create directory structure
2. Create new composables (useSecretContext, useHomepageMode, useSecretLifecycle)
3. Create per-app routers
4. Move Kernel app (smallest, lowest risk)
5. Move Session app (isolated)
6. Move Workspace app (many files, medium risk)
7. Move Secret app (requires merge work, highest complexity)
8. Move shared infrastructure (layouts, components)
9. Update main router/index.ts
10. Run import rewrites
11. Delete old files/directories
12. Run validation checklist
```

---

## Summary

| Category | Files Moved | Files Created | Files Deleted |
|----------|-------------|---------------|---------------|
| Secret App | 15 | 4 | 6 |
| Workspace App | 32 | 1 | 1 |
| Kernel App | 12 | 1 | 0 |
| Session App | 7 | 2 | 0 |
| Shared | 50+ | 3 | 1 |
| Router | 0 | 4 | 10 |
| **Total** | ~116 | 15 | 18 |
