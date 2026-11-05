// src/tests/apps/admin/AdminLayout.spec.ts

import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
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

// The header's step-up control is real; only its transport is faked.
const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
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
        renderStubDefaultSlot: true,
        stubs: { 'router-link': { template: '<a><slot /></a>' } },
      },
    });

  it('renders the Data Tools band with Secret Receipts and Schemas', () => {
    wrapper = mountLayout();
    const nav = wrapper.find('aside nav');
    const heading = nav.findAll('p').find((p) => p.text() === 'web.colonel.nav.groups.data');
    expect(heading).toBeDefined();
    const band = heading!.element.nextElementSibling;
    expect(band?.textContent).toContain('web.admin.secrets.title');
    expect(band?.textContent).toContain('web.admin.schemas.title');
    expect(band?.textContent).not.toContain('web.colonel.titles.system');
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

  // #4327: the step-up state beside the operator's email, so they can opt in
  // before a destructive task and see (and end) a live window at a glance.
  describe('header elevation control', () => {
    const elevateButton = (w: VueWrapper) => w.find('[data-testid="elevation-control-elevate"]');
    const dropButton = (w: VueWrapper) => w.find('[data-testid="elevation-control-drop"]');

    beforeEach(() => __resetColonelElevationState({ statusRead: true }));
    afterEach(() => __resetColonelElevationState());

    it('offers "Elevate" when step-up is on and no window is live, and opens the prompt', async () => {
      wrapper = mountLayout();

      expect(dropButton(wrapper).exists()).toBe(false);
      const button = elevateButton(wrapper);
      expect(button.exists()).toBe(true);
      expect(button.text()).toContain('web.admin.elevation.control.elevate');
      expect(button.find('[data-name="lock-closed"]').exists()).toBe(true);

      await button.trigger('click');

      expect(useColonelElevation().promptOpen.value).toBe(true);
      // Opening the prompt is local; the prompt itself owns the status read.
      expect(mockApi.get).not.toHaveBeenCalled();
      expect(mockApi.post).not.toHaveBeenCalled();
      useColonelElevation().resolvePrompt(false);
    });

    it('shows the unlocked icon and the m:ss left while a window is live, and drops it on click', async () => {
      const elevation = useColonelElevation();
      elevation.elevated.value = true;
      elevation.expiresAt.value = Math.floor(Date.now() / 1000) + 299;
      elevation.secondsRemaining.value = 299;
      mockApi.delete.mockResolvedValue({ data: {} });
      mockApi.get.mockResolvedValue({
        data: {
          shrimp: '',
          record: { elevated: false, expires_at: null, seconds_remaining: 0 },
          details: {
            enabled: true,
            window: 600,
            reauth_grace: 0,
            grace_available: false,
            password_available: true,
            factors: ['password'],
          },
        },
      });

      wrapper = mountLayout();

      expect(elevateButton(wrapper).exists()).toBe(false);
      const button = dropButton(wrapper);
      expect(button.exists()).toBe(true);
      expect(button.find('[data-name="lock-open"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="elevation-control-remaining"]').text()).toBe('4:59');
      expect(button.attributes('aria-label')).toBe('web.admin.elevation.control.drop');

      await button.trigger('click');
      await flushPromises();

      expect(mockApi.delete).toHaveBeenCalledWith('/api/colonel/elevation');
      expect(dropButton(wrapper).exists()).toBe(false);
      expect(elevateButton(wrapper).exists()).toBe(true);
    });

    it('renders nothing when step-up is disabled by config', () => {
      useColonelElevation().enabled.value = false;
      wrapper = mountLayout();

      expect(elevateButton(wrapper).exists()).toBe(false);
      expect(dropButton(wrapper).exists()).toBe(false);
    });

    it('renders nothing while the admin session has expired', () => {
      const elevation = useColonelElevation();
      elevation.elevated.value = true;
      elevation.secondsRemaining.value = 120;
      elevation.adminSessionExpired.value = true;
      wrapper = mountLayout();

      expect(elevateButton(wrapper).exists()).toBe(false);
      expect(dropButton(wrapper).exists()).toBe(false);
    });
  });
});
