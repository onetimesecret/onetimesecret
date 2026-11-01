// src/tests/composables/useUnrecoverableContent.spec.ts

import { useUnrecoverableContent } from '@/shared/composables/useUnrecoverableContent';
import { hasUnrecoverableContent } from '@/utils/unrecoverableContent';
import { effectScope, ref } from 'vue';
import { afterEach, describe, expect, it } from 'vitest';

describe('useUnrecoverableContent', () => {
  const scopes: ReturnType<typeof effectScope>[] = [];

  afterEach(() => {
    for (const scope of scopes.splice(0)) scope.stop();
    expect(hasUnrecoverableContent()).toBe(false);
  });

  function inScope(fn: () => void) {
    const scope = effectScope();
    scopes.push(scope);
    scope.run(fn);
    return scope;
  }

  it('marks the page the moment the source turns true, before any render flush', () => {
    const showing = ref(false);
    inScope(() => useUnrecoverableContent(showing));
    expect(hasUnrecoverableContent()).toBe(false);

    showing.value = true;
    expect(hasUnrecoverableContent()).toBe(true);

    showing.value = false;
    expect(hasUnrecoverableContent()).toBe(false);
  });

  it('marks immediately when the source is already true', () => {
    inScope(() => useUnrecoverableContent(() => true));
    expect(hasUnrecoverableContent()).toBe(true);
  });

  it('releases the mark when the owning scope stops (the component unmounts)', () => {
    const showing = ref(true);
    const scope = inScope(() => useUnrecoverableContent(showing));
    expect(hasUnrecoverableContent()).toBe(true);

    scope.stop();
    expect(hasUnrecoverableContent()).toBe(false);
  });
});
