// src/tests/apps/workspace/account/settings/ProfileSettings.spec.ts
//
// Tests for ProfileSettings mount-time behavior and the Default workspace
// preference.

import ProfileSettings from '@/apps/workspace/account/settings/ProfileSettings.vue';
import { organizationSchema } from '@/schemas/shapes/organizations/organization';
import type { Organization } from '@/types/organization';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import axios from 'axios';
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
  authenticated: true,
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
  isListLoading: false,
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

let wrapper: VueWrapper | undefined;

beforeEach(() => {
  vi.clearAllMocks();
  bootstrapStore.authenticated = true;
  bootstrapStore.has_password.value = true;
  bootstrapStore.i18n_enabled.value = false;
  organizationStore.organizations = [];
  organizationStore.isListFetched = true;
  organizationStore.isListLoading = false;
  organizationStore.loading = false;
  organizationStore.fetchOrganizations.mockResolvedValue([]);
  organizationStore.setDefaultOrganization.mockReset();
});

afterEach(() => {
  wrapper?.unmount();
  wrapper = undefined;
});

const mountComponent = () => {
  wrapper = mount(ProfileSettings, {
    global: {
      plugins: [i18n, createTestingPinia({ createSpy: vi.fn, stubActions: false })],
    },
  });
  return wrapper;
};

describe('ProfileSettings', () => {
  describe('On mount', () => {
    it('fetches account info exactly once', async () => {
      mountComponent();
      await flushPromises();

      expect(fetchAccountInfo).toHaveBeenCalledTimes(1);
    });
  });

  describe('Email verification status', () => {
    // green-600 small text on the translucent card is ~3.2:1 and fails the
    // axe color-contrast rule; green-700 (light) / green-400 (dark) pass AA.
    it('renders the verified label with AA-contrast green classes', () => {
      const label = mountComponent()
        .findAll('span.text-sm')
        .find((el) => el.text().includes('web.auth.account.verified'));
      expect(label).toBeDefined();
      expect(label!.classes()).toEqual(
        expect.arrayContaining(['text-green-700', 'dark:text-green-400'])
      );
      expect(label!.classes()).not.toContain('text-green-600');
    });
  });
});

// ── Default workspace ───────────────────────────────────────────────────────
// Members who own no organization (invite, tenant SSO) cannot open /orgs, so
// this row is where they choose their default.

const row = () => wrapper!.find('[data-testid="default-workspace-setting"]');
const select = () => wrapper!.find<HTMLSelectElement>('[data-testid="default-workspace-select"]');
const saveButton = () => wrapper!.find('[data-testid="default-workspace-save"]');

/** Like a store that saved: the default flag moves to `chosen`. */
const moveDefaultTo = (chosen: Organization) => {
  organizationStore.organizations = organizationStore.organizations.map((o) => ({
    ...o,
    is_current_user_default: o.objid === chosen.objid,
  }));
};

/** setDefaultOrganization that succeeds and moves the flag */
const saveSucceeds = (previous: string | null) =>
  organizationStore.setDefaultOrganization.mockImplementation(async (chosen: Organization) => {
    moveDefaultTo(chosen);
    return { organization_id: chosen.objid, previous_default_organization_id: previous };
  });

const choose = async (objid: string) => {
  await select().setValue(objid);
  await flushPromises();
};

const save = async () => {
  await saveButton().trigger('click');
  await flushPromises();
};

const mountWith = async (orgs: Organization[]) => {
  organizationStore.organizations = orgs;
  mountComponent();
  await flushPromises();
};

describe('ProfileSettings default workspace', () => {
  it('is hidden for a user in a single organization', async () => {
    await mountWith([org('a', { is_current_user_default: true })]);

    expect(row().exists()).toBe(false);
  });

  it('lists every organization when the user belongs to more than one', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);

    expect(row().exists()).toBe(true);
    expect(row().find('label').text()).toBe('web.settings.default_workspace.title');
    expect(row().find('label').attributes('for')).toBe(select().attributes('id'));
    const options = select().findAll('option');
    expect(options.map((o) => o.text())).toEqual(['Org a', 'Org b']);
    expect(saveButton().text()).toBe('web.COMMON.word_save');
  });

  it("starts on this user's default, not the owner's auto-created workspace", async () => {
    await mountWith([org('a', { is_default: true }), org('b', { is_current_user_default: true })]);

    expect(select().element.value).toBe('b');
    expect(select().text()).not.toContain('web.settings.default_workspace.not_set');
  });

  it('shows a disabled "Not set" placeholder when no default is recorded', async () => {
    await mountWith([org('a'), org('b')]);

    const placeholder = select().find('option[value=""]');
    expect(placeholder.exists()).toBe(true);
    expect(placeholder.text()).toBe('web.settings.default_workspace.not_set');
    expect(placeholder.attributes('disabled')).toBeDefined();
    expect(select().element.value).toBe('');
  });
});

