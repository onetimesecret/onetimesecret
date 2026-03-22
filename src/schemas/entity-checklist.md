# Entity Test Coverage Checklist

Reference implementation: `receipt`

## Entity Status Overview

| Entity | Contract | V2 | V3 | Fixtures | Serializers | Tests | Status |
|--------|----------|----|----|----------|-------------|-------|--------|
| receipt | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| secret | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| feedback | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| customer | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| organization | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| organization_membership | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |
| custom_domain | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **DONE** |

**Tiers by complexity:**
- Tier 1: V2 exists, simple structure
- Tier 2: Core entities with relationships
- Tier 3: Complex (domain parsing, nested structures)

## Prerequisites (Step 0)

- [ ] `contracts/<entity>.ts` exports `<Entity>Canonical` types
- [ ] `shapes/v2/<entity>.ts` exists
- [ ] `shapes/v3/<entity>.ts` exists

## Test Implementation

1. [ ] `tests/schemas/shapes/fixtures/<entity>.fixtures.ts`
   - `createCanonical<Entity>(overrides?)` factory
   - State variant factories (e.g., `createShared<Entity>()`)
   - `compareCanonical<Entity>(a, b)` for equality checks

2. [ ] `tests/schemas/shapes/helpers/serializers.ts`
   - Wire types: `V2Wire<Entity>`, `V3Wire<Entity>`
   - Serializers: `toV2Wire<Entity>()`, `toV3Wire<Entity>()`

3. [ ] `tests/schemas/shapes/<entity>.roundtrip.spec.ts`
   - Import and call `runRoundTripTests(harness)`
   - Add entity-specific edge cases

4. [ ] `tests/schemas/shapes/<entity>.compat.spec.ts`
   - Import and call `runCompatibilityTests(harness)`
   - Document semantic differences (e.g., `null` → `false` transforms)

## Determining Status

```bash
# Step 0: Check prerequisites exist
ls src/schemas/contracts/<entity>.ts
ls src/schemas/shapes/v2/<entity>.ts
ls src/schemas/shapes/v3/<entity>.ts

# Steps 1-4: Check test files exist
ls src/tests/schemas/shapes/fixtures/<entity>.fixtures.ts
grep -l "toV2Wire<Entity>" src/tests/schemas/shapes/helpers/serializers.ts
ls src/tests/schemas/shapes/<entity>.roundtrip.spec.ts
ls src/tests/schemas/shapes/<entity>.compat.spec.ts

# Verify tests pass
pnpm vitest run src/tests/schemas/shapes/<entity> --reporter=dot
```
