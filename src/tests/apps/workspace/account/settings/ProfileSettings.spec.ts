// src/tests/apps/workspace/account/settings/ProfileSettings.spec.ts
//
// Tests for ProfileSettings mount-time behavior and the Default workspace
// preference.

import ProfileSettings from '@/apps/workspace/account/settings/ProfileSettings.vue';
import { organizationSchema } from '@/schemas/shapes/organizations/organization';
import type { Organization } from '@/types/organization';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { createTestI18n } from '@tests/setup';

// vue-router stubs
vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/account/settings/profile' }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Child components mocked away to keep the test focused
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />', props: ['collection', 'name', 'class'] },
}));
vi.mock('@/shared/components/ui/LanguageToggle.vue', () => ({
  default: { name: 'LanguageToggle', template: '<div class="language-toggle" />' },
}));
vi.mock('@/shared/components/ui/ThemeToggle.vue', () => ({
  default: {
    name: 'ThemeToggle',
    template: '<div class="theme-toggle" />',
    props: ['disabled', 'ariaBusy'],
    emits: ['theme-changed'],
  },
}));
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: { name: 'SettingsLayout', template: '<div class="mock-settings-layout"><slot /></div>' },
}));

// useAccount composable
const fetchAccountInfo = vi.fn().mockResolvedValue(undefined);
vi.mock('@/shared/composables/useAccount', () => ({
  useAccount: () => ({
    accountInfo: ref({ email_verified: true, created_at: '2024-01-01T00:00:00Z' }),
    fetchAccountInfo,
  }),
}));

// Bootstrap store — exposes i18n_enabled / has_password via storeToRefs
const bootstrapStore = {
  email: 'user@example.com',
  i18n_enabled: ref(false),
  has_password: ref(true),
};
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => bootstrapStore,
}));

// Organization store: only what the Default workspace row reads and calls.
// The store's own behavior (request body, refetch, current org) is covered
// end to end in OrganizationsSettings.spec.ts and organizationStore.spec.ts.
const organizationStore = reactive({
  organizations: [] as Organization[],
  isListFetched: true,
  loading: false,
  fetchOrganizations: vi.fn(),
  setDefaultOrganization: vi.fn(),
});
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => organizationStore,
}));

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

/** An Organization parsed from an organizations-list wire record */
const org = (objid: string, over: Record<string, unknown> = {}): Organization =>
  organizationSchema.parse({
    objid,
    extid: `on_${objid}`,
    display_name: `Org ${objid}`,
    description: null,
    owner_id: 'cust-owner',
    contact_email: null,
    planid: 'free_v1',
    is_default: false,
    is_current_user_default: false,
    current_user_role: 'member',
    created: 1700000000,
    updated: 1700000000,
    ...over,
  });

const i18n = createTestI18n();