// WCAG 3.2.2: arrow keys on a closed select fire `change` in some browsers,
// so choosing must not save; the Save button does.
describe('ProfileSettings default workspace: choosing and saving', () => {
  it('does not save when the selection changes', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);

    await choose('b');
    await select().trigger('keydown', { key: 'ArrowDown' });
    await flushPromises();

    expect(organizationStore.setDefaultOrganization).not.toHaveBeenCalled();
    expect(select().element.value).toBe('b');
    expect(select().attributes('disabled')).toBeUndefined();
  });

  it('marks Save unavailable while the choice is the saved default', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);

    expect(saveButton().attributes('aria-disabled')).toBe('true');
    // aria-disabled, not disabled, so focus survives a press
    expect(saveButton().attributes('disabled')).toBeUndefined();
    await save();
    expect(organizationStore.setDefaultOrganization).not.toHaveBeenCalled();

    await choose('b');
    expect(saveButton().attributes('aria-disabled')).toBe('false');
    await choose('a');
    expect(saveButton().attributes('aria-disabled')).toBe('true');
  });

  it('saves the chosen organization on Save and reports success', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);
    saveSucceeds('a');

    await choose('b');
    await save();

    expect(organizationStore.setDefaultOrganization).toHaveBeenCalledTimes(1);
    expect(organizationStore.setDefaultOrganization).toHaveBeenCalledWith(
      expect.objectContaining({ objid: 'b', extid: 'on_b' })
    );
    expect(select().element.value).toBe('b');
    expect(saveButton().attributes('aria-disabled')).toBe('true');
    expect(showMock).toHaveBeenCalledWith(
      'web.organizations.make_default_success',
      'success',
      'top'
    );
  });

  it('marks Save busy and ignores another press while saving', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);
    let finish: () => void = () => {};
    organizationStore.setDefaultOrganization.mockImplementation(
      (chosen: Organization) =>
        new Promise((resolve) => {
          finish = () => {
            moveDefaultTo(chosen);
            resolve({ organization_id: chosen.objid, previous_default_organization_id: 'a' });
          };
        })
    );

    await choose('b');
    await save();
    expect(saveButton().attributes('aria-busy')).toBe('true');
    expect(saveButton().attributes('aria-disabled')).toBe('true');
    expect(select().attributes('disabled')).toBeUndefined();
    await save();
    expect(organizationStore.setDefaultOrganization).toHaveBeenCalledTimes(1);

    finish();
    await flushPromises();
    expect(saveButton().attributes('aria-busy')).toBe('false');
  });

  it('replaces the placeholder once a first default is saved', async () => {
    await mountWith([org('a'), org('b')]);
    saveSucceeds(null);

    await choose('a');
    await save();

    expect(organizationStore.setDefaultOrganization).toHaveBeenCalledWith(
      expect.objectContaining({ objid: 'a' })
    );
    expect(select().find('option[value=""]').exists()).toBe(false);
    expect(select().element.value).toBe('a');
  });

  it('reports a failure and keeps the choice so Save can be pressed again', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);
    organizationStore.setDefaultOrganization.mockRejectedValue(new Error('Invalid organization'));
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    await choose('b');
    await save();

    expect(organizationStore.setDefaultOrganization).toHaveBeenCalledTimes(1);
    expect(select().element.value).toBe('b');
    expect(saveButton().attributes('aria-disabled')).toBe('false');
    expect(showMock).toHaveBeenCalledWith('web.organizations.make_default_error', 'error', 'top');
    expect(showMock).not.toHaveBeenCalledWith(
      'web.organizations.make_default_success',
      expect.anything(),
      expect.anything()
    );
    errorSpy.mockRestore();
  });

  it('stays quiet when a sign-out cancels the change', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);
    organizationStore.setDefaultOrganization.mockRejectedValue(new axios.CanceledError());
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    await choose('b');
    await save();

    expect(showMock).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});

