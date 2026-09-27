// src/router/viewKey.ts

import type { RouteLocationNormalizedLoaded } from 'vue-router';

type ViewKeyRoute = Pick<
  RouteLocationNormalizedLoaded,
  'fullPath' | 'hash' | 'matched' | 'meta' | 'params' | 'query'
>;

/**
 * Key for the routed view in App.vue.
 *
 * By default the key is the route's fullPath, so every navigation mounts a
 * fresh component instance (App.vue avoids keep-alive for the same reason).
 * A route can name params in `meta.keepMountedAcrossParams`. Those params are
 * left out of the key, so a navigation that changes only them keeps the
 * mounted instance. That instance must then react to the change itself
 * (watch route.params). Route guards still run on such a navigation; only
 * the remount is skipped.
 */
export function routeViewKey(route: ViewKeyRoute): string {
  const kept = route.meta?.keepMountedAcrossParams;
  if (!kept?.length) return route.fullPath;

  const params = Object.fromEntries(
    Object.entries(route.params).filter(([name]) => !kept.includes(name))
  );
  return JSON.stringify([
    route.matched.map((record) => record.path),
    params,
    route.query,
    route.hash,
  ]);
}

/**
 * True when a navigation changes the URL but keeps the routed view mounted,
 * i.e. only params the route lists in `meta.keepMountedAcrossParams` changed.
 */
export function keepsRoutedView(to: ViewKeyRoute, from: ViewKeyRoute): boolean {
  return to.fullPath !== from.fullPath && routeViewKey(to) === routeViewKey(from);
}