describe('ProfileSettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    bootstrapStore.has_password.value = true;
    bootstrapStore.i18n_enabled.value = false;
    organizationStore.organizations = [];
    organizationStore.isListFetched = true;
    organizationStore.loading = false;
    organizationStore.fetchOrganizations.mockResolvedValue([]);
    organizationStore.setDefaultOrganization.mockReset();
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = () =>
    mount(ProfileSettings, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({ createSpy: vi.fn, stubActions: false }),
        ],
      },
    });

  describe('On mount', () => {
    it('fetches account info exactly once', async () => {
      wrapper = mountComponent();
      await flushPromises();

      expect(fetchAccountInfo).toHaveBeenCalledTimes(1);
    });
  });

  describe('Email verification status', () => {
    // green-600 small text on the translucent card is ~3.2:1 and fails the
    // axe color-contrast rule; green-700 (light) / green-400 (dark) pass AA.
    it('renders the verified label with AA-contrast green classes', () => {
      wrapper = mountComponent();

      const label = wrapper
        .findAll('span.text-sm')
        .find((el) => el.text().includes('web.auth.account.verified'));
      expect(label).toBeDefined();
      expect(label!.classes()).toEqual(
        expect.arrayContaining(['text-green-700', 'dark:text-green-400'])
      );
      expect(label!.classes()).not.toContain('text-green-600');
    });
  });

  // Members who own no organization (invite, tenant SSO) cannot open /orgs,
  // so this row is where they choose their default.
  describe('Default workspace', () => {
    const row = () => wrapper.find('[data-testid="default-workspace-setting"]');
    const select = () =>
      wrapper.find<HTMLSelectElement>('[data-testid="default-workspace-select"]');

    const choose = async (objid: string) => {
      await select().setValue(objid);
      await flushPromises();
    };

    it('is hidden for a user in a single organization', async () => {
      organizationStore.organizations = [org('a', { is_current_user_default: true })];
      wrapper = mountComponent();
      await flushPromises();

      expect(row().exists()).toBe(false);
    });

    it('lists every organization when the user belongs to more than one', async () => {
      organizationStore.organizations = [org('a', { is_current_user_default: true }), org('b')];
      wrapper = mountComponent();
      await flushPromises();

      expect(row().exists()).toBe(true);
      expect(row().find('label').text()).toBe('web.settings.default_workspace.title');
      expect(row().find('label').attributes('for')).toBe(select().attributes('id'));
      const options = select().findAll('option');
      expect(options.map((o) => o.text())).toEqual(['Org a', 'Org b']);
    });

    it("starts on this user's default, not the owner's auto-created workspace", async () => {
      organizationStore.organizations = [
        org('a', { is_default: true }),
        org('b', { is_current_user_default: true }),
      ];
      wrapper = mountComponent();
      await flushPromises();

      expect(select().element.value).toBe('b');
      expect(select().text()).not.toContain('web.settings.default_workspace.not_set');
    });

    it('shows a disabled "Not set" placeholder when no default is recorded', async () => {
      organizationStore.organizations = [org('a'), org('b')];
      wrapper = mountComponent();
      await flushPromises();

      const placeholder = select().find('option[value=""]');
      expect(placeholder.exists()).toBe(true);
      expect(placeholder.text()).toBe('web.settings.default_workspace.not_set');
      expect(placeholder.attributes('disabled')).toBeDefined();
      expect(select().element.value).toBe('');
    });

    it('saves the chosen organization as the default and reports success', async () => {
      organizationStore.organizations = [org('a', { is_current_user_default: true }), org('b')];
      organizationStore.setDefaultOrganization.mockImplementation(async (chosen: Organization) => {
        organizationStore.organizations = organizationStore.organizations.map((o) => ({
          ...o,
          is_current_user_default: o.objid === chosen.objid,
        }));
        return { organization_id: chosen.objid, previous_default_organization_id: 'a' };
      });
      wrapper = mountComponent();
      await flushPromises();

      await choose('b');

      expect(organizationStore.setDefaultOrganization).toHaveBeenCalledTimes(1);
      expect(organizationStore.setDefaultOrganization).toHaveBeenCalledWith(
        expect.objectContaining({ objid: 'b', extid: 'on_b' })
      );
      expect(select().element.value).toBe('b');
      expect(select().attributes('disabled')).toBeUndefined();
      expect(showMock).toHaveBeenCalledWith(
        'web.organizations.make_default_success',
        'success',
        'top'
      );
    });

    it('replaces the placeholder once a first default is chosen', async () => {
      organizationStore.organizations = [org('a'), org('b')];
      organizationStore.setDefaultOrganization.mockImplementation(async (chosen: Organization) => {
        organizationStore.organizations = organizationStore.organizations.map((o) => ({
          ...o,
          is_current_user_default: o.objid === chosen.objid,
        }));
        return { organization_id: chosen.objid, previous_default_organization_id: null };
      });
      wrapper = mountComponent();
      await flushPromises();

      await choose('a');

      expect(organizationStore.setDefaultOrganization).toHaveBeenCalledWith(
        expect.objectContaining({ objid: 'a' })
      );
      expect(select().find('option[value=""]').exists()).toBe(false);
      expect(select().element.value).toBe('a');
    });

    it('reports a failure and puts the select back on the stored default', async () => {
      organizationStore.organizations = [org('a', { is_current_user_default: true }), org('b')];
      organizationStore.setDefaultOrganization.mockRejectedValue(new Error('Invalid organization'));
      const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      wrapper = mountComponent();
      await flushPromises();

      await choose('b');

      expect(organizationStore.setDefaultOrganization).toHaveBeenCalledTimes(1);
      expect(select().element.value).toBe('a');
      expect(select().attributes('disabled')).toBeUndefined();
      expect(showMock).toHaveBeenCalledWith('web.organizations.make_default_error', 'error', 'top');
      expect(showMock).not.toHaveBeenCalledWith(
        'web.organizations.make_default_success',
        expect.anything(),
        expect.anything()
      );
      errorSpy.mockRestore();
    });

    it('goes back to "Not set" when a first choice fails', async () => {
      organizationStore.organizations = [org('a'), org('b')];
      organizationStore.setDefaultOrganization.mockRejectedValue(new Error('Invalid organization'));
      const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      wrapper = mountComponent();
      await flushPromises();

      await choose('b');

      expect(select().element.value).toBe('');
      expect(select().find('option[value=""]').exists()).toBe(true);
      expect(showMock).toHaveBeenCalledWith('web.organizations.make_default_error', 'error', 'top');
      errorSpy.mockRestore();
    });

    describe('loading the organization list', () => {
      it('fetches the list when it has not been loaded', async () => {
        organizationStore.isListFetched = false;
        wrapper = mountComponent();
        await flushPromises();

        expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
      });

      it('does not fetch again when the list is loaded', async () => {
        wrapper = mountComponent();
        await flushPromises();

        expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();
      });

      // OrganizationContextBar (in the layout) usually starts the fetch first;
      // a second call would abort it.
      it('does not start a second fetch while one is in flight', async () => {
        organizationStore.isListFetched = false;
        organizationStore.loading = true;
        wrapper = mountComponent();
        await flushPromises();

        expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();
      });
    });
  });
});
