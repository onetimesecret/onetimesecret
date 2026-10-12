// src/tests/utils/navigation.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { hardNavigate, routerOwnsPath } from '@/utils/navigation';
import * as redirectUtils from '@/utils/redirect';

// The customer route modules read bootstrapStore in their guards; give them a
// store before import (same posture as sso-only-reachability.spec.ts).
setActivePinia(createTestingPinia({ createSpy: vi.fn }));

const { createAppRouter } = await import('@/router');
const { createAdminRouter } = await import('@/apps/admin/router');

/**
 * hardNavigate is the only place in the SPA that hands a SERVER-SUPPLIED path
 * to window.location. Its whole job is that the value cannot be an
 * off-origin destination, so the rejection cases are the point of this file.
 */
describe('hardNavigate', () => {
  const assign = vi.fn();
  let original: Location;

  beforeEach(() => {
    original = window.location;
    assign.mockClear();
    Object.defineProperty(window, 'location', {
      configurable: true,
      writable: true,
      value: { ...original, assign },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    Object.defineProperty(window, 'location', {
      configurable: true,
      writable: true,
      value: original,
    });
  });

  it('navigates to a valid internal path', () => {
    hardNavigate('/colonel/customers/ur_bob', '/colonel');
    expect(assign).toHaveBeenCalledWith('/colonel/customers/ur_bob');
  });

  it('keeps query and hash', () => {
    hardNavigate('/dashboard?tab=secrets#top', '/');
    expect(assign).toHaveBeenCalledWith('/dashboard?tab=secrets#top');
  });

  it.each([
    ['absolute URL', 'https://evil.example/steal'],
    ['script URL', 'javascript:alert(1)'],
    ['data URL', 'data:text/html,<script>alert(1)</script>'],
    ['protocol-relative', '//evil.example'],
    ['backslash trick', '/\\evil.example'],
    ['traversal', '/a/../../etc/passwd'],
    ['empty', ''],
    ['null', null],
    ['undefined', undefined],
  ])('falls back instead of following a %s target', (_label, target) => {
    hardNavigate(target as string | null | undefined, '/colonel');
    expect(assign).toHaveBeenCalledWith('/colonel');
  });

  it('normalizes an internal path while preserving query and hash', () => {
    hardNavigate('/./dashboard?tab=secrets#top', '/');
    expect(assign).toHaveBeenCalledExactlyOnceWith('/dashboard?tab=secrets#top');
  });

  it('normalizes the selected fallback', () => {
    hardNavigate(null, '/./colonel?tab=customers#top');
    expect(assign).toHaveBeenCalledExactlyOnceWith('/colonel?tab=customers#top');
  });

  it.each(['/.//evil.example', '/%2e//evil.example'])(
    'falls back to the root when normalization produces a protocol-relative path: %s',
    (target) => {
      hardNavigate(target, '/colonel');
      expect(assign).toHaveBeenCalledExactlyOnceWith('/');
    }
  );

  it('falls back to the root when the selected fallback normalizes to a protocol-relative path', () => {
    hardNavigate(null, '/.//evil.example');
    expect(assign).toHaveBeenCalledExactlyOnceWith('/');
  });

  it.each(['https://evil.example/steal', '//evil.example', 'javascript:alert(1)'])(
    'rejects an unsafe destination at the sink even if the input validator accepts it: %s',
    (target) => {
      vi.spyOn(redirectUtils, 'isValidInternalPath').mockReturnValueOnce(true);
      hardNavigate(target, '/colonel');
      expect(assign).toHaveBeenCalledExactlyOnceWith('/');
    }
  );

  it('falls back to the root when URL construction throws', () => {
    vi.spyOn(globalThis, 'URL').mockImplementationOnce(function () {
      throw new TypeError('Invalid URL');
    });
    hardNavigate('/colonel', '/');
    expect(assign).toHaveBeenCalledExactlyOnceWith('/');
  });

  it('falls back to the root when the FALLBACK itself is unsafe', () => {
    hardNavigate('https://evil.example', 'https://also-evil.example');
    expect(assign).toHaveBeenCalledWith('/');
  });
});

/**
 * routerOwnsPath decides between router.push and a document load for an
 * arbitrary internal path. Checked against the REAL route tables of both
 * bundles: the bug it fixes was the customer router rendering its NotFound for
 * the post-sign-in ?redirect=/colonel, because /colonel lives only in the
 * admin bundle.
 */
describe('routerOwnsPath', () => {
  describe('customer router', () => {
    const router = createAppRouter();

    it.each(['/colonel', '/colonel/', '/colonel/customers/ur_bob', '/colonel?tab=x'])(
      'does not own the admin console path %s',
      (path) => {
        expect(routerOwnsPath(router, path)).toBe(false);
      }
    );

    it.each(['/', '/signin', '/dashboard', '/secret/abc?view=raw#content'])(
      'owns its own route %s',
      (path) => {
        expect(routerOwnsPath(router, path)).toBe(true);
      }
    );
  });

  describe('admin router', () => {
    const router = createAdminRouter();

    it.each(['/colonel', '/colonel/', '/colonel/customers'])('owns %s', (path) => {
      expect(routerOwnsPath(router, path)).toBe(true);
    });

    it.each(['/dashboard', '/signin'])('does not own the customer path %s', (path) => {
      expect(routerOwnsPath(router, path)).toBe(false);
    });
  });
});
