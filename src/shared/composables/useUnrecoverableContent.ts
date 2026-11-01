// src/shared/composables/useUnrecoverableContent.ts

import { markUnrecoverableContent } from '@/utils/unrecoverableContent';
import { onScopeDispose, watch, type WatchSource } from 'vue';

/**
 * Marks the page as showing unrecoverable content
 * (src/utils/unrecoverableContent.ts) while `showing` is true. The mark is
 * released when `showing` turns false or the calling component unmounts.
 *
 * The watcher is synchronous so the mark is in place the moment the value
 * reaches the store, before the render that puts it on screen.
 */
export function useUnrecoverableContent(showing: WatchSource<boolean>): void {
  let release: (() => void) | null = null;
  const stop = () => {
    release?.();
    release = null;
  };

  watch(
    showing,
    (on) => {
      if (on) {
        release ??= markUnrecoverableContent();
      } else {
        stop();
      }
    },
    { immediate: true, flush: 'sync' }
  );
  onScopeDispose(stop);
}
