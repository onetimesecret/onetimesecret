
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

- Covered = the Ruby class declares a SCHEMA/SCHEMAS constant AND the key it points to resolves to an actual Zod
schema in one of the TS registries (responseSchemas or schemaRegistry). The OpenAPI generator can produce a typed
JSON Schema for this handler's response.
- Broken (a subset of declared) = the Ruby class declares the constant but the key doesn't resolve anywhere. This
is what we just fixed — 7 → 0.
- Uncovered handler = a route handler class that has no SCHEMA/SCHEMAS constant at all. The generator still emits
an OpenAPI path entry for it, but with a generic { type: 'object' } response body instead of a real schema. These
are the 46 remaining gaps.
- Uncovered model = a model file in lib/onetime/models/ with no SCHEMA constant. These aren't route handlers, so
they don't directly affect the API spec — but they're tracked because model schemas feed the JSON Schema
generation pipeline (schemaRegistry).

Example: So a coverage number (62/108 = 54%) means: of 108 route handlers the scanner sees, 62 have declared schema
constants that resolve to real Zod schemas. The other 46 produce spec entries with placeholder response shapes.



---

## Next steps for the convention-based OpenAPI generator

The scanner and generator pipeline is functional: Ruby SCHEMA constants are declared on 62 handler classes and 4
models, the TypeScript scanner extracts them, and the generator produces a valid OpenAPI 3.1 spec covering 54% of
the 120 API routes (65 of 120 routes have schema-backed responses). The tooling has surfaced structural anomalies
in the public API surface: V1's path triplication, V2's inherited aliases, and the V2/V3 wire format divergence.

### Completed:

1. ✓ Fix the 7 broken references

Registered 3 Incoming response schemas (validateRecipient, incomingConfig, incomingSecret) in responseSchemas —
the Zod schemas existed in src/schemas/api/incoming.ts but weren't wired into the central registry. Taught the
scanner and generator to also check schemaRegistry for model-prefixed keys (models/secret, models/receipt, etc.)
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

### Remaining:

6. Add the 3 uncovered Meta endpoints per version

system_status, system_version, get_supported_locales are class methods on a module, not logic classes. They need
either:
- A SCHEMA constant on the Meta module itself (minor convention extension)
- Simple response schemas added to responseSchemas (these return trivial JSON — status string, version string,
locale list)

Request schema scaffolds already exist for these (empty z.object({}) — correct, since they accept no params).

7. Wire request schemas into the OpenAPI generator

The 80 request schema scaffolds are standalone files. To connect them to the generated spec:
- Create a requestSchemaRegistry (parallel to responseSchemas) that maps handler names to Zod request schemas
- Teach the scanner to read request: keys from Ruby SCHEMA constants (currently only 4 handlers declare them)
- Have buildRequestBody in the generator resolve against the registry
- V1 routes emit application/x-www-form-urlencoded; V2+ emit application/json

Currently 4/~50 mutation endpoints have wired request schemas. The scaffolds provide the Zod definitions; this
step connects them to the pipeline.

Known scaffold issues to fix before wiring:
- V2/V3 conceal-secret.ts and generate-secret.ts define flat params, but V2/V3 nest under secret: {...}. The
  existing v3/requests.ts already shows the correct wrapper pattern (z.object({ secret: concealPayloadSchema }))
- domains update-domain-logo.ts and update-domain-icon.ts are multipart file uploads, not JSON bodies

8. Register the V2 wire format difference

V2 and V3 share the same SCHEMA values but V2 returns string-encoded booleans/numbers while V3 returns native JSON
types. Options:
- Create separate v2/ response schemas that reflect the wire format (strings everywhere)
- Add an x-otto-route-wire-format: string-encoded annotation to V2 routes.txt (flows through the extension bridge)
- Document it and move on — V2 is stable and likely headed for deprecation

9. Fill remaining response schema gaps incrementally

The 46 uncovered handlers break down as:
- 9 V1 controllers — V1 is the oldest external API; frozen response shapes via receipt_hsh make these easy to
  document accurately. Option B (TS-side hardcoded map, no Ruby SCHEMA convention) is pragmatic since the shapes
  won't evolve
- 6 V2/V3 Meta methods — covered by step 6 above
- 8 Account mutations — generic success responses, low priority
- 8 Domain image/remove ops — could inherit from existing imageProps schema. Adding SCHEMA to GetDomainImage /
  UpdateDomainImage base classes would cover 8 routes at once
- 4 Organization invitations — need new schemas
- 3 Invite API — need new schemas
- 8 Colonel admin ops — scope=internal, low priority but response schemas still useful for admin tooling

Suggested order

Step 6 is mechanical and could be done now. Step 7 is the main pipeline advancement — connecting request schemas
to the generator. Step 8 is worth discussing before acting (the x-otto-route extension bridge now makes the
annotation approach trivial). Step 9 is ongoing.
