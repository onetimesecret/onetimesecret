# OpenAPI Generation - Proof of Concept Results

## Executive Summary

✅ **PoC Status: SUCCESSFUL**

The `@asteasolutions/zod-to-openapi` library is **fully compatible** with the Onetime Secret codebase and can generate complete OpenAPI 3.0.3 documents from existing Zod schemas.

---

## Test Results

### Test 1: Basic Functionality ✅
- **File**: `poc.ts`
- **Result**: All tests passed
- **Findings**:
  - Library generates valid OpenAPI 3.0.3 documents
  - Security schemes work correctly
  - Path registration works as expected
  - Complete document structure validated

### Test 2: Approach Analysis ✅
- **File**: `poc-approach-analysis.ts`
- **Result**: Optimal approach identified
- **Decision**: Use global Zod extension pattern

---

## Key Findings

### ✅ What Works

1. **Complete OpenAPI Documents**
   - Generates paths, servers, security schemes, tags
   - Full OpenAPI 3.0.3 compliance
   - No manual JSON Schema writing needed

2. **Schema Patterns**
   - ✅ Factory functions (createApiResponseSchema)
   - ✅ Custom transforms (transforms.fromString.number)
   - ✅ Complex nested objects
   - ✅ Enums and unions
   - ✅ Optional/nullable fields
   - ✅ Generic types

3. **Security & Authentication**
   - ✅ Multiple security schemes (Basic Auth, Session Auth)
   - ✅ Per-endpoint security requirements
   - ✅ Optional authentication (empty object in security array)

### ⚠️ Requirements

1. **Global Zod Extension**
   - Must call `extendZodWithOpenApi(z)` BEFORE schemas are defined
   - Solution: Created `src/schemas/openapi-setup.ts`
   - All schema files should import from this file

2. **Migration Path**
   - Update imports: `import { z } from '@/schemas/openapi-setup'`
   - Schemas work immediately without `.openapi()` metadata
   - Can add metadata incrementally for richer documentation

---

## Implementation Strategy

### Phase 1: Foundation (Week 1) - COMPLETED ✅

- [x] Install @asteasolutions/zod-to-openapi
- [x] Validate library compatibility
- [x] Test with real Onetime Secret schemas
- [x] Identify optimal integration approach
- [x] Create global Zod extension setup

### Phase 2: Otto Routes Parser (Week 1-2) - NEXT

Create `otto-routes-parser.ts` to:
- Parse Otto routes files (apps/api/*/routes)
- Extract HTTP methods, paths, authentication requirements
- Map routes to Logic classes
- Generate path metadata for OpenAPI registration

### Phase 3: Full Generation Script (Week 2)

Create `generate-openapi.ts` to:
- Import all schemas from `src/schemas/api/`
- Parse all Otto routes files
- Generate 6 separate OpenAPI specs:
  - `v2-openapi.json` (Public API v2)
  - `v3-openapi.json` (Public API v3)
  - `account-openapi.json` (Internal Account API)
  - `domains-openapi.json` (Internal Domains API)
  - `organizations-openapi.json` (Internal Organizations API)
  - `teams-openapi.json` (Internal Teams API)

### Phase 4: Schema Enhancement (Week 2-3)

Optionally enhance schemas with OpenAPI metadata:
```typescript
// Minimal (works as-is)
const secretSchema = z.object({
  id: z.string(),
  value: z.string()
});

// Enhanced (better documentation)
const secretSchema = z.object({
  id: z.string().openapi({
    description: 'Unique secret identifier',
    example: 'abc123def456'
  }),
  value: z.string().openapi({
    description: 'Encrypted secret value',
    example: 'encrypted_data_here'
  })
}).openapi('Secret');
```

### Phase 5: Automation (Week 3-4)

- Add npm scripts for generation
- Create CI/CD GitHub Actions workflow
- Set up validation pipeline
- Generate documentation site (Redoc/Swagger UI)

---

## Migration Guide

### For Existing Schema Files

**Option A: Gradual Migration (Recommended)**
1. Update import statement:
   ```typescript
   // Before
   import { z } from 'zod';

   // After
   import { z } from '@/schemas/openapi-setup';
   ```
2. Schema works immediately (no other changes needed)
3. Optionally add `.openapi()` metadata later

**Option B: Keep Existing Imports**
- Schemas can be registered using `registerComponent`
- Requires manual OpenAPI schema definition
- Not recommended (risk of drift)

### For New Schema Files

Always import from `openapi-setup.ts`:
```typescript
import { z } from '@/schemas/openapi-setup';

export const mySchema = z.object({
  field: z.string().openapi({
    description: 'Field description',
    example: 'Example value'
  })
}).openapi('MySchema');
```

---

## Running the PoC

```bash
# Basic functionality test
pnpm exec tsx src/scripts/openapi/poc.ts

# Approach analysis
pnpm exec tsx src/scripts/openapi/poc-approach-analysis.ts
```

---

## Next Steps

### Immediate (This Week)
1. ✅ Complete PoC validation
2. ⏳ Create Otto routes parser
3. ⏳ Build basic generation script for V3 API

### Short-term (Next 2 Weeks)
4. Extend to all 6 API applications
5. Add OpenAPI metadata to key schemas
6. Set up validation pipeline

### Medium-term (Weeks 3-4)
7. Create CI/CD automation
8. Generate documentation site
9. Add contract testing
10. Document maintenance procedures

---

## Files Created

- ✅ `poc.ts` - Basic functionality test
- ✅ `poc-approach-analysis.ts` - Approach comparison
- ✅ `../schemas/openapi-setup.ts` - Global Zod extension
- ✅ `README.md` - This file

---

## Decision: Proceed with Implementation ✅

**Recommendation**: Move forward with full implementation using `@asteasolutions/zod-to-openapi`.

**Confidence Level**: High (95%)

**Risk Level**: Low
- Library is mature and well-maintained
- Compatible with all Onetime Secret patterns
- Clear migration path
- No breaking changes required

**Timeline**: 4 weeks to complete all 6 API specs with automation

---

## Conclusion

The Proof of Concept successfully validated that `@asteasolutions/zod-to-openapi` is the right tool for generating OpenAPI documentation from Onetime Secret's Zod schemas. The library handles all current schema patterns, requires minimal code changes, and provides a clear path to complete, accurate, and maintainable API documentation.

**Status**: ✅ **READY TO PROCEED WITH FULL IMPLEMENTATION**
