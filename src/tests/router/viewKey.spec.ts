// src/tests/router/viewKey.spec.ts
//
// App.vue keys the routed view by routeViewKey($route). The fullPath default
// remounts the page on every navigation; a route's meta.keepMountedAcrossParams
// narrows that so a tab switch (/org/:extid/:tab?) keeps the page mounted.

import organizationRoutes from '@/apps/workspace/routes/organizations';
import { keepsRoutedView, routeViewKey } from '@/router/viewKey';
import { describe, expect, it } from 'vitest';
import { createMemoryHistory, createRouter, type RouteRecordRaw } from 'vue-router';

const Page = { render: () => null };

const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    // The real org settings record, so its meta is what is under test.
    ...organizationRoutes.map((record) => ({ ...record, component: Page }) as RouteRecordRaw),
    { path: '/secret/:secretIdentifier', name: 'Secret', component: Page },
    { path: '/dashboard', name: 'Dashboard', component: Page },
  ],
});

const at = (path: string) => router.resolve(path);

describe('routeViewKey', () => {
  it('is the fullPath for a route that keeps no params', () => {
    expect(routeViewKey(at('/secret/abc'))).toBe('/secret/abc');
    expect(routeViewKey(at('/secret/abc?x=1#h'))).toBe('/secret/abc?x=1#h');
  });

  it('keeps the org settings view mounted across :tab only', () => {
    const bare = routeViewKey(at('/org/on1a'));
    expect(routeViewKey(at('/org/on1a/members'))).toBe(bare);
    expect(routeViewKey(at('/org/on1a/activity'))).toBe(bare);
    expect(routeViewKey(at('/org/on1a/settings'))).toBe(bare);
  });

  it('remounts the org settings view for another org, query or hash', () => {
    const key = routeViewKey(at('/org/on1a/members'));
    expect(routeViewKey(at('/org/on1b/members'))).not.toBe(key);
    expect(routeViewKey(at('/org/on1a/members?x=1'))).not.toBe(key);
    expect(routeViewKey(at('/org/on1a/members#h'))).not.toBe(key);
  });

  it('never collides with another route', () => {
    expect(routeViewKey(at('/org/on1a'))).not.toBe(routeViewKey(at('/dashboard')));
  });
});

describe('keepsRoutedView', () => {
  it('is true only when the URL changes and the view key does not', () => {
    expect(keepsRoutedView(at('/org/on1a/members'), at('/org/on1a/domains'))).toBe(true);
    expect(keepsRoutedView(at('/org/on1a/members'), at('/org/on1a/members'))).toBe(false);
    expect(keepsRoutedView(at('/org/on1b/members'), at('/org/on1a/members'))).toBe(false);
    expect(keepsRoutedView(at('/dashboard'), at('/org/on1a/members'))).toBe(false);
    expect(keepsRoutedView(at('/secret/b'), at('/secret/a'))).toBe(false);
  });
});
