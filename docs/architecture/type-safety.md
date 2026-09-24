# Type Safety

This page describes the implemented type-safety boundary for the Vue frontend.
It is not a proposal to trust API responses or to replace runtime schemas with
interfaces.

## Current contract

The frontend combines compile-time TypeScript types with runtime Zod validation:

- API response schemas define the standard `{ record, details }` response shape.
- `z.infer` derives TypeScript types from those schemas.
- Stores and shared fetch composables validate server responses before relying on
  typed fields.
- Request schemas validate user-controlled payloads at the appropriate form or
  store boundary.

The server's Ruby serializers remain hand-written. The repository generates JSON
schema documentation and frontend JSON-schema artifacts, but it does not generate
Ruby serializers from a shared JSON Schema definition.

Relevant implementation paths:

- Response-schema factories: `src/schemas/api/base.ts`
- Schema validation helper: `src/utils/schemaValidation.ts`
- Secret response handling: `src/shared/stores/secretStore.ts`
- Shared admin fetch contracts: `src/apps/admin/composables/usePaginatedFetch.ts`
  and `src/apps/admin/composables/useResourceFetch.ts`

## Validate server responses

A successful HTTP status does not prove that a response has the shape the UI
requires. Validate it before accessing nested fields.

```ts
const response = await $api.get(`/api/v3/secret/${secretIdentifier}`);
const result = gracefulParse(responseSchemas.secret, response.data, 'SecretResponse');

if (!result.ok) {
  throw new Error('Unable to load secret. Please try again.');
}

record.value = result.data.record;
details.value = result.data.details ?? null;
```

This pattern catches backend regressions, proxy responses, and serializer drift at
the boundary instead of allowing an asserted TypeScript type to fail later in a
component.

## Choose failure semantics deliberately

Schema validation is required, but each operation selects its own user-facing
failure behavior:

- **Required data:** Throw a safe, actionable error after validation fails. Secret
  fetch and reveal follow this pattern.
- **Optional/admin data:** Set explicit validation state and return `null` so the
  view can degrade safely. The shared admin fetch composables follow this pattern.
- **Behavior-controlling acknowledgements:** Strictly validate the fields that
  alter the result, such as an idempotency status; a 2xx response alone is not
  enough.

Do not silently cast `response.data as SomeType` for a new endpoint.

## Requests and internal state

Validate user input before submission, then preserve the validated shape through
the request path. Inside a layer, use TypeScript interfaces or inferred types for
ordinary state, but do not use those types as a substitute for validating data
that crossed a process boundary.

Avoid unnecessary duplicate request transformations when an existing schema and
store contract already own the conversion. Response validation remains required
at the store/composable boundary.

## Future unification is a proposal

A single source format that generated Ruby serializers, Zod schemas, and
TypeScript types would be a future architecture project. It is not current
repository behavior. Any proposal should first define compatibility, serializer
ownership, and migration rules, then replace duplicated contracts incrementally
without removing runtime response validation.

## Adding or changing an API contract

1. Define or update the Zod request/response schema.
2. Derive the TypeScript type from the schema where practical.
3. Parse the server response in the store or shared fetch composable.
4. Specify whether a schema mismatch throws or degrades, and make the view render
   that outcome.
5. Add coverage for valid responses, HTTP failure, and malformed successful
   responses.
