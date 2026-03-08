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
SCHEMA = { response: 'concealData', request: 'api/v3/conceal-payload' }.freeze

# Logic class (response only)
SCHEMA = { response: 'receipt' }.freeze

# Model class
SCHEMA = 'models/secret'.freeze
```

Response values are keys in `responseSchemas` (`src/schemas/api/v3/responses.ts`). Request values are keys in `schemaRegistry` (`src/schemas/registry.ts`). Run `pnpm run schema:scan` to verify coverage.
