# OpenAPI Generation

Generates an OpenAPI 3.1 spec from Otto `routes.txt` files and Zod v4 schemas. No third-party OpenAPI libraries required.

## Usage

```bash
pnpm run openapi:generate              # Generate spec to generated/openapi/openapi.json
pnpm run openapi:generate -- --dry-run  # Preview without writing
pnpm run openapi:generate -- --verbose  # Show per-route details (+ = has schema)
pnpm run schema:scan                    # Scan Ruby SCHEMA constants, print coverage gap report
```

## How it works

1. `otto-routes-parser.ts` auto-discovers and parses all `apps/api/{name}/routes.txt`
2. `schema-scanner.ts` scans Ruby logic classes and models for `SCHEMA` constants (configurable globs)
3. `generate-openapi.ts` joins routes with scanned schemas, derives operationId/summary/tags from handler class names
4. Matched schemas are converted via `z.toJSONSchema()` (Zod v4 native, JSON Schema 2020-12)
5. Output is a single OpenAPI 3.1 JSON file with a gap report on stderr

## Terminology: V2/V3 are API versions, not Zod versions

References to "V2" and "V3" throughout this codebase refer to the Onetime Secret
REST API versions (`/api/v2/*`, `/api/v3/*`), not Zod library versions. The project
uses Zod v4 (the npm `zod` package) for all schema definitions across both API versions.

## Schema data flow: Wire → Domain → Documentation

Each V3 schema serves three roles in a single definition:

```typescript
// Wire → Domain → Documentation
//
// 1. VALIDATE: Parse the JSON response from the API
secretResponseSchema.parse(json)       // input:  { created: 1641234567 }
//
// 2. TRANSFORM: Coerce wire values into domain types for Pinia/components
//    ↓ .transform(v => new Date(v * 1000))
//    result: { created: Date }          // output: consumed by stores & components
//
// 3. DOCUMENT: Generate JSON Schema for API consumers
//    z.toJSONSchema(schema, { io: "input" })
//    ↓ documents the input (wire) type, not the output (domain) type
//    result: { "type": "number" }       // OpenAPI spec reflects what the API sends
```

The `io: "input"` parameter is what makes this work. Without it, `z.toJSONSchema()`
defaults to the output type — and `Date` serializes as `{}` (unrepresentable in
JSON Schema). With `io: "input"`, it documents the wire format instead.

| Wire value (input)   | Domain value (output) | JSON Schema type |
|----------------------|----------------------|-----------------|
| `1641234567`         | `Date`               | `number`        |
| `"0"` / `"1"`       | `false` / `true`     | `string`        |
| `"1641234567"`       | `1641234567`         | `string`        |

This means you can safely add `.transform()` to any V3 schema field without breaking
the generated OpenAPI spec. V3 timestamp transforms live in `src/schemas/transforms.ts`
under `transforms.fromNumber.*` (as opposed to V2's `transforms.fromString.*` which
handle string-encoded Redis values).

## Files

- `generate-openapi.ts` — the generator script
- `schema-scanner.ts` — scans Ruby source for `SCHEMA` constants, produces coverage reports
- `otto-routes-parser.ts` — parses routes.txt into structured route metadata
- `route-config.ts` — shared helpers (standardErrorResponses, mergeResponses)
- `tests/test-parser.ts` — smoke tests for the routes parser
- `tests/test-scanner.ts` — smoke tests for the schema scanner

## Adding schema coverage

Add a `SCHEMA` constant to a Ruby logic class or model:

```ruby
# Logic class (request + response)
SCHEMAS = { response: 'concealData', request: 'concealSecret' }.freeze

# Logic class (response only)
SCHEMAS = { response: 'receipt' }.freeze

# Model class
SCHEMA = 'models/secret'.freeze
```

Each key type validates against its own registry: `response` keys against `responseSchemas` (`src/schemas/api/v3/responses.ts`), `request` keys against `REQUEST_SCHEMA_REGISTRY` (`src/scripts/openapi/generate-openapi.ts`), and `model` keys against `modelSchemas` (`src/schemas/registry.ts`). Run `pnpm run schema:scan` to verify coverage.
