import {
  applyRequestCorrelation,
  parseRequestId,
  readDocumentRequestId,
  readResponseRequestId,
} from '@/plugins/core/diagnostics/requestCorrelation';
import type { ErrorEvent } from '@sentry/core';
import { AxiosHeaders } from 'axios';
import { afterEach, describe, expect, it } from 'vitest';

describe('request correlation identifiers', () => {
  afterEach(() => {
    document.querySelectorAll('meta[name="request-id"]').forEach((meta) => meta.remove());
  });

  it.each([
    '6bb16e69-9530-47e6-9b40-af292665771b',
    'c46b0584d349817239ae58279dc45fab',
    'Request_ABC:012.example-1',
    'a'.repeat(200),
  ])('preserves an opaque request ID %s', (value) => {
    expect(parseRequestId(value)).toBe(value);
  });

  it.each([
    null,
    undefined,
    123,
    ['request-1'],
    {},
    '',
    ' request-1',
    'request-1 ',
    'request-1\n',
    'request-1\r\n',
    'request\t1',
    'request\u00001',
    'request-1,request-2',
    '<request>',
    'a'.repeat(201),
  ])('rejects malformed request ID %j', (value) => {
    expect(parseRequestId(value)).toBeUndefined();
  });

  it('reads header names case-insensitively including AxiosHeaders', () => {
    expect(readResponseRequestId({ 'X-Request-ID': 'Request-ABC' })).toBe('Request-ABC');
    expect(readResponseRequestId(new AxiosHeaders({ 'X-Request-ID': 'Request-ABC' }))).toBe(
      'Request-ABC'
    );
  });

  it('rejects repeated, non-string or ambiguous header values', () => {
    expect(readResponseRequestId({ 'x-request-id': ['one', 'two'] })).toBeUndefined();
    expect(readResponseRequestId({ 'x-request-id': 123 })).toBeUndefined();
    expect(readResponseRequestId({ 'x-request-id': 'one', 'X-Request-ID': 'two' })).toBeUndefined();
  });

  it('reads the initial document ID from the server-rendered meta tag', () => {
    expect(readDocumentRequestId()).toBeUndefined();
    const meta = document.createElement('meta');
    meta.name = 'request-id';
    meta.content = 'document-ABC';
    document.head.append(meta);
    expect(readDocumentRequestId()).toBe('document-ABC');
    meta.content = 'invalid id';
    expect(readDocumentRequestId()).toBeUndefined();
  });

  it('keeps the document and failed API IDs distinct on an error', () => {
    const event: ErrorEvent = { type: undefined, tags: { document_request_id: 'document-ABC' } };
    applyRequestCorrelation(event, {
      originalException: {
        response: { headers: { 'x-request-id': 'api-XYZ' } },
      },
    });
    expect(event.tags).toEqual({ document_request_id: 'document-ABC', request_id: 'api-XYZ' });

    const unrelated: ErrorEvent = {
      type: undefined,
      tags: { document_request_id: 'document-ABC' },
    };
    applyRequestCorrelation(unrelated, { originalException: new Error('unrelated') });
    expect(unrelated.tags).toEqual({ document_request_id: 'document-ABC' });
  });

  it('does not use an error body or an invalid header as request correlation', () => {
    const event: ErrorEvent = { type: undefined };
    applyRequestCorrelation(event, {
      originalException: {
        response: { headers: { 'x-request-id': 'invalid id' }, data: { request_id: 'body-id' } },
      },
    });
    expect(event.tags).toBeUndefined();
  });
});
