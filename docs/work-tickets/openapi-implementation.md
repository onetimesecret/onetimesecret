# OpenAPI Schema Generation Implementation

**Epic**: Implement comprehensive OpenAPI 3.0.3 documentation for all Onetime Secret APIs

**Status**: In Progress (Phase 1 Complete)

**Assignee**: Development Team

**Priority**: High

**Labels**: `documentation`, `api`, `openapi`, `typescript`, `infrastructure`

---

## Overview

Overhaul the OpenAPI v3 schema generation for Onetime Secret's API ecosystem, creating a TypeScript-first, automated approach that maintains sync between Zod schemas, API implementations, and documentation.

### Goals
- Single source of truth for API contracts (Zod schemas)
- Automated OpenAPI spec generation
- CI/CD integration for continuous validation
- Comprehensive documentation for all 6 APIs (68 total routes)

---

## Original Plan (4-Week Timeline)

### Phase 1: Foundation & Tooling (Weeks 1-2)
- [x] Set up `@asteasolutions/zod-to-openapi` library
- [x] Create Otto routes parser to discover endpoints
- [x] Build automated generation scripts
- [x] Establish CI/CD pipeline

### Phase 2: Schema Enhancement (Weeks 2-3)
- [ ] Add OpenAPI metadata to all existing Zod schemas
- [ ] Create endpoint metadata registry for all APIs
- [ ] Generate separate specs for all 6 APIs:
  - [x] Account API (7 routes) - **COMPLETE**
  - [ ] V3 API (18 routes) - **50% complete (9/18)**
  - [ ] V2 API (17 routes) - **Not started**
  - [ ] Domains API (13 routes) - **Not started**
  - [ ] Organizations API (5 routes) - **Not started**
  - [ ] Teams API (8 routes) - **Not started**

### Phase 3: Separation & Validation (Weeks 3-4)
- [ ] Split into public vs internal API specifications
- [ ] Create comprehensive validation suite
- [ ] Set up contract testing framework
- [ ] Add response/request validation

### Phase 4: Automation & Process (Week 4+)
- [ ] Pre-commit hooks for automatic spec generation
- [ ] Enhanced CI/CD validation
- [ ] Establish quarterly review process
- [ ] Document maintenance procedures

---

## ✅ Completed Work

### Infrastructure (100% Complete)

**Files Created:**
- `src/schemas/openapi-setup.ts` - Global Zod OpenAPI extension
- `src/scripts/openapi/otto-routes-parser.ts` - Route discovery (68 routes across 6 APIs)
- `src/scripts/openapi/route-config.ts` - Data-driven route mapping utilities
- `src/scripts/openapi/generate-all-specs.ts` - Master orchestrator
- `src/scripts/openapi/generate-account-spec.ts` - Account API generator
- `src/scripts/openapi/generate-v3-spec.ts` - V3 API generator
- `src/scripts/openapi/test-parser.ts` - Parser test suite
- `src/schemas/api/account/stripe-types.ts` - Stripe type definitions
- `.github/workflows/openapi-generation.yml` - CI/CD automation

**Generated Outputs:**
- `docs/api/account-openapi.json` - 1116 lines, 7 endpoints
- `docs/api/v3-openapi.json` - 9 endpoints (partial)

### Features Implemented

**1. Otto Routes Parser**
- Automatic discovery of all API routes by scanning `apps/api/*/routes`
- Extracts: method, path, handler, auth requirements, CSRF exemptions
- Discovered: 68 routes across 6 APIs
- Dynamic API discovery (no hardcoded lists)

**2. Account API Generator (100% Coverage)**
- All 7 routes fully documented
- Proper Stripe type definitions (Customer, Subscription)
- Data-driven route mapping pattern
- Request/response schemas for all endpoints

**3. V3 API Generator (50% Coverage)**
- 9 of 18 routes documented:
  - POST /secret/conceal
  - POST /secret/generate
  - GET /receipt/recent
  - GET /receipt/:identifier
  - POST /receipt/:identifier/burn
  - GET /private/recent
  - GET /private/:identifier
  - POST /private/:identifier/burn
  - GET /status

**4. CI/CD Automation**
- GitHub Actions workflow triggers on schema changes
- Auto-validates generated JSON
- Commits updated specs to repository
- Posts PR comments when specs change

