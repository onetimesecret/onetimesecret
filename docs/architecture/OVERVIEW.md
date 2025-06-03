# Architecture Overview

## System Components

Onetime Secret consists of two primary components working together:

**Ruby Backend** (`lib/onetime/logic/`)
- Consistent `success_data` methods for API responses
- Logic classes inherit from Base with helpers
- Validation in `raise_concerns` methods
- Data transformation in `process` methods

**Vue 3 Frontend** (`src/schemas/`, `src/types/api/`)
- TypeScript with Zod for runtime validation
- Layered architecture: Schemas → Services → Stores → Composables → Components
- Type-safe API integration

## Architecture Principles

### Layered Frontend Design
Each layer has a distinct responsibility:
- **Schemas**: Data structures and validation
- **Services**: API communication
- **Stores**: State management
- **Composables**: Reusable business logic
- **Components**: UI presentation

### Type Safety Strategy
- Schemas define types that flow through all layers
- Runtime validation at API boundaries
- Compile-time checking throughout the stack

### Error Handling
- Vue error boundaries for component errors
- Explicit handling for async operations
- Result types for expected failures
- Clear separation between recoverable and system errors

## Current Challenges

**Type Complexity**: Multiple transformation layers in frontend create maintenance overhead. The codebase currently over-engineers type safety at the cost of development velocity.

**API Integration**: Inconsistent serialization between Ruby and TypeScript requires complex frontend transformations.

**Error Handling**: Need consistent patterns across layers for both expected business errors and unexpected system failures.

## Related Documentation

- [Frontend Architecture](./frontend-architecture.md) - Vue 3 layered approach
- [Type Safety](./type-safety.md) - Managing types across the stack
- [Error Handling](./error-handling.md) - Patterns for robust error management
- [Config vs Settings](./config-vs-settings.md) - Configuration management conventions
