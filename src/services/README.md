# Services

This directory contains service modules that provide consistent interfaces for
interacting with external resources and encapsulating complex logic.

## Bootstrap State Architecture

Server-injected state is accessed through a two-phase architecture:

### Phase 0: Pre-Pinia Access (`bootstrap.service.ts`)

For code that runs before Pinia is initialized (e.g., router guards, early
initialization), use the bootstrap service:

```typescript
import { getBootstrapValue, getBootstrapSnapshot } from '@/services/bootstrap.service';

// Get a single value
const locale = getBootstrapValue('locale');

// Get the full snapshot
const snapshot = getBootstrapSnapshot();
```

### Phase 1: Pinia Store Access (`bootstrapStore.ts`)

Once Pinia is initialized, use the bootstrap store for reactive state:

```typescript
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';

const bootstrap = useBootstrapStore();
const { authenticated, locale, cust } = storeToRefs(bootstrap);

// Update after API calls
await bootstrap.refresh();
```

## Migration Notes

The `WindowService` (`window.service.ts`) was deprecated and removed as part of
the bootstrap store migration (Issue #2365). All access to server-injected state
should now go through:

1. `bootstrap.service.ts` - For pre-Pinia access (Phase 0)
2. `bootstrapStore.ts` - For reactive Pinia access (Phase 1)

Direct access to `window.__BOOTSTRAP_STATE__` is prohibited by ESLint rule.

## Service vs. Utility

### Service Characteristics
- Stateless (typically)
- Encapsulates complex logic
- Provides a consistent interface for interacting with external resources
- Often represents a domain-specific abstraction
- Can be easily mocked/tested in isolation

### Utility Characteristics
- Pure functions
- Typically stateless
- Simple, direct transformations
- No complex logic or side effects

### Why Use Services in Vue 3?

1. **Separation of Concerns** - Decouple business logic from components
2. **Testability** - Easy to mock in tests
3. **Cross-Cutting Concerns** - Consistent interface, SSR compatibility, error handling, logging, type safety