**5. Code Quality**
- Data-driven route configuration (vs manual if/else chains)
- Reusable error response templates
- TypeScript type-safe throughout
- Comprehensive inline documentation

### npm Scripts Added
```bash
pnpm run openapi:generate          # Generate all API specs
pnpm run openapi:generate:all      # Same as above
pnpm run openapi:generate:v3       # Generate V3 API only
pnpm run openapi:generate:account  # Generate Account API only
pnpm run openapi:test-parser       # Test route parser
pnpm run openapi:poc               # Validate library compatibility
```

---

## 🚧 Remaining Work

### High Priority: Complete API Coverage (Est: 2-3 days)

**V3 API - Finish Remaining Routes (9 routes)**
- [ ] GET /secret/:identifier
- [ ] GET /secret/:identifier/status
- [ ] POST /secret/status
- [ ] POST /secret/:identifier/reveal
- [ ] OPTIONS /secret/generate
- [ ] OPTIONS /secret/conceal
- [ ] GET /supported-locales
- [ ] GET /version
- [ ] POST /feedback

**V2 API Generator (17 routes)**
- [ ] Create `generate-v2-spec.ts`
- [ ] Map all 17 V2 endpoints
- [ ] Handle string-serialized responses (V2 characteristic)
- [ ] Add to master generation script

**Domains API Generator (13 routes)**
- [ ] Create `generate-domains-spec.ts`
- [ ] Import domain schemas from `src/schemas/models/domain/`
- [ ] Map all 13 domain endpoints
- [ ] Add to master generation script

**Organizations API Generator (5 routes)**
- [ ] Create `generate-organizations-spec.ts`
- [ ] Import organization schemas
- [ ] Map all 5 organization endpoints
- [ ] Add to master generation script

**Teams API Generator (8 routes)**
- [ ] Create `generate-teams-spec.ts`
- [ ] Import team schemas
- [ ] Map all 8 team endpoints
- [ ] Add to master generation script

### Medium Priority: Schema Enhancement (Est: 1-2 days)

**Add .openapi() Metadata to Schemas**
- [ ] V3 request/response schemas (add descriptions, examples)
- [ ] V2 request/response schemas
- [ ] Domain model schemas
- [ ] Organization/Team schemas
- [ ] Enhance with:
  - Field descriptions
  - Example values
  - Validation rules documentation
  - Deprecation notices

**Refactor to Data-Driven Pattern**
- [ ] Convert V3 generator from if/else to RouteMapping pattern
- [ ] Apply same pattern to V2, Domains, Orgs, Teams generators
- [ ] Extract common route configurations
- [ ] Create reusable request/response builders

### Lower Priority: Validation & Testing (Est: 2-3 days)

**Validation Suite**
- [ ] Schema validation against OpenAPI 3.0.3 spec
- [ ] Request validation (ensure requests match schemas)
- [ ] Response validation (ensure responses match schemas)
- [ ] Add to CI/CD pipeline
- [ ] Create validation test suite

**Contract Testing**
- [ ] Set up Pact or similar framework
- [ ] Create consumer contracts
- [ ] Create provider contracts
- [ ] Add contract tests to CI

**Enhanced Testing**
- [ ] Unit tests for each generator
- [ ] Integration tests for spec generation
- [ ] E2E tests validating generated specs against live API

### Optional: Process & Polish (Est: 1-2 days)

**Pre-commit Hooks**
- [ ] Auto-generate specs on schema file changes
- [ ] Validate specs before allowing commit
- [ ] Add to developer setup documentation

**Public/Internal Split**
- [ ] Identify which endpoints are public vs internal
- [ ] Create separate spec generation for public API
- [ ] Create separate spec for internal/admin API
- [ ] Update documentation site

**Documentation & Process**
- [ ] Create API versioning strategy document
- [ ] Establish quarterly review schedule
- [ ] Create deprecation tracking system
- [ ] Document breaking change process

---

## 📊 Progress Metrics

| Metric | Current | Target | Progress |
|--------|---------|--------|----------|
| **APIs with Generators** | 2/6 | 6/6 | 33% |
| **Routes Documented** | 14/68 | 68/68 | 21% |
| **Account API Coverage** | 7/7 | 7/7 | ✅ 100% |
| **V3 API Coverage** | 9/18 | 18/18 | 50% |
| **V2 API Coverage** | 0/17 | 17/17 | 0% |
| **Domains API Coverage** | 0/13 | 13/13 | 0% |
| **Organizations API Coverage** | 0/5 | 5/5 | 0% |
| **Teams API Coverage** | 0/8 | 8/8 | 0% |
| **CI/CD Automation** | ✅ | ✅ | 100% |
| **Validation Suite** | Partial | Complete | 25% |

