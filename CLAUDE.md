# CLAUDE.md - Agent Guidelines for OneTimeSecret

BE CONCISE. One-person project: focus on what's important NOW.

**PROCESSING NOTE**: Lines 1-56 contain CRITICAL context for immediate decisions. Lines 57+ provide detailed reference material - consult only when specific details are needed.

## Essential Commands
- Dev: `pnpm dev` (local: `pnpm dev:local`)
- Build: `pnpm build` (dev: `pnpm build:local`)
- Test: `pnpm test` (Ruby: `pnpm rspec`, E2E: `pnpm playwright`)
- Validate: `pnpm lint`, `pnpm type-check`
- Git: `gh issue view [number]`, `gh pr create`

## Critical Workflow
1. **Research First**: Read files, understand patterns, plan before coding
2. **TDD**: Write tests → fail → implement → pass → commit
3. **Validate**: Test suite → type-check → lint → accessibility

## Code Style (Non-Negotiable)
- **Vue**: Composition API `<script setup lang="ts">`, Pinia stores, i18n `$t()`
- **TypeScript**: Strict mode, explicit types, max 100 chars
- **Testing**: Vitest (max 300 lines), mock Pinia stores
- **Styling**: Tailwind classes, WCAG compliance
- **Minimal Changes**: Preserve patterns, use existing utilities

## Tech Stack
**Backend**: Ruby 3.4, Rack 2.3.1, Redis 6
**Frontend**: Vue 3.5.13, Pinia 3.0.1, Vue Router 4.4.5, TypeScript 5.6.3
**Build**: Vite 5.4.11, Vitest 2.1.8, Tailwind 3.4.14
**Validation**: Zod 3.24.1, i18n 11.1.2

## i18n Requirements
- All text via `$t('key.path')` from `src/locales/en.json`
- Hierarchical keys (e.g., `web.secrets.enterPassphrase`)
- NO hardcoded text

## Project Structure
- Components: `src/components/`, `src/views/`
- State: `src/stores/` (Pinia)
- Types: `src/types/`
- Utils: `src/utils/`
- Tests: `src/components/__tests__/`, `tests/`

## Security & Testing
- JSON payload validation: `src/utils/__tests__/windowBootstrapValidation.test.ts`
- XSS protection, HTML escaping validation
- Mock Ruby ERB templates, Zod schema validation

---

## Detailed Guidelines (Line 101+)
- [File Locations](#file-locations-detail)
- [Testing Patterns](#testing-patterns-detail)
- [Component Patterns](#component-patterns-detail)
- [Validation Testing](#validation-testing-detail)
- [Multi-Task Guidelines](#multi-task-guidelines-detail)
- [Dependency Details](#dependency-details)

---

## Dependency Details

### Additional Dependencies
```json
{
  "@sentry/vue": "^9.9.0",
  "date-fns": "^4.1.0",
  "dompurify": "^3.1.7",
  "marked": "^15.0.7"
}
```

## File Locations Detail

### Configuration Files
- **Vite**: `vite.config.ts`
- **Tailwind**: `tailwind.config.js`
- **TypeScript**: `tsconfig.json`
- **Locales**: `src/locales/en.json`

### Test Structure
- **Component Tests**: `src/components/__tests__/`
- **Integration Tests**: `tests/`
- **Fixtures**: `tests/fixtures/`
- **E2E Tests**: `tests/e2e/`

## Component Patterns Detail

### Vue Component Structure
```vue
<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { useStore } from '@/stores/store'

const store = useStore()
const { state } = storeToRefs(store)
</script>

<template>
  <div class="p-4 bg-white">{{ $t('key.path') }}</div>
</template>
```

### State Management Patterns
- Use `storeToRefs()` for reactive destructuring
- Pinia setup stores with typed actions
- Avoid global state, prefer dependency injection

### Form Handling
- Zod schemas for validation
- Typed error handling
- i18n error messages

## Testing Patterns Detail

### Component Testing
```typescript
import { mount } from '@vue/test-utils'
import { createTestingPinia } from '@pinia/testing'

const wrapper = mount(Component, {
  global: {
    plugins: [createTestingPinia()]
  }
})
```

### Test Organization
- Max 300 lines per test file
- Descriptive test names
- Mock Pinia stores
- Test props, events, i18n keys
- Accessibility compliance

## Validation Testing Detail

### JSON Payload Validation
- **Critical File**: `src/utils/__tests__/windowBootstrapValidation.test.ts`
- **Purpose**: Validate Ruby backend → Vue frontend data flow
- **Security**: XSS protection, HTML escaping validation
- **Coverage**: Mock ERB templates, Zod schemas, window.OneTime initialization

### Security Considerations
- Validate against XSS in window data
- Ensure HTML escaping of user content
- Maintain JSON structure integrity
- Type safety validation

## Multi-Task Guidelines Detail

### Git Workflow
- Use worktrees for independent components
- Separate frontend/backend changes
- Clear commit messages with issue numbers
- Use `/clear` between unrelated tasks
- Use `git mv` for renaming files. Do not just move or copy files without proper version control.

### Branch Management
- Keep features isolated
- Document progress in commits
- Test thoroughly before merge
