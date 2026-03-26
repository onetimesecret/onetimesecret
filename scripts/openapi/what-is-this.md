
# OpenAPI specification for the Onetime Secret API

We're building an auto-generated OpenAPI 3.1 specification that documents the full HTTP API surface of Onetime
Secret — all 120 routes across 8 API namespaces (v1, v2, v3, account, colonel, domains, organizations, invite).
The spec is derived from two sources of truth already in the codebase: Ruby routes.txt files that define every
endpoint, and TypeScript Zod schemas that define request/response shapes. A convention-based pipeline connects
them — Ruby handler classes declare which schemas they use via SCHEMA constants, a TypeScript scanner extracts
those declarations, and a generator assembles the OpenAPI document. The goal is a machine-readable API contract
that can drive client SDK generation, documentation, contract testing, and anomaly detection across API versions.

It's a two-phase convention bridge — Ruby source declares intent (SCHEMA constants), TypeScript scanner reads it,
and the generator joins routes with schemas at build time. This is effectively a compile-time contract between
the Ruby backend and the TypeScript schema layer, with no runtime coupling. The gap report acts as a liveness
check on that contract.

#### > What is the reason for having "operationId" that the ruby module namespace didn't already do?

OpenAPI requires globally unique operationIds. The Ruby namespace gives you the handler identity — which code runs. The operationId gives you the API operation
identity — which endpoint is being called.

They diverge in three cases that are visible in this codebase:

1. Same handler, multiple paths (the alias problem we just solved)

GET /receipt/:key   V1::Controllers::Index#show_receipt
GET /private/:key   V1::Controllers::Index#show_receipt   deprecated=true

One Ruby handler, two distinct API operations. The namespace can't distinguish them — both are
V1::Controllers::Index#show_receipt. But a client SDK needs two methods: v1ShowReceipt() and
v1PrivateShowReceipt().

2. Same handler, different auth contexts (V3 guest routes)

POST /secret/conceal        V3::Logic::Secrets::ConcealSecret  auth=sessionauth
POST /guest/secret/conceal  V3::Logic::Secrets::ConcealSecret  auth=noauth

Same class, but these are semantically different operations (authenticated vs anonymous). The operationId
differentiates them in the spec.

3. Cross-version handler reuse

V2 and V3 share handler class names (e.g., both have ConcealSecret). The operationId prefixes with the API name
(v2_concealSecret vs v3_concealSecret) so they're unambiguous across the full spec.

Beyond disambiguation, operationId serves a different audience entirely. The Ruby namespace is for the server
(routing, code organization). The operationId is for consumers — SDK generators use it as method names,
documentation tools use it as anchor links, and contract testing tools use it to correlate requests to spec
entries. The OpenAPI spec is an external contract; it shouldn't leak internal class hierarchies.

#### > What does covered and uncovered mean?

- Covered = the Ruby class declares a SCHEMA/SCHEMAS constant AND each key resolves to a known Zod schema in its
respective registry: `response` keys against `responseSchemas`, `model` keys against `modelSchemas`, and `request`
keys against the generator's `REQUEST_SCHEMA_REGISTRY`. The OpenAPI generator can produce a typed JSON Schema for
this handler's response.
- Broken (a subset of declared) = the Ruby class declares the constant but the key doesn't resolve anywhere. This
is what we just fixed — 7 → 0.
- Uncovered handler = a route handler class that has no SCHEMA/SCHEMAS constant at all. The generator still emits
an OpenAPI path entry for it, but with a generic { type: 'object' } response body instead of a real schema. These
are the 46 remaining gaps.
- Uncovered model = a model file in lib/onetime/models/ with no SCHEMA constant. These aren't route handlers, so
they don't directly affect the API spec — but they're tracked because model schemas feed the JSON Schema
generation pipeline (modelSchemas in src/schemas/registry.ts).

Example: A coverage number of 64/110 (58%) means: of 110 route handlers the scanner sees, 64 have declared schema
constants that resolve to real Zod schemas. The other 46 produce spec entries with placeholder response shapes.



---

## Next steps for the convention-based OpenAPI generator

