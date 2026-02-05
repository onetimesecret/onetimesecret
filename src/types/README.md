# Types Organization

This directory contains TypeScript types, re-exports from schemas, and runtime constants.

## Structure

- `ui/` - UI-specific types (layouts, forms, notifications)
- `declarations/` - TypeScript declaration files
- `index.ts` - Barrel exports

## Pattern: Schema-Derived Types

Types are derived from Zod schemas in `src/schemas/`. This file re-exports them with runtime constants:

```typescript
// Re-export schemas and types from canonical location
export {
  schemaName,
  type TypeName,
} from '@/schemas/models/xyz';

// Runtime constants (kept here, not in schemas)
export const CONSTANTS = { ... } as const;

// Helper functions (kept here)
export function formatValue() { ... }
```

See `organization.ts` and `billing.ts` for reference implementations.

## When to Use Each Location

- `src/schemas/` - Zod schemas as source of truth, types via `z.infer<>`
- `src/types/` - Re-exports, runtime constants, helper functions, branded types
- `src/types/ui/` - Pure UI types without API boundary validation