---

## 🎯 Next Sprint Goals

### Sprint 1 (This Week)
1. Complete V3 API remaining 9 routes
2. Create V2 API generator
3. Create Domains API generator

### Sprint 2 (Next Week)
4. Create Organizations API generator
5. Create Teams API generator
6. Add comprehensive .openapi() metadata to all schemas

### Sprint 3 (Following Week)
7. Implement validation suite
8. Set up contract testing
9. Refactor all generators to data-driven pattern

---

## 💡 Technical Decisions Made

### Architecture Choices
- **Library**: `@asteasolutions/zod-to-openapi` v8.1.0
  - Rationale: Complete document generation, mature, well-documented
  - No `z.lazy()` usage in codebase (verified)

- **Pattern**: Global Zod Extension
  - File: `src/schemas/openapi-setup.ts`
  - All schemas import `z` from this file
  - Enables `.openapi()` method on all schemas

- **Route Discovery**: Dynamic filesystem scanning
  - Scans `apps/api/*/routes` directories
  - Future-proof for new APIs
  - Fallback to known list if scan fails

### Code Patterns Established
- **Data-Driven Route Mapping**: `RouteMapping[]` configuration
- **Standardized Error Responses**: Reusable response templates
- **Type Inference**: Use `typeof schema._output` vs `z.infer`
- **Request Building**: Explicit if/else branches for type safety

---

## 🐛 Known Issues & Limitations

### Current Limitations
1. **V3 API**: Only 50% of routes mapped (9/18)
2. **OPTIONS Endpoints**: Not yet documented (CORS preflight)
3. **Metadata Sparse**: Most schemas lack `.openapi()` descriptions
4. **No Validation**: Generated specs not validated against live API
5. **Single Spec**: No public/internal separation yet

### Technical Debt
- V3 generator uses manual if/else (should migrate to RouteMapping pattern)
- Some response schemas use `any` type (should be more specific)
- No automated testing of generated specs

---

## 📚 Related Documentation

- **Implementation Guide**: `src/scripts/openapi/README.md`
- **Maintenance Procedures**: `src/scripts/openapi/README.md#maintenance-procedures`
- **CI/CD Workflow**: `.github/workflows/openapi-generation.yml`
- **Zod Setup**: `src/schemas/openapi-setup.ts` (inline documentation)

---

## 🔗 Dependencies

### External Libraries
- `@asteasolutions/zod-to-openapi@8.1.0`
- `@apidevtools/swagger-parser@10.1.0` (23 transitive deps)
- `zod@4.1.11`

### Internal Dependencies
- Zod schemas in `src/schemas/`
- Otto routes files in `apps/api/*/routes`
- TypeScript configuration
- CI/CD infrastructure

---

## 💬 Notes for Future Developers

### When Adding a New API Endpoint:
1. Add route to `apps/api/[api-name]/routes` file
2. Create Zod schemas in `src/schemas/api/[api-name]/`
3. Add route mapping to appropriate generator
4. Run `pnpm run openapi:generate`
5. Commit both schema and generated spec

### When Modifying Existing Schemas:
1. Update Zod schema file
2. Run `pnpm run openapi:generate`
3. Review diff in generated spec
4. Update tests if needed
5. Commit changes

### Best Practices:
- Always import `z` from `@/schemas/openapi-setup`
- Add `.openapi()` metadata for better documentation
- Use RouteMapping pattern for new generators
- Test locally before pushing to CI

---

## ✅ Acceptance Criteria

This epic is complete when:
- [ ] All 68 routes across 6 APIs are documented
- [ ] All generated specs pass OpenAPI 3.0.3 validation
- [ ] CI/CD automatically generates and validates specs
- [ ] Contract tests validate specs against live API
- [ ] Documentation site is live and auto-updates
- [ ] Maintenance procedures are documented
- [ ] Team is trained on workflow

---

**Created**: 2025-01-18
**Last Updated**: 2025-01-18
**Estimated Completion**: 2-3 weeks (with dedicated resources)
