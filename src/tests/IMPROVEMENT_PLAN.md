# Frontend Test Suite Improvement Plan

## Current State Assessment

### Metrics
- **Test Files:** 51
- **App Components:** 146 Vue files in `src/apps/`
- **Shared Composables:** 39 (only 9 have tests)
- **Skipped Tests:** 38 across 13 files
- **Pass Rate:** 843 passing, 35 skipped

### Coverage Gaps

#### Untested Composables (30 of 39)
High-priority (core functionality):
- `useAuth` - Authentication flows
- `useAccount` - Account management
- `useSecret` - Secret operations
- `useSecretForm` - Form handling
- `useCapabilities` - Feature gating
- `useClipboard` - Copy functionality
- `useLanguage` - i18n coordination

Medium-priority:
- `useActiveSessions` - Session management
- `useIncomingSecret` - Incoming secret handling
- `useMetadataList` - Metadata list operations
- `usePasswordChange` - Password flows
- `useWebAuthn` - Passkey authentication
- `useMagicLink` - Magic link flows
- `useDomain` / `useDomainStatus` - Domain management

Lower-priority (UI helpers):
- `useCharCounter`, `useClickOutside`, `useDropdown`, `useTextarea`
- `useMarkdownTheme`, `usePageTitle`, `useFormSubmission`
- `useColonelNavigation`, `usePrivacyOptions`, `useSecretExpiration`

#### Untested App Domains
- `src/apps/secret/` - Core secret creation/reveal flows (0 component tests)
- `src/apps/session/` - Login/signup/MFA views (0 tests)
- `src/apps/kernel/` - Admin/colonel interface (0 tests)
- `src/apps/workspace/billing/` - Billing components (0 tests)
- `src/apps/workspace/domains/` - Domain management views (0 tests)

---

## Phase 1: Foundation & Debt Cleanup (Week 1-2)

### 1.1 Create Shared Test Infrastructure

**File:** `src/tests/setup/test-utils.ts`
```typescript
// Centralized test utilities
- Global vue-i18n mock
- Pinia test factory with common store mocks
- Common component mount helpers
- Axios mock adapter factory
```

**File:** `src/tests/fixtures/index.ts`
```typescript
// Centralized fixtures
- Team fixtures (with extid, display_name)
- Metadata fixtures
- Customer/auth fixtures
- Domain fixtures
```

### 1.2 Fix Skipped Tests (38 tests across 13 files)

| File | Skipped | Issue Category |
|------|---------|----------------|
| `useDomainsManager.spec.ts` | 7 | Store interaction mocking |
| `useBranding.spec.ts` | 4 | Window state dependencies |
| `languageStore.spec.ts` | 3+ | MockService coordination |
| `domainsStore.spec.ts` | 3+ | Filtering logic |
| `authStore.spec.ts` | 2+ | Auth flow complexity |
| `useAsyncHandler.spec.ts` | 2 | Error classification edge cases |
| `useSecretConcealer.spec.ts` | 1 | Form submission flow |
| Others | ~16 | Various |

**Approach:**
1. Audit each skipped test - document why it was skipped
2. Categorize: fixable vs. needs redesign vs. obsolete
3. Fix or remove with justification

### 1.3 Update Test Documentation

Update `src/tests/CLAUDE.md`:
- Document test patterns and conventions
- Add fixture usage guidelines
- Document mock strategies for common dependencies
- Add troubleshooting section for common failures

---

## Phase 2: Critical Path Coverage (Week 3-4)

### 2.1 Authentication Composables

**Priority:** Critical - these control access to the entire app

```
src/tests/composables/
├── useAuth.spec.ts          # Login/logout, session checks
├── useAccount.spec.ts       # Account operations
├── useMfa.spec.ts           # Expand existing (currently minimal)
├── useWebAuthn.spec.ts      # Passkey registration/auth
└── useMagicLink.spec.ts     # Magic link flows
```

**Test scenarios for `useAuth`:**
- Initial auth state from window
- Login success/failure flows
- Logout and state cleanup
- Session expiry handling
- Auth check intervals

### 2.2 Secret Operations Composables

**Priority:** Critical - core product functionality

```
src/tests/composables/
├── useSecret.spec.ts        # Secret CRUD operations
├── useSecretForm.spec.ts    # Form state, validation
├── useIncomingSecret.spec.ts # Incoming secret handling
└── useSecretExpiration.spec.ts # TTL calculations
```

### 2.3 Store Coverage Expansion

Ensure all stores have baseline tests:
```
src/tests/stores/
├── accountStore.spec.ts     # EXISTS - verify coverage
├── brandStore.spec.ts       # NEW
├── colonelInfoStore.spec.ts # NEW
├── customerStore.spec.ts    # NEW
├── identityStore.spec.ts    # NEW
├── incomingStore.spec.ts    # NEW
├── systemSettingsStore.spec.ts # NEW
└── concealedMetadataStore.spec.ts # NEW
```

