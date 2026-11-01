// src/tests/shared/components/ui/RouteLoadNotice.spec.ts
//
// RouteLoadNotice: the inline notice for a page whose chunk did not load while
// this page declined to reload (src/utils/routeLoadFailure.ts). It says the
// page could not open, tells the user to copy what they need first, and offers
// a reload and a dismiss button. Mounted with the app's real i18n instance, so
// the copy asserted is the English the component ships
// (locales/content/en/10-layout.json).

import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />' },
}));

import i18n, { globalComposer } from '@/i18n';
import RouteLoadNotice from '@/shared/components/ui/RouteLoadNotice.vue';
import {
  dismissRouteLoadFailure,
  recordRouteLoadFailure,
  routeLoadFailure,
} from '@/utils/routeLoadFailure';

describe('RouteLoadNotice', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    globalComposer.locale.value = 'en';
    dismissRouteLoadFailure();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
  });

  const render = () => {
    wrapper = mount(RouteLoadNotice, { global: { plugins: [i18n] } });
    return wrapper;
  };
  const notice = () => wrapper!.find('[data-testid="route-load-notice"]');

  it('renders nothing while no failure is recorded', () => {
    render();

    expect(notice().exists()).toBe(false);
  });

  it('announces a recorded failure as an alert, in English copy, with a reload button', () => {
    recordRouteLoadFailure('/account');
    render();

    expect(notice().attributes('role')).toBe('alert');
    expect(notice().text()).toContain('This page could not be opened');
    expect(notice().text()).toContain(
      'Part of the site did not load, so the page you asked for could not open. ' +
        'Copy anything you still need from this page, then reload it.'
    );
    const reload = wrapper!.find('[data-testid="route-load-notice-reload"]');
    expect(reload.attributes('type')).toBe('button');
    expect(reload.text()).toBe('Reload page');
  });

  it('appears when a failure is recorded after it mounted', async () => {
    render();
    expect(notice().exists()).toBe(false);

    recordRouteLoadFailure('/account');
    await nextTick();

    expect(notice().exists()).toBe(true);
  });

  it('is dismissed by its button, which clears the record', async () => {
    recordRouteLoadFailure('/account');
    render();

    await wrapper!.find('[data-testid="route-load-notice-dismiss"]').trigger('click');

    expect(routeLoadFailure.value).toBeNull();
    expect(notice().exists()).toBe(false);
  });
});
