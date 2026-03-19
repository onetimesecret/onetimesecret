# Onetime Secret Schema System

Zod schemas for validating and transforming data between Vue frontend and Ruby/Redis backend.

## Architecture

- **Contracts** (`contracts/`): Canonical field names and output types
- **Shapes** (`shapes/v2/`, `shapes/v3/`): Wire-format specific transforms
- **Transforms** (`transforms.ts`): Centralized conversion utilities

## Data Flow

```
Redis → Ruby → API → Schema → Store → Component
(str) → (obj) → (json) → (validated) → (typed) → (display)
```

## Key Concepts

### Contracts vs Shapes

**Contracts** define *what* fields exist and their output types. They are version-agnostic.

**Shapes** define *how* fields are encoded on the wire for a specific API version (V2 or V3). They apply transforms to convert wire formats to contract types.

### Transform Strategy

All type conversions happen at API boundaries using centralized transforms:

- `transforms.fromString.*` — Redis/V2 string-to-type conversions
- `transforms.fromNumber.*` — V3 timestamp conversions
- `transforms.fromObject.*` — Nested object preprocessing

### State Terminology Migration

The API is migrating state field names for clarity:

| Old (V2) | New (V3) | Meaning |
|----------|----------|---------|
| `viewed` | `previewed` | Link accessed, confirmation shown |
| `received` | `revealed` | Secret content decrypted/consumed |

Both old and new values are sent for backward compatibility.

## Type Inference

All schemas export inferred types via `z.infer<>`:

```typescript
import { secretSchema, type Secret } from '@/schemas';

const secret = secretSchema.parse(apiData);
// secret is fully typed as Secret
```
