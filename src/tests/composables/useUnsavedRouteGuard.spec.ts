// src/tests/composables/useUnsavedRouteGuard.spec.ts
//
// The in-app unsaved-changes confirm. Leaving the route asks; so does a
// same-route param change that remounts the view (App.vue keys it with
// routeViewKey), e.g. the domain switcher replacing :extid. A param change the
// route keeps mounted (meta.keepMountedAcrossParams) loses nothing and does
// not ask. Driven through a real router so the guards fire as they do in the
// app.

import { useUnsavedRouteGuard } from '@/shared/composables/useUnsavedRouteGuard';
import { useRealRouter } from '@/tests/utils/routerSetup';
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { createTestI18n } from '@tests/setup';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { createMemoryHistory, createRouter, RouterView, type Router } from 'vue-router';

useRealRouter();

const MESSAGE = 'web.branding.you_have_unsaved_changes_are_you_sure';

const dirty = ref(false);
const messageKey = ref<string | undefined>(undefined);

const GuardedPage = defineComponent({
  setup() {
    useUnsavedRouteGuard(dirty, messageKey.value);
    return () => h('div', 'page');
  },
});

const Elsewhere = { render: () => h('div', 'elsewhere') };

function makeRouter(): Router {
  return createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/domains/:extid/sso', component: GuardedPage },
      {
        path: '/settings/:extid/:tab',
        component: GuardedPage,
        meta: { keepMountedAcrossParams: ['tab'] },
      },
      { path: '/elsewhere', component: Elsewhere },
    ],
  });
}

describe('useUnsavedRouteGuard', () => {
  let router: Router;
  let wrapper: VueWrapper;
  let confirm: ReturnType<typeof vi.spyOn>;

  async function mountAt(path: string) {
    router = makeRouter();
    await router.push(path);
    wrapper = mount(RouterView, { global: { plugins: [router, createTestI18n()] } });
    await flushPromises();
  }

  beforeEach(() => {
    dirty.value = false;
    messageKey.value = undefined;
    confirm = vi.spyOn(window, 'confirm');
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
  });

  describe('leaving the route', () => {
    it('leaves without asking when nothing is unsaved', async () => {
      await mountAt('/domains/dm_a/sso');

      await router.push('/elsewhere');

      expect(confirm).not.toHaveBeenCalled();
      expect(router.currentRoute.value.fullPath).toBe('/elsewhere');
    });

    it('asks, and stays on "cancel"', async () => {
      confirm.mockReturnValue(false);
      dirty.value = true;
      await mountAt('/domains/dm_a/sso');

      await router.push('/elsewhere');

      expect(confirm).toHaveBeenCalledWith(MESSAGE);
      expect(router.currentRoute.value.fullPath).toBe('/domains/dm_a/sso');
    });

    it('asks, and leaves on "ok"', async () => {
      confirm.mockReturnValue(true);
      dirty.value = true;
      await mountAt('/domains/dm_a/sso');

      await router.push('/elsewhere');

      expect(confirm).toHaveBeenCalledOnce();
      expect(router.currentRoute.value.fullPath).toBe('/elsewhere');
    });

    it('asks with the message key it was given', async () => {
      confirm.mockReturnValue(false);
      dirty.value = true;
      messageKey.value = 'web.domains.unsaved_changes_confirmation';
      await mountAt('/domains/dm_a/sso');

      await router.push('/elsewhere');

      expect(confirm).toHaveBeenCalledWith('web.domains.unsaved_changes_confirmation');
    });
  });

  describe('a param change on the same route', () => {
    it('asks when it remounts the view, and stays on "cancel"', async () => {
      confirm.mockReturnValue(false);
      dirty.value = true;
      await mountAt('/domains/dm_a/sso');

      await router.push('/domains/dm_b/sso');

      expect(confirm).toHaveBeenCalledWith(MESSAGE);
      expect(router.currentRoute.value.fullPath).toBe('/domains/dm_a/sso');
    });

    it('proceeds on "ok"', async () => {
      confirm.mockReturnValue(true);
      dirty.value = true;
      await mountAt('/domains/dm_a/sso');

      await router.push('/domains/dm_b/sso');

      expect(router.currentRoute.value.fullPath).toBe('/domains/dm_b/sso');
    });

    it('does not ask when nothing is unsaved', async () => {
      await mountAt('/domains/dm_a/sso');

      await router.push('/domains/dm_b/sso');

      expect(confirm).not.toHaveBeenCalled();
      expect(router.currentRoute.value.fullPath).toBe('/domains/dm_b/sso');
    });

    it('does not ask when the route keeps the view mounted across that param', async () => {
      dirty.value = true;
      await mountAt('/settings/dm_a/general');

      await router.push('/settings/dm_a/members');

      expect(confirm).not.toHaveBeenCalled();
      expect(router.currentRoute.value.fullPath).toBe('/settings/dm_a/members');
    });

    it('asks when a param outside keepMountedAcrossParams changes', async () => {
      confirm.mockReturnValue(false);
      dirty.value = true;
      await mountAt('/settings/dm_a/general');

      await router.push('/settings/dm_b/general');

      expect(confirm).toHaveBeenCalledWith(MESSAGE);
      expect(router.currentRoute.value.fullPath).toBe('/settings/dm_a/general');
    });
  });
});
