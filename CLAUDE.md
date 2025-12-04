# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

WRITE SHORT RESPONSES. BE CONCISE. Focus on what's important NOW.

Unless otherwise specified, pull requests target `develop` branch.

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
**Backend**: Ruby 3.4, Rack 3, Redis 7
**Frontend**: Vue 3.5, Pinia 3, Vue Router 4.4, TypeScript 5.6
**Build**: Vite 5.4., Vitest 2.1.8, Tailwind 3.4
**Validation**: Zod 4, i18n 11

## Architecture Overview

### Backend Structure
- **`apps/`**: Modular Rack applications (API v1/v2, Web Core)
  - `apps/api/v1/`: Legacy API with logic modules, controllers, models
  - `apps/api/v2/`: New API architecture with Otto auth strategies
  - `apps/web/core/`: Web application with views and serializers
  - `apps/base_application.rb`: Shared application foundation
- **`lib/`**: Core business logic and utilities
  - `lib/onetime/`: Main application classes (models, config, CLI)
  - `lib/middleware/`: Rack middleware for request processing
  - `lib/onetime/initializers/`: Boot-time setup modules
- **`bin/ots`**: CLI tool for administration and operations

### Frontend Structure (Interaction Modes Architecture)
- **`src/apps/`**: Domain-specific Vue applications
  - `src/apps/secret/`: Transactional flows (conceal, reveal, support)
  - `src/apps/workspace/`: Management (dashboard, account, billing, teams, domains)
  - `src/apps/session/`: Authentication (login, signup, MFA)
  - `src/apps/colonel/`: Admin (colonel)
- **`src/shared/`**: Cross-app shared resources
  - `src/shared/components/`: Categorized components (ui/, forms/, modals/, etc.)
  - `src/shared/composables/`: Shared composables
  - `src/shared/stores/`: Pinia state management
  - `src/shared/layouts/`: Layout components (TransactionalLayout, ManagementLayout, etc.)
- **`src/locales/`**: i18n JSON files (hierarchical keys)
- **`src/types/`**: TypeScript type definitions

## Development Commands

### Frontend Development
```bash
# Development with HMR
pnpm run dev

# Build for production
pnpm run build

# Type checking
pnpm run type-check
pnpm run type-check:watch

# Linting
pnpm run lint
pnpm run lint:fix
```

### Backend Development
```bash
# Console access
bin/ots console

# Start test database
pnpm run test:database:start
pnpm run test:database:stop
pnpm run test:database:status

# Administration
bin/ots migrate SCRIPT --run
bin/ots customers --list
bin/ots domains --list
```

### Testing

#### Ruby Tests
```bash
# RSpec tests
pnpm run test:rspec
pnpm run test:rspec:failures spec/path/file_spec.rb

# Tryouts framework (preferred for running all tests)
pnpm run test:tryouts:agent

# Individual tryout files (verbose, failures only)
pnpm run test:tryouts:failures try/path/file_try.rb:L100-L200
```

#### Frontend Tests
```bash
# Vitest unit tests
pnpm test
pnpm run test:coverage
pnpm run test:watch

# Playwright E2E
pnpm run playwright
```

### Quality Assurance
```bash
# Ruby linting
pnpm run rubocop
pnpm run rubocop:autocorrect

# Config validation
pnpm run config:validate

# Full test suite
pnpm run test:all:clean
```

## i18n Requirements
- All text via `$t('key.path')` from locale files in `src/locales/`
- Hierarchical keys (e.g., `web.secrets.enterPassphrase`)
- NO hardcoded text
- **UX guidance:** `src/locales/UX-TRANSLATION-GUIDE.md` (button text, character limits, pluralization)
- **Security guidance:** `src/locales/SECURITY-TRANSLATION-GUIDE.md` (auth error messages)

## Project Structure
- Apps: `src/apps/` (secret, workspace, session, colonel)
- Shared: `src/shared/` (components, composables, stores, layouts)
- Types: `src/types/`
- Tests: `tests/`, `src/**/__tests__/`

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
Please don't run web server processes. Ask the user to do it.
