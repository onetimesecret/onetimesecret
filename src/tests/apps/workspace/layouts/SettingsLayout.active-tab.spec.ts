// src/tests/apps/workspace/layouts/SettingsLayout.active-tab.spec.ts

import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, nextTick } from 'vue';
import { setupTestPinia } from '@/tests/setup';
import { createTestI18n } from '@tests/setup';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
import { authenticatedBootstrap } from '@/tests/fixtures/bootstrap.fixture';

const route = vi.hoisted(() => ({ path: '/account/settings/profile' }));
vi.mock('vue-router', () => ({
  useRoute: () => route,
}));

// Forwards every fallthrough attr (aria-current included) to the <a>, the way
// the real RouterLink's root element receives them.
const RouterLinkStub = defineComponent({
  name: 'RouterLink',
  inheritAttrs: false,
  props: { to: { type: String, required: true } },
  setup(props, { slots, attrs }) {
    return () => h('a', { ...attrs, href: props.to, 'data-tab-to': props.to }, slots.default?.());
  },
});

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: defineComponent({
    name: 'OIcon',
    props: ['collection', 'name'],
    template: '<span class="o-icon" />',
  }),
}));

const i18n = createTestI18n();

async function mountAt(path: string): Promise<VueWrapper> {
  route.path = path;
  await setupTestPinia();
  const store = useBootstrapStore();
  store.update({
    ...authenticatedBootstrap,
    authentication: { ...authenticatedBootstrap.authentication, mode: 'full' },
    has_password: true,
  });
  const wrapper = mount(SettingsLayout, {
    global: { plugins: [i18n], stubs: { RouterLink: RouterLinkStub } },
  });
  await nextTick();
  return wrapper;
}

function currentTabs(wrapper: VueWrapper): string[] {
  return wrapper
    .findAll('a[data-tab-to][aria-current="page"]')
    .map((a) => a.attributes('data-tab-to') ?? '');
}

describe('SettingsLayout — active tab is marked aria-current="page"', () => {
  let wrapper: VueWrapper | null = null;

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('marks the Profile tab on its redirect target /profile/preferences', async () => {
    wrapper = await mountAt('/account/settings/profile/preferences');
    expect(currentTabs(wrapper)).toEqual(['/account/settings/profile']);
  });

  it('marks the Security tab on a Security child page', async () => {
    wrapper = await mountAt('/account/settings/security/password');
    expect(currentTabs(wrapper)).toEqual(['/account/settings/security']);
  });

  it('marks exactly one tab on an exact tab route', async () => {
    wrapper = await mountAt('/account/settings/api');
    expect(currentTabs(wrapper)).toEqual(['/account/settings/api']);
  });
});
