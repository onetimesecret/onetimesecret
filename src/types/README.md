# Types Organization

This directory contains TypeScript types and interfaces for the application.

## Structure

- `ui/` - UI-specific types that span multiple components
- `declarations/` - TypeScript declaration files
- `index.ts` - Type re-exports

## Conventions

### UI Types Organization

UI types are organized by feature/domain rather than by component:

```
ui/
  secret-links.ts  # Types for secret links feature
  notifications.ts # Types for notification system
  layouts.ts      # Types for layout components
```

### Type vs Interface

- Use `interface` for object shapes (default choice)
- Use `type` for unions, intersections, mapped types
- Group related types in single files
- Split files when they exceed 200-300 lines or serve different purposes

## Directory Relationships

### Type Source of Truth
- `src/schemas/*` - Zod schemas with inferred types for domain models and API contracts
- `src/types/*` - Global TypeScript declarations and interfaces
- `src/types/ui/*` - Component-spanning UI type definitions

```typescript
// Example: Type Sources

// Domain/API types (src/schemas/models/secret.ts)
export const SecretSchema = z.object({...})
export type Secret = z.infer<typeof SecretSchema>

// Global types (src/types/declarations/global.d.ts)
declare global {
  interface Window {
    config: AppConfig
  }
}

// UI types (src/types/ui/secret-links.ts)
export interface SecretLinkDisplay {
  id: string
  formattedDate: string
  status: DisplayStatus
}
```


## Usage Guidelines

### When to Use Each Directory
- `src/schemas/*` - For any types requiring runtime validation
- `src/types/*` - For global type declarations and shared interfaces
- `src/types/ui/*` - For component-spanning UI types without validation needs

### Best Practices
- Keep types close to their usage
- Use feature-based file names
- Prefer interfaces for object shapes
- Use types for unions/intersections
- Avoid type duplication across directories
- Re-export commonly used types through index files

### When to Use
- Default to `interface` for object shapes unless specific Zod, `type` or `class` features are needed.
- When runtime validation is needed: Use Zod schemas
- When types are shared across components: Use UI types
- Avoid classes in favor of interfaces and types

Note: interfaces are open to extension while types are closed, making interfaces more flexible for future changes.