---

## Phase 3: App Component Testing (Week 5-6)

### 3.1 Secret App Components

**Directory:** `src/tests/apps/secret/`

```
components/
├── form/
│   ├── SecretForm.spec.ts        # Main form component
│   ├── SecretContentInputArea.spec.ts
│   ├── ConcealButton.spec.ts
│   └── GenerateButton.spec.ts
├── metadata/
│   ├── SecretLink.spec.ts        # Link display/copy
│   ├── BurnButtonForm.spec.ts    # Burn confirmation
│   └── StatusBadge.spec.ts
└── reveal/
    └── ShowSecret.spec.ts        # Secret reveal flow
```

### 3.2 Session App Components

**Directory:** `src/tests/apps/session/`

```
views/
├── LoginView.spec.ts
├── SignupView.spec.ts
├── ForgotPasswordView.spec.ts
└── MfaView.spec.ts
```

### 3.3 Workspace Account Components

**Directory:** `src/tests/apps/workspace/`

```
account/
├── settings/
│   ├── ProfileSettings.spec.ts
│   ├── SecuritySettings.spec.ts
│   └── ApiKeySettings.spec.ts
└── region/
    └── RegionSelector.spec.ts
```

---

## Phase 4: Integration & E2E Enhancement (Week 7-8)

### 4.1 Component Integration Tests

Test component compositions that work together:

```
src/tests/integration/
├── secret-creation-flow.spec.ts   # Form → Submit → Link display
├── secret-reveal-flow.spec.ts     # Load → Passphrase → Reveal
├── auth-flow.spec.ts              # Login → Dashboard redirect
└── domain-management-flow.spec.ts # Add → Verify → Configure
```

### 4.2 Playwright E2E Expansion

Current E2E tests are minimal. Expand:

```
tests/e2e/
├── auth/
│   ├── login.spec.ts
│   ├── signup.spec.ts
│   └── logout.spec.ts
├── secrets/
│   ├── create-secret.spec.ts
│   ├── reveal-secret.spec.ts
│   └── burn-secret.spec.ts
├── account/
│   ├── profile-settings.spec.ts
│   └── api-keys.spec.ts
└── smoke/
    └── critical-paths.spec.ts
```

---

## Phase 5: Quality Gates & Automation (Ongoing)

### 5.1 Coverage Thresholds

Add to `vitest.config.ts`:
```typescript
coverage: {
  provider: 'v8',
  reporter: ['text', 'html', 'lcov'],
  thresholds: {
    global: {
      statements: 60,  // Start achievable, increase over time
      branches: 50,
      functions: 60,
      lines: 60
    }
  }
}
```

### 5.2 Pre-commit Hooks

Add test validation to git hooks:
- Run affected tests on staged files
- Block commits with failing tests
- Warn on decreased coverage

### 5.3 CI Pipeline Integration

```yaml
# .github/workflows/test.yml additions
- Run full test suite on PR
- Generate coverage report
- Post coverage diff as PR comment
- Block merge if coverage decreases significantly
```

---

## Implementation Priority Matrix

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| P0 | Fix 38 skipped tests | Medium | High - reduces debt |
| P0 | Shared test infrastructure | Medium | High - enables velocity |
| P1 | `useAuth` tests | High | Critical - auth is core |
| P1 | `useSecret`/`useSecretForm` tests | High | Critical - product core |
| P1 | Secret form component tests | Medium | High - main user flow |
| P2 | Session view tests | Medium | Medium - login flows |
| P2 | Remaining store tests | Medium | Medium - state management |
| P2 | Integration tests | High | High - catch regressions |
| P3 | E2E expansion | High | Medium - slower feedback |
| P3 | Coverage thresholds | Low | Medium - quality gate |

---

## Success Metrics

### Short-term (4 weeks)
- [ ] Zero skipped tests (fix or remove with justification)
- [ ] All composables have at least smoke tests
- [ ] Shared fixtures eliminate schema drift

### Medium-term (8 weeks)
- [ ] 70%+ line coverage on `src/shared/`
- [ ] All critical user flows have integration tests
- [ ] Coverage gates active in CI

### Long-term (12 weeks)
- [ ] 80%+ overall coverage
- [ ] E2E tests cover all critical paths
- [ ] Test suite runs in < 30 seconds
- [ ] Zero flaky tests

---

## Notes

- Prioritize tests that catch real bugs over coverage metrics
- Prefer integration tests over unit tests for Vue components
- Keep test files close to implementation (`__tests__/` co-location is fine)
- Use `describe.concurrent` for independent test suites to speed up runs
