# CLAUDE.md - Agent Guidelines for OneTimeSecret

BE CONCISE. Remember this is currently a one-person project. All scope needs to consider: I can only do one thing at a time -- is this important to spend time on? To spend time on now?

## Common Commands
- Dev server: `pnpm dev` or `pnpm dev:local` (with local config)
- Build: `pnpm build` (production) or `pnpm build:local` (development)
- Lint: `pnpm lint` or `pnpm lint:fix` (auto-fix issues)
- Type check: `pnpm type-check` or `pnpm type-check:watch` (watch mode)
- Vue tests: `pnpm test` (all) or `pnpm test:base run --filter=<test-name>` (single)
- Ruby tests: `pnpm rspec` or `bundle exec rspec <file_path>`
- E2E tests: `pnpm playwright` or `pnpm exec playwright test <test-file>`
- gh issue view [number]: Review GitHub issue details
- gh pr create: Create pull request with context-aware commit message

## Workflow: Feature Implementation

### 1. Research & Planning Phase
IMPORTANT: Always research and plan before coding. Use "think" or "think hard" for complex features.

- Read relevant files and documentation WITHOUT writing code yet
- Understand the Vue.js component structure and state management patterns
- Review existing components and utility functions
- Create implementation plan in markdown file or GitHub issue
- Document security implications and edge cases

### 2. Implementation Phase
Follow test-driven development when possible:

1. Write Vitest tests first (mark with "TDD - no implementation yet")
2. Confirm tests fail appropriately
3. Commit tests
4. Implement code to pass tests WITHOUT modifying tests
5. Ensure proper i18n integration and accessibility
6. Verify TypeScript types and error handling
7. Commit implementation

### 3. Validation & Review
- Run full test suite: `pnpm test`
- Check TypeScript compilation: `pnpm type-check`
- Run linting: `pnpm lint`
- Verify accessibility compliance
- Test in multiple browsers/devices
- Update documentation if needed
- Use `gh` to create descriptive pull request

## Code Style Guidelines
- **Commit Messages**: Use imperative mood, prefix with issue number `[#123]`
- **TypeScript**: Strict mode, explicit types, max 100 chars per line
- **Vue Components**: Use Composition API with `<script setup>`, camelCase props
- **Error Handling**: Use typed error handling with Zod for validations
- **State Management**: Use Pinia stores with `storeToRefs()` for reactive props
- **Imports**: Group imports (builtin → external → internal), alphabetize
- **Testing**: Max 300 lines per test file, use descriptive test names
- **API Logic**: Prefer small, focused functions (max 50 lines)
- **Styling**: Use Tailwind classes with consistent ordering
- **Accessibility**: Ensure all components are accessible, a11y, and follow WCAG guidelines
- Vue components should be written in a consistent style, using the Composition API with `<script setup lang="ts>`.
- Vue components should be styled using Tailwind classes with class lists should wrap long lines.
- Avoid deep nesting (max 3 levels) and limit function parameters (max 3).

## Code Style
- CRITICAL: Make MINIMAL changes to existing patterns
- Preserve existing naming conventions and file organization
- Use existing utility functions - avoid duplication
- Use dependency injection over global state

### Project Version Reference

#### Backend Framework Versions

Ruby 3.4
Rack 2.3.1
redis-rb 5.0.2
Redis Server 6

## Vuejs 3 Frontend Framework Versions
```json
{
  "vue": "^3.5.13",
  "vue-router": "^4.4.5",
  "pinia": "^3.0.1",
  "vue-i18n": "^11.1.2",
  "zod": "^3.24.1",
  "vite": "^5.4.11",
  "typescript": "^5.6.3",
  "vue-tsc": "^2.1.10",
  "vitest": "^2.1.8",
  "tailwindcss": "^3.4.14",
  "@headlessui/vue": "^1.7.23",
  "@vitejs/plugin-vue": "^5.1.4",
  "eslint": "^9.15.0",
  "axios": "^1.7.7"
}
```

## Additional Dependencies
```json
{
  "@sentry/vue": "^9.9.0",
  "date-fns": "^4.1.0",
  "dompurify": "^3.1.7",
  "marked": "^15.0.7",
  "altcha": "^1.1.0"
}


Vue - Composition API (setup, lang="ts")
Pinia - Setup Stores
Vue Router - Named components, route guards


## i18n

The default english translation is provided in the `src/locales/en.json` file.
Look at the heirarchical keys in the JSON file to understand the structure and
how properly reference them in Vue components (e.g. `$t('web.secrets.enterPassphrase')`).

DO NOT ADD TEXT unless using the i18n system. Use existing keys or create new ones.

## Multi-Task Guidelines
For complex features requiring parallel work:
- Use git worktrees for independent components
- Keep frontend changes separate from backend changes
- Use /clear between unrelated tasks to optimize context
- Document progress in commit messages

## Project-Specific Notes

### Core Components to Consider
- **Vue Components**: Composition API with `<script setup>`, reactive state management
- **State Management**: Pinia stores with typed actions and getters
- **Routing**: Vue Router with route guards and navigation
- **i18n**: Vue I18n with hierarchical translation keys
- **Validation**: Zod schemas for form and API validation
- **Styling**: Tailwind CSS with consistent class ordering
- **Testing**: Vitest for unit tests, Playwright for E2E

### Key File Locations
- **Vue Components**: `src/components/`, `src/views/`
- **Pinia Stores**: `src/stores/`
- **Types**: `src/types/`
- **Utilities**: `src/utils/`
- **Locales**: `src/locales/`
- **Configuration**: `vite.config.ts`, `tailwind.config.js`
- **Tests**: `src/components/__tests__/`, `tests/`

### Key Patterns
- **Component Structure**: Use Composition API with `<script setup lang="ts">`
- **State Management**: Pinia stores with `storeToRefs()` for reactive props
- **i18n Integration**: Use `$t()` for all text, organize keys hierarchically
- **Form Handling**: Zod validation with typed error handling
- **API Integration**: Axios with proper error handling and loading states
- **Accessibility**: ARIA attributes, semantic HTML, keyboard navigation

### Testing Patterns
- Mock Pinia stores for component testing
- Use fixtures in `tests/fixtures/` for consistent test data
- Test all component props and events
- Verify i18n keys and translations
- Test form validation and error states
- Check accessibility compliance with automated tools
