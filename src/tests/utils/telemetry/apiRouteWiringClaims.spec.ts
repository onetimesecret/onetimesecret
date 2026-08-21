// src/tests/utils/telemetry/apiRouteWiringClaims.spec.ts
//
// A DOC-DRIFT GUARD, not a behaviour test.
//
// The recurring defect in this effort is a comment that asserts a guarantee the
// code does not deliver. Three such comments described the API-route feature as
// unwired — "the feature is inert ... until someone wires it up", "THIS IS THE
// ONE-LINE WIRING POINT", "unknown is the common case until the axios
// interceptor is wired" — long after `requestInterceptor` began calling
// `setCurrentApiRoute` on every request. A reader trusting them would conclude
// `apiRoute` never leaves the browser, which is the opposite of the truth: it
// is a populated, INDEXED tag.
//
// This file pins the two halves together. If the wiring is ever removed, the
// first assertion fails and tells you the prose has to go back. If the prose
// creeps back while the wiring stands, the second fails.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

function source(relativePath: string): string {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8');
}

const INTERCEPTORS = 'src/plugins/axios/interceptors.ts';

/** Files whose comments describe the wiring state. */
const CLAIM_SITES = [
  'src/utils/telemetry/apiRouteContext.ts',
  'src/utils/schemaValidation.ts',
];

/**
 * Phrases that are only true while the interceptor does NOT stamp the slot.
 * Matched case-insensitively; each one shipped verbatim at some point.
 */
const UNWIRED_CLAIMS = [
  /the feature is inert/i,
  /until someone wires it up/i,
  /one-line wiring point/i,
  /until the axios interceptor is wired/i,
  /safe to land ahead of its wiring/i,
];

describe('api-route wiring claims match the code', () => {
  it('the axios request interceptor really does stamp the route slot', () => {
    // The single production caller. If this assertion ever fails, the feature
    // IS inert again and the prose in CLAIM_SITES must say so.
    expect(source(INTERCEPTORS)).toContain('setCurrentApiRoute(');
    expect(source(INTERCEPTORS)).toContain("from '@/utils/telemetry/apiRouteContext'");
  });

  it.each(CLAIM_SITES)('%s no longer describes the feature as unwired', (file) => {
    const text = source(file);
    const stale = UNWIRED_CLAIMS.filter((pattern) => pattern.test(text)).map(String);

    expect(stale).toEqual([]);
  });
});