describe('ProfileSettings default workspace: following the saved default', () => {
  it('follows a default changed elsewhere (e.g. Make default on /orgs)', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b')]);

    moveDefaultTo(organizationStore.organizations[1]);
    await flushPromises();

    expect(select().element.value).toBe('b');
    expect(saveButton().attributes('aria-disabled')).toBe('true');
  });

  it('keeps an unsaved choice when the default changes elsewhere', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b'), org('c')]);

    await choose('c');
    moveDefaultTo(organizationStore.organizations[1]);
    await flushPromises();

    expect(select().element.value).toBe('c');
    expect(saveButton().attributes('aria-disabled')).toBe('false');
  });

  it('starts over from the reloaded list after a store reset', async () => {
    await mountWith([org('a', { is_current_user_default: true }), org('b'), org('c')]);
    await choose('c');

    organizationStore.organizations = [];
    await flushPromises();
    expect(row().exists()).toBe(false);

    organizationStore.organizations = [org('a'), org('b', { is_current_user_default: true })];
    await flushPromises();
    expect(select().element.value).toBe('b');
  });
});

describe('ProfileSettings default workspace: loading the organization list', () => {
  it('fetches the list when it has not been loaded', async () => {
    organizationStore.isListFetched = false;
    await mountWith([]);

    expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
  });

  it('does not fetch again when the list is loaded', async () => {
    await mountWith([]);

    expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();
  });

  // OrganizationContextBar (in the layout) usually starts the fetch first;
  // a second call would abort it.
  it('waits while a list fetch is in flight, then fetches if the list is still missing', async () => {
    organizationStore.isListFetched = false;
    organizationStore.isListLoading = true;
    await mountWith([]);
    expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();

    // that fetch failed or was cancelled; no list arrived
    organizationStore.isListLoading = false;
    await flushPromises();

    expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
  });

  // `loading` is shared by every store action, so it is no reason to wait.
  it('does not wait on other store actions', async () => {
    organizationStore.isListFetched = false;
    organizationStore.loading = true;
    await mountWith([]);

    expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
  });

  it('does not fetch when the list fetch it waited on brought the list', async () => {
    organizationStore.isListFetched = false;
    organizationStore.isListLoading = true;
    await mountWith([]);

    organizationStore.organizations = [org('a', { is_current_user_default: true }), org('b')];
    organizationStore.isListFetched = true;
    organizationStore.isListLoading = false;
    await flushPromises();

    expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();
    expect(row().exists()).toBe(true);
  });

  it('leaves the row hidden when the fetch fails, and does not retry', async () => {
    organizationStore.isListFetched = false;
    organizationStore.fetchOrganizations.mockRejectedValue(new Error('Network Error'));
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    await mountWith([]);

    // a later list fetch settling does not start another attempt
    organizationStore.isListLoading = true;
    await flushPromises();
    organizationStore.isListLoading = false;
    await flushPromises();

    expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
    expect(row().exists()).toBe(false);
    expect(errorSpy).toHaveBeenCalledTimes(1);
    errorSpy.mockRestore();
  });

  // Signing out resets the store, which clears isListFetched.
  it('does not fetch after sign-out resets the store', async () => {
    await mountWith([org('a'), org('b')]);

    bootstrapStore.authenticated = false;
    organizationStore.organizations = [];
    organizationStore.isListFetched = false;
    await flushPromises();

    expect(organizationStore.fetchOrganizations).not.toHaveBeenCalled();
  });

  it('stays quiet when its fetch is superseded, and uses the list the other fetch brings', async () => {
    organizationStore.isListFetched = false;
    organizationStore.fetchOrganizations.mockRejectedValue(new axios.CanceledError());
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    await mountWith([]);

    expect(row().exists()).toBe(false);
    expect(errorSpy).not.toHaveBeenCalled();

    // the superseding fetch lands
    organizationStore.organizations = [org('a'), org('b')];
    organizationStore.isListFetched = true;
    await flushPromises();

    expect(row().exists()).toBe(true);
    expect(organizationStore.fetchOrganizations).toHaveBeenCalledTimes(1);
    errorSpy.mockRestore();
  });
});
