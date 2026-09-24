// src/tests/apps/admin/AdminLayout.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/colonel', meta: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

// The step-up banner/prompt have their own specs; keep this one about the shell.
vi.mock('@/apps/admin/components/ElevationBanner.vue', () => ({
  default: { name: 'ElevationBanner', template: '<div />' },
}));
vi.mock('@/apps/admin/components/ElevationPrompt.vue', () => ({
  default: { name: 'ElevationPrompt', template: '<div />' },
}));

import AdminLayout from '@/apps/admin/layouts/AdminLayout.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

/**
 * The console shell. Covers the one piece of deployment context an operator
 * previously had to leave the console to read: the running app version.
 */
describe('AdminLayout (console shell)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });
  afterEach(() => wrapper?.unmount());

  const mountLayout = () =>
    mount(AdminLayout, {
      global: {
        plugins: [i18n],
        stubs: { 'router-link': { template: '<a><slot /></a>' } },
      },
    });

  it('pins the running app version in the rail foot, linked to its release notes', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.ot_version = '0.26.11';
    bootstrap.ot_version_long = '0.26.11 (abc1234)';

    wrapper = mountLayout();

    const version = wrapper.find('[data-testid="admin-app-version"]');
    expect(version.exists()).toBe(true);
    expect(version.text()).toBe('v0.26.11 (abc1234)');
    expect(version.attributes('href')).toBe(
      'https://github.com/onetimesecret/onetimesecret/releases/tag/v0.26.11'
    );
    expect(version.attributes('rel')).toContain('noopener');
  });

  it('falls back to the short version when no long form is provided', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.ot_version = '0.26.11';
    bootstrap.ot_version_long = '';

    wrapper = mountLayout();

    expect(wrapper.find('[data-testid="admin-app-version"]').text()).toBe('v0.26.11');
  });

  it('renders nothing for the version when bootstrap carries none', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.ot_version = '';
    bootstrap.ot_version_long = '';

    wrapper = mountLayout();

    expect(wrapper.find('[data-testid="admin-app-version"]').exists()).toBe(false);
    // The escape hatch beside it is unaffected.
    expect(wrapper.find('[data-testid="admin-back-to-site"]').exists()).toBe(true);
  });
});
