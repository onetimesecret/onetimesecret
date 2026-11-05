// src/tests/utils/unrecoverableContent.spec.ts

import { hasUnrecoverableContent, markUnrecoverableContent } from '@/utils/unrecoverableContent';
import { describe, expect, it } from 'vitest';

describe('unrecoverableContent', () => {
  it('is inactive until something is marked, and again once every mark is released', () => {
    expect(hasUnrecoverableContent()).toBe(false);

    const releaseFirst = markUnrecoverableContent();
    const releaseSecond = markUnrecoverableContent();
    expect(hasUnrecoverableContent()).toBe(true);

    releaseFirst();
    expect(hasUnrecoverableContent()).toBe(true);

    releaseSecond();
    expect(hasUnrecoverableContent()).toBe(false);
  });

  it('ignores a second release of the same mark', () => {
    const releaseA = markUnrecoverableContent();
    const releaseB = markUnrecoverableContent();

    releaseA();
    releaseA();
    expect(hasUnrecoverableContent()).toBe(true);

    releaseB();
    expect(hasUnrecoverableContent()).toBe(false);
  });
});