The scanner and generator pipeline is functional: Ruby SCHEMA constants are declared on 64 handler classes and 6
models, the TypeScript scanner extracts them, and the generator produces a valid OpenAPI 3.1 spec covering 58% of
the API routes (64 of 110 handler entries have schema-backed responses). The tooling has surfaced structural
anomalies in the public API surface: V1's path triplication, V2's inherited aliases, and the V2/V3 wire format
divergence.

### Completed:

1. ✓ Fix the 7 broken references

Registered 3 Incoming response schemas (validateRecipient, incomingConfig, incomingSecret) in responseSchemas —
the Zod schemas existed in src/schemas/api/incoming.ts but weren't wired into the central registry. Taught the
scanner to validate model-prefixed keys (models/secret, models/receipt, etc.) against modelSchemas
so Ruby model SCHEMA declarations resolve correctly. Broken references: 7 → 0.

2. ✓ Document and deprecate V1/V2 path aliases

Added deprecated=true annotation to 12 legacy alias routes in V1 and V2 routes.txt (/private/ and /metadata/
paths). The generator reads the param and emits deprecated: true on those OpenAPI operations. OperationIds include
the path prefix for deprecated routes (e.g. v1_private_showReceipt) to avoid collisions with canonical routes.
All paths remain in the spec — existing clients still find them, but the deprecation signal is clear.

3. ✓ Generate request schema scaffolds for all API namespaces

Built a scaffold generator (generate-request-scaffolds.ts) that reads routes.txt and produces versioned Zod
request schemas under src/schemas/api/{version}/requests/. Each file is pre-populated with known parameter names
from a Ruby source survey — one file per handler leaf, deduplicated across deprecated aliases, with barrel index
re-exports per directory.

  80 request schema files across 7 directories:
  - v1 (9 files, flat form params), v2 (13), v3 (18)
  - account (11), domains (14), organizations (12), invite (3)

  V1 uses flat params (secret="", ttl=""); V2/V3 nest under secret={...}. Each version gets its own directory
  because the request shapes diverge structurally, not just by field additions.

  The scaffolds are human-editable starting points — the Ruby raise_concerns methods are too varied for automated
  extraction. A reviewer removes the TODO comment to mark each schema as verified.

4. ✓ Route param → OpenAPI extension bridge (x-otto-route-*)

Non-reserved route.txt key=value params now automatically emit as x-otto-route-{key} vendor extensions on OpenAPI
operations. Reserved params consumed structurally by the generator (response, auth, csrf, deprecated) are excluded.
This is the convention for carrying route-level metadata into the spec without per-param wiring.

5. ✓ Colonel routes marked scope=internal

All 21 colonel routes annotated with scope=internal in routes.txt. The scaffold generator skips these routes
(no request schema files generated). The OpenAPI generator still emits colonel operations in the spec with
x-otto-route-scope: internal, so consumers can filter them programmatically. Colonel response schemas are
unaffected — they remain in the spec for documentation.

6. ✓ Fix V2/V3 request schema nesting and establish compose-not-redefine pattern

V2/V3 conceal and generate request schemas were flat, but the Ruby handlers nest params under a "secret" key
(BaseSecretAction: @payload = params['secret'] || {}). Fixed by composing from existing payload schemas:

  z.object({ secret: concealPayloadSchema })  // transport wrapper
  z.object({ secret: generatePayloadSchema })

This established the request schema layering pattern:
- payloads/ = flat domain validation schemas (used by Vue forms, stores, composables)
- requests/ = transport wrappers that compose payloads (used by OpenAPI pipeline)
- Endpoints with params['secret'] nesting: request wraps payload under secret key
- Endpoints with flat params (show, reveal, burn): request schema IS the payload (no wrapper)

V1 request schemas are frozen — flat inline definitions, not composed from payloads. V1 is deprecated; these
exist solely for contract testing (validating response stability between releases). Do not refactor.

