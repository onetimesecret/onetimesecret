# Error Handling

This page describes the frontend error-handling paths that are implemented in
this repository. It is not a general Result-pattern guide.

## Error paths at a glance

1. `createApi()` creates the Axios client and installs request, response, and
   error interceptors.
2. Axios rejects failed HTTP requests. The error interceptor preserves CSRF-token
   updates and records a scrubbed diagnostic breadcrumb; it does not convert an
   error into a Result value.
3. Components and composables that need loading state and user feedback use
   `useAsyncHandler().wrap()`.
4. Stores validate response bodies with their Zod schemas. A contract mismatch
   either throws a user-safe error or degrades to an explicitly empty state,
   according to that operation's contract.
5. `RouteErrorBoundary` handles synchronous route setup/render failures with a
   visible recovery panel. The global Vue handler logs and reports errors that
   reach it.

Relevant implementation paths:

- Axios client: `src/api/index.ts`
- Axios interceptors: `src/plugins/axios/interceptors.ts`
- Async wrapper and error classification: `src/shared/composables/useAsyncHandler.ts`
- Route render boundary: `src/shared/components/errors/RouteErrorBoundary.vue`
- Global Vue handler: `src/plugins/core/globalErrorBoundary.ts`

## API and asynchronous operations

Use the injected project client through `useApi()`. Do not create an unrelated
`fetch` client for ordinary application requests: it would bypass the configured
CSRF, locale, organization-context, and diagnostic behavior.

`useAsyncHandler().wrap()` catches, classifies, reports, and returns `undefined`
on failure. Callers must handle that return value before using the result.

```ts
import { useApi } from '@/shared/composables/useApi';
import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';

const $api = useApi();
const { wrap } = useAsyncHandler({
  setLoading: (loading) => {
    isLoading.value = loading;
  },
  onError: (error) => {
    formError.value = error.message;
  },
});

const data = await wrap(async () => {
  const response = await $api.get('/api/v3/secret/example');
  return response.data;
});

if (!data) return;
```

Use `notify: false` when the caller renders an inline error, as the authentication
forms do. Otherwise, supply a notification callback when a transient error should
be announced outside the form.

## Response contracts

TypeScript annotations do not validate a server response. Validate response
bodies at the API boundary with the endpoint's Zod schema.

The expected behavior differs by operation:

- Secret fetch/reveal operations use `gracefulParse()` and throw a safe error if
  the response does not satisfy the required contract.
- Admin resource fetchers use `gracefulParse()`, record `validationError`, and
  return `null` so views can render an explicit degraded state.
- A response field that controls behavior, such as an idempotency status, may
  require strict parsing even when the rest of an acknowledgement is advisory.

Follow the existing store or shared fetch-composable contract for the endpoint;
do not introduce an unshared `{ status: 'success' | 'error' }` Result convention.

## Render and programming errors

`RouteErrorBoundary` wraps the active route in `App.vue`. It uses
`onErrorCaptured` to show a recovery panel, reports the error once, and returns
`false` only after it has supplied that fallback. Its recovery actions reload the
page or navigate home; changing a local error ref alone does not reliably rebuild
the failed route subtree.

The global `app.config.errorHandler` is installed after Pinia. It classifies and
logs errors, and sends technical errors to diagnostics when configured. It only
notifies users when the plugin receives a `notify` callback; the normal app
initializer does not currently supply one. Do not treat it as a visible UI
fallback.

Unexpected programming errors should throw and reach one of these boundaries.
Expected HTTP and validation outcomes should instead use the async and
response-contract paths above.

## Adding a new error path

1. Use `useApi()` for application HTTP requests.
2. Define or reuse the endpoint's request and response schemas.
3. Choose the existing failure contract: throw a safe error, or return a typed
   degraded result with visible state.
4. Wrap user-triggered asynchronous work with `useAsyncHandler()` when it needs
   common loading, classification, reporting, or notification behavior.
5. Test both the HTTP-failure and malformed-success-response paths.
