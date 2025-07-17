# Onetime Secret Vue.js Frontend Architecture Analysis

## Naming Conventions

These naming conventions provide clear file identification and prevent naming conflicts while improving codebase navigation and IDE support.

- Use PascalCase for components, layouts, Stores, views: `UserProfile.vue`
- Use descriptive suffixes ("discriminator suffixes") to indicate file type/purpose: `auth.routes.ts`
- Consider kebab-case for non-Vue specific files (e.g. `color-utils.ts`)

## Key Design Principles

1. **Component Reusability** - Shared components with strategy-specific implementations
2. **Strategy Isolation** - Clear separation between branded and canonical experiences
3. **Progressive Enhancement** - Core functionality works across both strategies
4. **Composable Logic** - Business logic separated from UI concerns
5. **Type Safety** - Strong TypeScript integration throughout

## Documentation Conventions

- Include a `README.md` in each major directory
- READMEs should document:
  - Directory purpose
  - Code conventions
  - Important patterns
  - Setup requirements
  - Usage examples
- READMEs be focused on their directory context and maintained as living documentation
