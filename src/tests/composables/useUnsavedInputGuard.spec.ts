// src/tests/composables/useUnsavedInputGuard.spec.ts
//
// ADR-046 "Forced page load": conditional registration and removal of the
// shared beforeunload guard (#4465).

import { useUnsavedInputGuard } from '@/shared/composables/useUnsavedInputGuard';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { effectScope, ref } from 'vue';

describe('useUnsavedInputGuard', () => {
  let add: ReturnType<typeof vi.spyOn>;
  let remove: ReturnType<typeof vi.spyOn>;

  const isBeforeUnload = (call: unknown[]) => call[0] === 'beforeunload';
  const registered = () =>
    add.mock.calls.filter(isBeforeUnload).length - remove.mock.calls.filter(isBeforeUnload).length;

  /** Dispatches a real, cancelable beforeunload and reports what the page did. */
  function unload() {
    const event = new Event('beforeunload', { cancelable: true }) as BeforeUnloadEvent;
    window.dispatchEvent(event);
    return { prompted: event.defaultPrevented };
  }

  beforeEach(() => {
    add = vi.spyOn(window, 'addEventListener');
    remove = vi.spyOn(window, 'removeEventListener');
  });

  afterEach(() => vi.restoreAllMocks());

  it('registers nothing while there is no unsubmitted input', () => {
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(ref(false)));

    expect(registered()).toBe(0);
    expect(unload().prompted).toBe(false);
    scope.stop();
  });

  it('is present only while unsubmitted input exists: 0 -> 1 -> 0', () => {
    const dirty = ref(false);
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(dirty));

    dirty.value = true;
    expect(registered()).toBe(1);
    expect(unload().prompted).toBe(true);

    // Submitted or cleared: removed synchronously, before any navigation.
    dirty.value = false;
    expect(registered()).toBe(0);
    expect(unload().prompted).toBe(false);
    scope.stop();
  });

  it('registers once, however many times the input changes while dirty', () => {
    const text = ref('');
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(() => text.value.trim().length > 0));

    text.value = 'a';
    text.value = 'ab';
    text.value = 'abc';

    expect(registered()).toBe(1);
    scope.stop();
  });

  it('registers immediately when the view starts with unsubmitted input', () => {
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(ref(true)));

    expect(registered()).toBe(1);
    scope.stop();
  });

  it('is removed when the owning component goes away', () => {
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(ref(true)));

    scope.stop();

    expect(registered()).toBe(0);
    expect(unload().prompted).toBe(false);
  });

  it('cancels the event and sets returnValue for older browsers', () => {
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(ref(true)));
    const handler = add.mock.calls.find(isBeforeUnload)?.[1] as (
      event: BeforeUnloadEvent
    ) => void;
    // jsdom has no BeforeUnloadEvent, and Event#returnValue is the legacy
    // boolean, so hand the handler the two members it must touch.
    const event = { preventDefault: vi.fn(), returnValue: 'unset' };

    handler(event as unknown as BeforeUnloadEvent);

    expect(event.preventDefault).toHaveBeenCalledTimes(1);
    expect(event.returnValue).toBe('');
    scope.stop();
  });

  it('writes nothing to browser storage', () => {
    const local = vi.spyOn(Storage.prototype, 'setItem');
    const dirty = ref(false);
    const scope = effectScope();
    scope.run(() => useUnsavedInputGuard(dirty));

    dirty.value = true;
    unload();
    dirty.value = false;

    expect(local).not.toHaveBeenCalled();
    scope.stop();
  });
});
