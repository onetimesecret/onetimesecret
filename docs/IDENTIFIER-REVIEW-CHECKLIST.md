# Opaque Identifier Pattern - Code Review Checklist

This checklist helps reviewers identify potential IDOR (Insecure Direct Object Reference) vulnerabilities in code changes involving entity identifiers.

## Quick Reference

| Context | Use This | NOT This |
|---------|----------|----------|
| URL paths | `entity.extid` | `entity.id` |
| API endpoints | `entity.extid` | `entity.objid` |
| Route params | `:extid` | `:id` |
| Vue component `:key` | `entity.id` ✓ | - |
| Store lookups | `entity.id` ✓ | - |
| Logging/debugging | Either ✓ | - |

## OWASP Alignment

| Our Term | OWASP Term | Risk Level |
|----------|------------|------------|
| `id` / `objid` | Direct Object Reference | HIGH if exposed in URLs |
| `extid` | Indirect Object Reference | LOW (enumeration-resistant) |

---

## Review Checklist

### 1. URL Construction

**Check all occurrences of:**
- Template literals with path patterns: `` `/org/${...}` ``, `` `/secret/${...}` ``, etc.
- Router navigation: `router.push()`, `router.replace()`
- `<router-link>` components with `:to` props
- API URL construction: `` `/api/.../${...}` ``

**Red flags:**
```typescript
// BAD - internal ID in URL
router.push(`/org/${org.id}`);
const url = `/api/organizations/${entity.id}`;
<router-link :to="`/domain/${domain.objid}`">

// GOOD - external ID in URL
router.push(`/org/${org.extid}`);
const url = `/api/organizations/${entity.extid}`;
<router-link :to="`/domain/${domain.extid}`">
```

### 2. Component Props and Emits

**Check:**
- Props passed down for navigation purposes
- Events emitting IDs for route changes

**Red flags:**
```typescript
// BAD - emitting internal ID for navigation
emit('select', entity.id);  // If this triggers navigation

// GOOD - emit extid for navigation
emit('select', entity.extid);

// OK - internal ID for non-navigation purposes
emit('focus', entity.id);  // Just for UI focus management
```

### 3. Store Functions

**Check:**
- API call construction in store actions
- Parameter naming conventions

**Red flags:**
```typescript
// BAD - parameter name suggests URL usage but accepts any string
async function fetchEntity(id: string) {
  return api.get(`/entities/${id}`);  // Using 'id' in URL!
}

// GOOD - explicit parameter naming
async function fetchEntity(extid: string) {
  return api.get(`/entities/${extid}`);
}

// BETTER - typed parameter
async function fetchEntity(extid: ExtId) {
  return api.get(`/entities/${extid}`);
}
```

### 4. Route Definitions

**Check:**
- Route parameter naming in path definitions

**Red flags:**
```typescript
// BAD
{ path: '/org/:id', ... }

// GOOD
{ path: '/org/:extid', ... }
```

### 5. Type Definitions

**Check:**
- Interface/type definitions for entities with IDs

**Best practice:**
```typescript
// GOOD - branded types for compile-time safety
interface Organization {
  id: ObjId;      // Internal - TypeScript prevents URL use
  extid: ExtId;   // External - required for URL builders
}
```

---

## When `.id` IS Appropriate

The following uses of `.id` are correct and should NOT be flagged:

1. **Vue component keys:**
   ```vue
   <div v-for="org in organizations" :key="org.id">
   ```

2. **Store lookups/comparisons:**
   ```typescript
   const org = organizations.find(o => o.id === selectedId);
   ```

3. **Display fallbacks:**
   ```typescript
   const label = org.display_name || org.id;
   ```

4. **Logging/debugging:**
   ```typescript
   console.log(`Processing org: ${org.id}`);
   ```

5. **Form field values (not affecting navigation):**
   ```vue
   <select v-model="selectedOrgId">
     <option v-for="org in orgs" :value="org.id">
   ```

---

## Automated Enforcement

### ESLint Rule

The `ots/no-internal-id-in-url` rule detects `.id` usage in URL contexts:

```bash
# Check for violations
pnpm lint

# The rule reports:
# ⚠️ Potential IDOR violation: "id" (internal ID) used in URL context. Use ".extid" instead.
```

### TypeScript Branded Types

Using `ObjId` and `ExtId` branded types provides compile-time safety:

```typescript
import { buildEntityPath, type ExtId } from '@/types/identifiers';

// This compiles:
buildEntityPath('org', org.extid);

// This fails at compile time:
buildEntityPath('org', org.id);  // Type error!
```

---

## Migration Notes

### Phase 1 (Current)
- Lenient Zod schemas accept any string, output branded types
- No breaking changes to existing code
- ESLint rule set to `warn`

### Phase 2 (Planned)
- Update function signatures to require `ExtId`/`ObjId`
- Add `toExtId()`/`toObjId()` at boundaries

### Phase 3 (Future)
- Switch to strict Zod schemas
- Enable ESLint rule as `error`
- Full compile-time and runtime enforcement

---

## References

- [OWASP IDOR Testing Guide](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/05-Authorization_Testing/04-Testing_for_Insecure_Direct_Object_References)
- `src/types/identifiers.ts` - Branded type definitions
- `src/build/eslint/no-internal-id-in-url.ts` - ESLint rule implementation
