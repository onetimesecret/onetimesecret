
OpenAPI specification for the Onetime Secret API

We're building an auto-generated OpenAPI 3.1 specification that documents the full HTTP API surface of Onetime
Secret — all 120 routes across 8 API namespaces (v1, v2, v3, account, colonel, domains, organizations, invite).
The spec is derived from two sources of truth already in the codebase: Ruby routes.txt files that define every
endpoint, and TypeScript Zod schemas that define request/response shapes. A convention-based pipeline connects
them — Ruby handler classes declare which schemas they use via SCHEMA constants, a TypeScript scanner extracts
those declarations, and a generator assembles the OpenAPI document. The goal is a machine-readable API contract
that can drive client SDK generation, documentation, contract testing, and anomaly detection across API versions.


> What is the reason for having "operationId" that the ruby module namespace didn't already do?

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

---

Next steps for the convention-based OpenAPI generator

The scanner and generator pipeline is functional: Ruby SCHEMA constants are declared on 62 handler classes and 4
models, the TypeScript scanner extracts them, and the generator produces a valid OpenAPI 3.1 spec covering 54% of
the 120 API routes (65 of 120 routes have schema-backed responses). The tooling has surfaced structural anomalies
in the public API surface: V1's path triplication, V2's inherited aliases, and the V2/V3 wire format divergence.

Completed:

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

Remaining:

3. Add the 3 uncovered Meta endpoints per version

system_status, system_version, get_supported_locales are class methods on a module, not logic classes. They need
either:
- A SCHEMA constant on the Meta module itself (minor convention extension)
- Simple response schemas added to responseSchemas (these return trivial JSON — status string, version string,
locale list)

4. Deduplicate V3 guest routes in the spec

The 8 guest routes use the same handlers and schemas as their authenticated counterparts. The generator could
either:
- Merge them into shared path entries with security: [sessionAuth, {}] (either auth or none)
- Keep them separate but link via x-related-operation or shared $ref schemas (current behavior, arguably more
accurate since the paths differ)

5. Register the V2 wire format difference

V2 and V3 share the same SCHEMA values but V2 returns string-encoded booleans/numbers while V3 returns native JSON
types. Options:
- Create separate v2/ response schemas that reflect the wire format (strings everywhere)
- Add an x-wire-format: string-encoded extension to V2 operations in the generated spec
- Document it and move on — V2 is stable and likely headed for deprecation

6. Fill remaining schema gaps incrementally

The 46 uncovered handlers break down as:
- 9 V1 controllers — skip unless V1 gets formal API documentation
- 6 V2/V3 Meta methods — covered by step 3 above
- 8 Account mutations — generic success responses, low priority
- 8 Colonel admin ops — internal tooling, low priority
- 8 Domain image/remove ops — could inherit from existing imageProps schema
- 4 Organization invitations — need new schemas
- 3 Invite API — need new schemas

The domain image handlers are the easiest gap to close — GetDomainLogo, GetDomainIcon, UpdateDomainLogo,
UpdateDomainIcon all use the imageProps response but the scanner missed them because they inherit via
GetDomainImage/UpdateDomainImage base classes. Adding SCHEMA to the base classes (or the subclasses) would cover 8
routes at once.

Suggested order

Step 3 is mechanical and could be done now. Step 4 is a design call. Step 5 is worth discussing before acting.
Step 6 is ongoing — each gap filled immediately increases coverage in the generated spec.
