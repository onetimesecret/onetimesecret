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

## Schema transforms and JSON Schema (`io: "input"`)

V3 schemas serve two purposes: runtime validation (Pinia stores call `.parse()`) and
OpenAPI documentation (this generator calls `z.toJSONSchema()`). Some fields use
`.transform()` to coerce wire values into application types — for example,
`z.number().transform(v => new Date(v * 1000))` converts Unix epoch seconds into
JavaScript `Date` objects for frontend consumption.

All `z.toJSONSchema()` calls pass `io: "input"` so that transforms document the
**wire format** (what the API actually sends), not the coerced output type. Without
this option, a `Date` output would serialize as `{}` (unrepresentable in JSON Schema).

| Wire value (input)   | Application value (output) | JSON Schema type |
|----------------------|---------------------------|-----------------|
| `1641234567`         | `Date`                    | `number`        |
| `"0"` / `"1"`       | `false` / `true`          | `string`        |
| `"1641234567"`       | `1641234567`              | `string`        |

This means you can safely add `.transform()` to any V3 schema field without breaking
the generated OpenAPI spec.

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
