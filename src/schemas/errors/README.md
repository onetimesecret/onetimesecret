
# Strongly Typed Error Handling in Vue.js

```
schemas/
├── api/
├── models/
├── errors/        # Consolidated error handling
│   ├── api.ts     # Technical/API errors
│   ├── domain.ts  # Business/domain errors
│   └── index.ts   # Shared types/utilities
└── utils/
```

## Why `schemas/errors`?

In most Vue.js applications, error handling is loosely typed and scattered across components, stores, and utilities. This project takes a different approach by treating errors as strongly typed data structures that are part of our application's schema.

### The Case for Schema-Based Errors

Error handling isn't just about catching exceptions - it's about modeling failure states as explicitly as our success states. By placing error types in `schemas/`, we:

- Define clear contracts for error states
- Enable compile-time error type checking
- Maintain consistent error structures
- Integrate error validation with our data validation
- Make error handling patterns explicit and discoverable

```typescript
// schemas/errors/api.ts
export class ApiError extends Error {
  constructor(
    public code: number,
    message: string,
    public details?: unknown
  ) {
    super(message);
  }
}

// schemas/errors/domain.ts
export class DomainError extends Error {
  constructor(
    public kind: 'validation' | 'business' | 'security',
    message: string,
    public context?: Record<string, unknown>
  ) {
    super(message);
  }
}
```

### Why Not Traditional Approaches?

Common alternatives include:
- `types/errors` - Focuses only on TypeScript types
- `utils/errors` - Suggests errors are just utilities
- Component-level handling - Scatters error logic

The `schemas/errors` approach emphasizes that errors are:
1. Fundamental to our design
2. Part of our data validation strategy
3. Strongly typed at runtime and compile time

### Integration with Vue.js

While this approach differs from typical Vue.js patterns, it complements Vue's reactivity system and composable patterns:

```typescript
// composables/useErrorHandler.ts
export function useErrorHandler() {
  const handleError = (error: unknown) => {
    // Type-safe error handling with schema validation
    const result = errorSchema.safeParse(error);
    if (!result.success) {
      // Handle invalid error structure
    }
    // Handle typed error
  };

  return { handleError };
}
```

## Learn More
- [Error Handling Architecture](./docs/architecture/ERRORS.md)
- [Schema Validation](./docs/schemas/README.md)
- [Type Safety](./docs/typescript/README.md)

## Contributing
We welcome discussion and contributions around this pattern. Open an issue to share your thoughts or experience implementing similar approaches.
