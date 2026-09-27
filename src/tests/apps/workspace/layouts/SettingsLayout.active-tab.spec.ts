// src/tests/apps/workspace/layouts/SettingsLayout.active-tab.spec.ts

import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, nextTick, reactive } from 'vue';
import { setupTestPinia } from '@/tests/setup';
import { createTestI18n } from '@tests/setup';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
import { authenticatedBootstrap } from '@/tests/fixtures/bootstrap.fixture';

// Reactive, like the router's current route, so a test can navigate after
// mount. Read lazily by the mock, after this module has run.
const route = reactive({ path: '/account/settings/profile' });
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

async function mountAt(path: string, slot?: () => unknown): Promise<VueWrapper> {
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
    slots: slot ? { default: slot } : {},
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

  it('moves the mark when the route changes under the mounted layout', async () => {
    wrapper = await mountAt('/account/settings/profile/preferences');
    const layout = wrapper.element;

    route.path = '/account/settings/security/password';
    await nextTick();

    expect(wrapper.element).toBe(layout);
    expect(currentTabs(wrapper)).toEqual(['/account/settings/security']);
  });

  it('marks no tab on a route outside every tab', async () => {
    wrapper = await mountAt('/account/settings');
    expect(currentTabs(wrapper)).toEqual([]);
  });
});

describe('SettingsLayout — page frame', () => {
  let wrapper: VueWrapper | null = null;

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('renders the page in its content area, after the tab navigation', async () => {
    wrapper = await mountAt('/account/settings/api', () =>
      h('form', { 'data-testid': 'settings-page' }, 'API settings')
    );

    const nav = wrapper.find('nav[aria-label="Settings navigation"]');
    const page = wrapper.find('[data-testid="settings-page"]');
    expect(page.text()).toBe('API settings');
    expect(nav.element.contains(page.element)).toBe(false);
    expect(
      nav.element.compareDocumentPosition(page.element) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
  });

  it('puts every tab link in the labelled settings navigation', async () => {
    wrapper = await mountAt('/account/settings/profile');

    const nav = wrapper.find('nav[aria-label="Settings navigation"]');
    const tabLinks = nav.findAll('a[data-tab-to]').map((a) => a.attributes('data-tab-to'));
    expect(tabLinks).toContain('/account/settings/profile');
    expect(tabLinks.length).toBeGreaterThan(1);

    // The one link outside it is the back link to the dashboard.
    const otherLinks = wrapper
      .findAll('a[data-tab-to]')
      .filter((a) => !nav.element.contains(a.element))
      .map((a) => a.attributes('data-tab-to'));
    expect(otherLinks).toEqual(['/']);
  });

  it('titles the page with a single h1 and links back to the dashboard', async () => {
    wrapper = await mountAt('/account/settings/profile');

    const headings = wrapper.findAll('h1');
    expect(headings).toHaveLength(1);
    expect(headings[0].text()).toBe('web.TITLES.account');
    const back = wrapper.find('a[href="/"]');
    expect(back.text()).toBe('web.settings.back_to_dashboard');
  });
});
