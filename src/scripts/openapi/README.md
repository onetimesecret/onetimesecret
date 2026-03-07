# OpenAPI Generation

Generates an OpenAPI 3.1 spec from Otto `routes.txt` files and Zod v4 schemas. No third-party OpenAPI libraries required.

## Usage

```bash
pnpm run openapi:generate              # Generate spec to generated/openapi/openapi.json
pnpm run openapi:generate -- --dry-run  # Preview without writing
pnpm run openapi:generate -- --verbose  # Show per-route details (+  = has schema)
```

## How it works

1. `otto-routes-parser.ts` auto-discovers and parses all `apps/api/{name}/routes.txt`
2. `generate-openapi.ts` derives operationId, summary, and tags from handler class names (convention)
3. Response/request schemas are resolved from an explicit mapping to the Zod schema registry
4. Matched schemas are converted via `z.toJSONSchema()` (Zod v4 native, JSON Schema 2020-12)
5. Output is a single OpenAPI 3.1 JSON file

## Files

- `generate-openapi.ts` — the generator script
- `otto-routes-parser.ts` — parses routes.txt into structured route metadata
- `route-config.ts` — shared helpers (standardErrorResponses, mergeResponses)
- `test-parser.ts` — smoke tests for the routes parser

## Adding schema coverage

Edit the `RESPONSE_SCHEMA_MAP` and `REQUEST_SCHEMA_MAP` in `generate-openapi.ts` to map handler class names to schema keys in `src/schemas/api/v3/responses.ts`.
