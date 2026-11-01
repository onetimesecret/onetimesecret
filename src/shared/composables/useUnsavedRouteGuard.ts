// src/shared/composables/useUnsavedRouteGuard.ts

import { routeViewKey } from '@/router/viewKey';
import { toValue, type MaybeRefOrGetter } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router';

/**
 * Asks the user to confirm before an in-app (Vue Router) navigation discards
 * edits the view has not saved.
 *
 * Leaving the route is not the only way to lose them. A navigation that stays
 * on the same route and changes only its params (the header's domain switcher
 * replacing :extid, for one) never fires onBeforeRouteLeave, yet App.vue keys
 * the routed view with routeViewKey, the fullPath by default, so it mounts a
 * fresh instance and the edits are gone. The update guard asks for those
 * navigations, and only for those that change the key: a param the route
 * lists in meta.keepMountedAcrossParams keeps the instance, and its edits.
 *
 * Document unloads (reload, tab close, hard links) never reach Vue Router;
 * useUnsavedInputGuard covers those.
 *
 * @param hasUnsavedChanges - true while the view holds unsaved edits
 * @param messageKey - i18n key of the confirmation text
 */
export function useUnsavedRouteGuard(
  hasUnsavedChanges: MaybeRefOrGetter<boolean>,
  messageKey = 'web.branding.you_have_unsaved_changes_are_you_sure'
): void {
  const { t } = useI18n();

  // true lets the navigation proceed, false cancels it.
  const confirmDiscard = (): boolean =>
    !toValue(hasUnsavedChanges) || window.confirm(t(messageKey));

  onBeforeRouteLeave(() => confirmDiscard());

  onBeforeRouteUpdate((to, from) => routeViewKey(to) === routeViewKey(from) || confirmDiscard());
}
