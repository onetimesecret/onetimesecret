// src/tests/utils/navigation.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { hardNavigate } from '@/utils/navigation';

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

  it('falls back to the root when the FALLBACK itself is unsafe', () => {
    hardNavigate('https://evil.example', 'https://also-evil.example');
    expect(assign).toHaveBeenCalledWith('/');
  });
});
