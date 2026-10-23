// src/tests/plugins/core/startApp.spec.ts
//
// startApp (src/plugins/core/startApp.ts), shared by src/main.ts and
// src/admin.ts: install → await the initial navigation (which activates the
// visitor's locale) → mount → console warning → html[data-app-ready]. A
// failed start flags the server-rendered shell (html[data-app-failed]) and
// leaves it in place, unless a guard hands off to a page load.

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createMemoryHistory, createRouter, type Router } from 'vue-router';

const h = vi.hoisted(() => ({
  order: [] as string[],
  installError: null as Error | null,
}));

vi.mock('@/plugins/core/appInitializer', () => ({
  AppInitializer: {
    install(_app: unknown, options: { router: Router }) {
      h.order.push('install');
      if (h.installError) throw h.installError;
      // Installing the real router starts the initial navigation; do only that.
      options.router.push('/').catch(() => undefined);
    },
  },
  showConsoleWarning: () => {
    const mounted = document.getElementById('app')?.textContent === 'ROOT';
    const ready = document.documentElement.dataset.appReady ?? 'unset';
    h.order.push(`banner (mounted: ${mounted}, ready: ${ready})`);
  },
}));

import { startApp } from '@/plugins/core/startApp';

const Root = {
  render() {
    h.order.push('render');
    return 'ROOT';
  },
};

const html = document.documentElement;
const appText = () => document.getElementById('app')?.textContent;

/** A router whose one guard waits a turn (a locale loading), then returns `decide()`. */
function routerWith(decide: () => unknown): Router {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { render: () => null } }],
  });
  router.beforeEach(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
    h.order.push('guard');
    return decide() as boolean;
  });
  // vue-router prints a failed navigation's error when nothing listens.
  router.onError(() => undefined);
  return router;
}

beforeEach(() => {
  h.order = [];
  h.installError = null;
  document.body.innerHTML = '<div id="app">SHELL</div>';
  delete html.dataset.appReady;
  delete html.dataset.appFailed;
});

describe('startApp', () => {
  it('mounts only after the initial navigation, then warns, then flags ready', async () => {
    const started = startApp({ root: Root, createRouter: () => routerWith(() => true) });
    // Still navigating: the shell is up and nothing is flagged.
    expect(appText()).toBe('SHELL');
    expect(html.dataset.appReady).toBeUndefined();
    await started;

    expect(h.order).toEqual(['install', 'guard', 'render', 'banner (mounted: true, ready: unset)']);
    expect(appText()).toBe('ROOT');
    expect(html.dataset.appReady).toBe('true');
    expect(html.dataset.appFailed).toBeUndefined();
  });

  it('flags the shell and rethrows when the initial navigation fails', async () => {
    const failure = new Error('messages for bg did not load');
    const router = routerWith(() => {
      throw failure;
    });

    await expect(startApp({ root: Root, createRouter: () => router })).rejects.toBe(failure);

    expect(html.dataset.appFailed).toBe('true');
    expect(html.dataset.appReady).toBeUndefined();
    expect(appText()).toBe('SHELL');
    expect(h.order).toEqual(['install', 'guard']);
  });

  it('flags the shell when the router factory throws', async () => {
    await expect(
      startApp({
        root: Root,
        createRouter: () => {
          throw new Error('bad routes');
        },
      })
    ).rejects.toThrow('bad routes');

    expect(html.dataset.appFailed).toBe('true');
    expect(appText()).toBe('SHELL');
  });

  it('flags the shell when an initializer throws', async () => {
    h.installError = new Error('pinia failed');

    await expect(
      startApp({ root: Root, createRouter: () => routerWith(() => true) })
    ).rejects.toThrow('pinia failed');

    expect(html.dataset.appFailed).toBe('true');
  });

  it('wraps a non-Error failure in an Error', async () => {
    const router = routerWith(() => {
      throw 'plain string';
    });

    await expect(startApp({ root: Root, createRouter: () => router })).rejects.toThrow(
      '[startApp] Startup failed; app-ready flag not set: plain string'
    );
  });

  // A guard aborts the first navigation only when it hands off to a document
  // load (a hard navigation out of this bundle).
  it('leaves the shell unflagged when the initial navigation is aborted', async () => {
    await expect(
      startApp({ root: Root, createRouter: () => routerWith(() => false) })
    ).resolves.toBeUndefined();

    expect(html.dataset.appFailed).toBeUndefined();
    expect(html.dataset.appReady).toBeUndefined();
    expect(appText()).toBe('SHELL');
  });
});
