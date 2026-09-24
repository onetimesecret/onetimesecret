// src/apps/admin/composables/useRefocusAfterBusy.ts

import { nextTick, watch, type Ref } from 'vue';

/**
 * Hand focus back to an input that a `busy` flag disabled.
 *
 * Every admin search input is disabled while its request is in flight so the
 * visible term cannot diverge from the results that land. Disabling a focused
 * element drops focus to `<body>`, and re-enabling it does NOT give focus
 * back, so without this the operator would need a click before every
 * refinement of a search they just submitted from the keyboard.
 *
 * Remembers whether the input had focus at the moment it went busy (the
 * watcher runs before the DOM applies `disabled`, so `activeElement` is still
 * the input) and restores it on the tick after busy clears (after the DOM has
 * removed `disabled`). Nothing happens when focus was elsewhere.
 */
export function useRefocusAfterBusy(input: Ref<HTMLInputElement | null>, busy: Ref<boolean>): void {
  let hadFocus = false;

  watch(busy, (isBusy) => {
    if (isBusy) {
      const el = input.value;
      hadFocus = el !== null && typeof document !== 'undefined' && document.activeElement === el;
      return;
    }
    if (!hadFocus) return;
    hadFocus = false;
    void nextTick(() => input.value?.focus());
  });
}