7. ✓ Migrate v3/requests.ts → v3/requests/*.ts

The single-file v3/requests.ts predated the per-endpoint requests/ directory. Deleted the flat file, consumers
now import from the per-endpoint requests/ directory.

8. ✓ Split V2/V3 response schema layers

Created separate schema layers for V2 (runtime parsing) and V3 (JSON-native OpenAPI):
- v3/responses/*.ts — JSON-native schemas using plain z.string(), z.boolean(), z.number(). No transforms,
  no preprocess. These are the source of truth for OpenAPI spec generation.
- v2/responses/ — Runtime parsing schemas with z.preprocess(), transforms.fromString.*, coercion. These are
  used by Pinia stores and Vue components that need to handle Redis string-encoded values.
- api/base.ts — Shared envelope schemas (ApiRecordResponse, ApiRecordsResponse) hoisted out of v3 so both
  layers can compose from the same base.

The split resolves the V2 wire format question (old step 10): V3 schemas define the canonical JSON contract,
V2 schemas handle the string-encoded wire format at runtime. No annotation needed — the schema layer itself
encodes the difference.

Consumer imports (stores, composables) were redirected from v3/responses → v2/responses, since stores parse
runtime data. The v3 barrel now re-exports only what's needed for backward compatibility.

9. ✓ Register CustomDomain and Organization model schemas

Added SCHEMA constants to custom_domain.rb ('models/custom-domain') and organization.rb ('models/organization'),
following the established models/kebab-name convention. Registered both in the TS modelSchemas registry.
Renamed src/schemas/models/domain/ → models/custom-domain/ to align directory name with the Ruby model class
and registry key. Models: 4/8 → 6/8. Remaining uncovered: Features (embedded value object) and
OrganizationMembership (join model) — both always nested inside other responses.

10. ✓ Add the 3 uncovered Meta endpoints per version

system_status, system_version, get_supported_locales are class methods on a module, not instance-based logic
classes. The scanner's 1:1 class→SCHEMA mapping doesn't apply. Proposed convention: a method-keyed SCHEMAS
hash on the Meta module:

  SCHEMAS = {
    system_status:         { response: 'systemStatus' },
    system_version:        { response: 'systemVersion' },
    get_supported_locales: { response: 'supportedLocales' },
  }.freeze

Scanner changes needed: multiline SCHEMAS parsing (accumulate lines between { and }.freeze), emit entries with
dot notation (V3::Logic::Meta.system_status) matching how routes.txt references them. Simple response schemas
needed in responseSchemas for these trivial JSON shapes.

Request schema scaffolds already exist for these (empty z.object({}) — correct, since they accept no params).


### Remaining:


11. Wire request schemas into the OpenAPI generator

The 80 request schema scaffolds are standalone files. To connect them to the generated spec:
- Create a requestSchemaRegistry (parallel to responseSchemas) that maps handler names to Zod request schemas
- Teach the scanner to read request: keys from Ruby SCHEMA constants (currently only 4 handlers declare them)
- Have buildRequestBody in the generator resolve against the registry
- V1 routes emit application/x-www-form-urlencoded; V2+ emit application/json

Currently 4/~50 mutation endpoints have wired request schemas. The scaffolds provide the Zod definitions; this
step connects them to the pipeline.

Known scaffold issues to fix before wiring:
- domains update-domain-logo.ts and update-domain-icon.ts are multipart file uploads, not JSON bodies

12. Fill remaining response schema gaps

The 46 uncovered handlers break down as:
- 9 V1 controllers — frozen response shapes via receipt_hsh; TS-side hardcoded map is pragmatic
- 6 V2/V3 Meta methods — covered by step 10 above
- 8 Account mutations — generic success responses, low priority
- 8 Domain image/remove ops — could inherit from existing imageProps schema. Adding SCHEMA to GetDomainImage /
  UpdateDomainImage base classes would cover 8 routes at once
- 4 Organization invitations — need new schemas
- 3 Invite API — need new schemas
- 8 Colonel admin ops — scope=internal, low priority but response schemas still useful for admin tooling

Suggested order: Step 10 is mechanical (6 handlers, trivial response shapes). Step 11 is the main pipeline
advancement — connecting request schemas to the generator. Step 12 is ongoing gap closure.
