// src/tests/api/createApi.spec.ts
//
// The shared API client's timeout/cancellation contract.
//
// This looks like a test for a config flag, and it is — but the flag is
// load-bearing for observability, not ergonomics. Axios rejects BOTH
// `xhr.ontimeout` and `xhr.onabort` with code ECONNABORTED by default, and
// the diagnostics noise filter DROPS cancellations while REPORTING timeouts
// (src/plugins/core/diagnostics/expectedOutcomes.ts). Without
// `clarifyTimeoutError`, those two are the same value on the wire and every
// timed-out request during an API slowdown would be silently discarded as
// "the user navigated away". Removing this flag re-blinds Sentry to a class
// of outage while every other test still passes — hence this one.

import { describe, expect, it } from 'vitest';

import { createApi } from '@/api';

describe('createApi — timeout/cancellation contract', () => {
  it('clarifies timeout errors so they are distinguishable from cancellations', () => {
    expect(createApi().defaults.transitional?.clarifyTimeoutError).toBe(true);
  });

  it('keeps the flag set when a custom domain is configured', () => {
    // Custom-domain deployments build their own client; the contract must not
    // depend on which constructor path a deployment takes.
    expect(
      createApi({ domain: 'secrets.example.com' }).defaults.transitional?.clarifyTimeoutError
    ).toBe(true);
  });

  it('sets no request timeout, so ECONNABORTED can only mean an abort today', () => {
    // Documents the current state rather than freezing it: the flag above is
    // what keeps adding a timeout later a safe change. If this assertion is
    // updated to a real timeout, the flag is what stops Sentry going quiet.
    expect(createApi().defaults.timeout).toBeFalsy();
  });
});
