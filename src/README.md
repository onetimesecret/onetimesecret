# Vue 3 File Naming Style Guide

## Core Rules

- Use PascalCase for components, layouts, Stores, views: `UserProfile.vue`
- Use descriptive suffixes ("discriminator suffixes") to indicate file type/purpose: `auth.routes.ts`
- Consider kebab-case for non-Vue specific files (e.g. `color-utils.ts`)

## Benefits

1. **Clear Purpose**: Suffixes immediately identify file responsibility
2. **Prevents Conflicts**: Allows related files to share base names without collision
3. **Better Organization**: Makes codebase more navigable and maintainable
4. **IDE Support**: Improves autocompletion and file searching

## By Directory

```
api/
  secrets.ts           // API endpoints/clients

assets/                // Static assets, styles, images
  style.css

components/
  HomepageTaglines.vue // UI components
  DefaultHeader.vue

composables/
  useMetadata.ts       // Composable hooks

layouts/
  DefaultLayout.vue    // Page layouts

locales/               // i18n translation files
  en.json

plugins/               // Plugin configurations
  errorHandler.ts

router/
  auth.routes.ts       // Route definitions

schemas/               // Data/validation schemas
  customer.ts

services/              // Business logic
  window.ts

stores/                // State management
  README.md            // Store guidelines & patterns
  authStore.ts

types/                 // TypeScript definitions
  forms.ts

utils/                 // Helper functions
  colorUtils.ts

views/                 // Page components
  Homepage.vue
```

## Common Suffixes
- `.vue` - Components, views, layouts
- `.routes.ts` - Route definitions and guards
- `.store.ts` - Pinia stores
- `.utils.ts` - Helper functions
- `.fixture.ts` - Test fixtures/data
- `.spec.ts` - Unit/integration tests
- `.d.ts` - TypeScript declarations
- `.json` - Data/configuration files
- `.md` - Documentation
- `.css` - Stylesheets

## Documentation Conventions
- Include a `README.md` in each major directory
- READMEs should document:
  - Directory purpose
  - Code conventions
  - Important patterns
  - Setup requirements
  - Usage examples
- Keep READMEs focused on their directory context
- Maintain READMEs as living documentation

This standardized naming helps us understand file purposes and reduces ambiguity.
