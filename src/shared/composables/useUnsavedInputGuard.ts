// src/shared/composables/useUnsavedInputGuard.ts

import { onScopeDispose, toValue, watch, type MaybeRefOrGetter } from 'vue';

/**
 * Asks the browser to confirm before the page is unloaded while the view holds
 * input the user has not submitted (ADR-046 "Forced page load", #4465).
 *
 * It covers every document unload, not only the forced page load the refresh
 * coordinator can trigger: user reloads, tab close, and hard navigations such
 * as the masthead logo. In-app (Vue Router) navigation never unloads the
 * document; guard that separately with `onBeforeRouteLeave` where it matters.
 *
 * The listener is registered ONLY while unsubmitted input exists and removed
 * as soon as it is submitted or cleared. A standing `beforeunload` listener
 * makes the page ineligible for the back/forward cache in Firefox (MDN,
 * web.dev "Back/forward cache", Chrome "Deprecating the unload event"), so a
 * handler that is always installed and returns early is not equivalent.
 *
 * What the platform does with it (HTML Standard, "prompt to unload"):
 * - the browser shows its own generic dialog, and only when the document has
 *   sticky activation, i.e. the user has interacted with the page. A tab the
 *   user never touched unloads silently, and has no typed input to lose;
 * - the dialog text cannot be customized;
 * - it is unreliable on mobile platforms and is not a persistence mechanism.
 *
 * Secret drafts are deliberately NOT written to browser storage to make up
 * for that: doing so would persist unsubmitted secrets.
 *
 * @param hasUnsavedInput - true while the view holds unsubmitted input
 */
export function useUnsavedInputGuard(hasUnsavedInput: MaybeRefOrGetter<boolean>): void {
  let registered = false;

  const handleBeforeUnload = (event: BeforeUnloadEvent) => {
    event.preventDefault();
    // Legacy browsers require returnValue to be set to show the prompt.
    event.returnValue = '';
  };

  const sync = (shouldGuard: boolean) => {
    if (shouldGuard === registered) return;
    if (shouldGuard) window.addEventListener('beforeunload', handleBeforeUnload);
    else window.removeEventListener('beforeunload', handleBeforeUnload);
    registered = shouldGuard;
  };

  // flush: 'sync' so the listener is gone the moment input is submitted or
  // cleared, not a tick later: a submit handler may navigate immediately.
  watch(() => toValue(hasUnsavedInput), sync, { immediate: true, flush: 'sync' });

  onScopeDispose(() => sync(false));
}
