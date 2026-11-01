import type { BreadcrumbHint, ErrorEvent, EventHint, Scope } from '@sentry/core';

// Diagnostic identifiers only: preserve case, reject controls, whitespace,
// header lists and coerced values. Supports proxy UUIDs and app-generated IDs.
const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;

export function parseRequestId(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  // JS's `$` can match before a final newline; require the whole value.
  return value.match(REQUEST_ID_PATTERN)?.[0] === value ? value : undefined;
}

/** Read only the response correlation header, never arbitrary response data. */
export function readResponseRequestId(headers: unknown): string | undefined {
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)) return undefined;

  const matches = Object.entries(headers).filter(([name]) => name.toLowerCase() === 'x-request-id');
  return matches.length === 1 ? parseRequestId(matches[0][1]) : undefined;
}

/** Read the SDK's existing HTTP breadcrumb hint without copying response data. */
export function readBreadcrumbRequestId(
  category: string | undefined,
  hint?: BreadcrumbHint
): string | undefined {
  try {
    if (category === 'xhr') {
      const xhr = hint?.xhr as Pick<XMLHttpRequest, 'getResponseHeader'> | undefined;
      return parseRequestId(xhr?.getResponseHeader('X-Request-ID'));
    }
    if (category === 'fetch') {
      const response = hint?.response as Pick<Response, 'headers'> | undefined;
      return parseRequestId(response?.headers.get('X-Request-ID'));
    }
  } catch {
    // Aborted requests or browser restrictions can make response headers unavailable.
  }
  return undefined;
}

/** The initial HTML request stays distinct from later, concurrent API calls. */
export function readDocumentRequestId(): string | undefined {
  if (typeof document === 'undefined') return undefined;
  return parseRequestId(document.querySelector('meta[name="request-id"]')?.getAttribute('content'));
}

/** Initialize both manual and integration capture scopes from this document. */
export function applyDocumentRequestId(scopes: Array<Pick<Scope, 'setTag'>>): void {
  const requestId = readDocumentRequestId();
  if (requestId) scopes.forEach((scope) => scope.setTag('document_request_id', requestId));
}

/** Attach the response ID to this error only; never mutate the shared scope. */
export function applyRequestCorrelation(event: ErrorEvent, hint?: EventHint): ErrorEvent {
  const original = hint?.originalException;
  if (!original || typeof original !== 'object') return event;

  const error = original as { response?: { headers?: unknown } };
  const requestId = readResponseRequestId(error.response?.headers);
  if (requestId) event.tags = { ...event.tags, request_id: requestId };
  return event;
}
