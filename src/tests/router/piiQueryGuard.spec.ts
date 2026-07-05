// src/tests/router/piiQueryGuard.spec.ts

/**
 * Tests for the dev-only "no PII in query" navigation guard. The guard only
 * warns (never blocks) and skips grandfathered legacy prefill routes. The
 * production runtime protection is the diagnostics scrubber, tested separately.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { RouteLocationNormalized, Router } from 'vue-router';
import { installPiiQueryDevWarning } from '@/router/piiQueryGuard';

type Guard = (to: RouteLocationNormalized) => unknown;

function makeRouter(): { router: Router; getGuard: () => Guard } {
  const beforeEach = vi.fn();
  const router = { beforeEach } as unknown as Router;
  return {
    router,
    getGuard: () => beforeEach.mock.calls[0][0] as Guard,
  };
}

function route(partial: Partial<RouteLocationNormalized>): RouteLocationNormalized {
  return {
    path: '/x',
    fullPath: '/x',
    query: {},
    params: {},
    hash: '',
    name: undefined,
    matched: [],
    meta: {},
    redirectedFrom: undefined,
    ...partial,
  } as unknown as RouteLocationNormalized;
}

describe('installPiiQueryDevWarning', () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  it('registers exactly one beforeEach guard', () => {
    const { router } = makeRouter();
    installPiiQueryDevWarning(router);
    expect(router.beforeEach).toHaveBeenCalledTimes(1);
  });

  it('warns when a PII key rides in the query, naming the key and path', () => {
    const { router, getGuard } = makeRouter();
    installPiiQueryDevWarning(router);

    const result = getGuard()(
      route({ path: '/check-email', fullPath: '/check-email?email=x@y.com', query: { email: 'x@y.com' } })
    );

    expect(warnSpy).toHaveBeenCalledTimes(1);
    const msg = String(warnSpy.mock.calls[0][0]);
    expect(msg).toContain('email');
    expect(msg).toContain('/check-email?email=x@y.com');
    // Never blocks navigation.
    expect(result).toBe(true);
  });

  it('does not warn for non-PII query params', () => {
    const { router, getGuard } = makeRouter();
    installPiiQueryDevWarning(router);

    const result = getGuard()(
      route({ path: '/pricing', fullPath: '/pricing?product=identity', query: { product: 'identity' } })
    );

    expect(warnSpy).not.toHaveBeenCalled();
    expect(result).toBe(true);
  });

  it('skips grandfathered legacy prefill routes (/signin, /signup)', () => {
    const { router, getGuard } = makeRouter();
    installPiiQueryDevWarning(router);

    getGuard()(route({ path: '/signin', query: { email: 'x@y.com' } }));
    getGuard()(route({ path: '/signup', query: { email: 'x@y.com' } }));

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('lists every leaked PII key when several are present', () => {
    const { router, getGuard } = makeRouter();
    installPiiQueryDevWarning(router);

    getGuard()(route({ path: '/x', query: { token: 'a', code: 'b' } }));

    const msg = String(warnSpy.mock.calls[0][0]);
    expect(msg).toContain('token');
    expect(msg).toContain('code');
  });
});
