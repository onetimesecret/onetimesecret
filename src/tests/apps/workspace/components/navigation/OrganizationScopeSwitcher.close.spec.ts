// src/tests/apps/workspace/components/navigation/OrganizationScopeSwitcher.close.spec.ts

/**
 * End-to-end close-behaviour regression for the Organization Scope Switcher.
 *
 * Mirrors DomainContextSwitcher.close.spec.ts: it uses the REAL @headlessui/vue
 * Menu so it exercises the actual open/close state machine, then drives the
 * genuine user flow (open -> click -> assert the panel is gone). This guards the
 * same class of bug the domain switcher had — the gear icon's stopPropagation
 * suppressing HeadlessUI's built-in MenuItem close, leaving the dropdown open
 * after navigation.
 *
 * Only the component's data dependencies are stubbed; HeadlessUI is real.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, reactive, ref } from 'vue';
import OrganizationScopeSwitcher from '@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue';

// NOTE: no vi.mock('@headlessui/vue') here — that is the whole point.

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class', 'ariaLabel'],
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const mockPush = vi.fn();
const mockRoute = reactive<{ name?: string; meta: Record<string, unknown>; params: Record<string, unknown> }>({
  name: 'dashboard',
  meta: {},
  params: {},
});
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush }),
}));

type TestOrg = {
  objid: string;
  extid?: string;
  display_name: string;
  is_default?: boolean;
  planid?: string;
  current_user_role?: 'owner' | 'admin' | 'member' | null;
};

const acme: TestOrg = { objid: 'o1', extid: 'org1', display_name: 'Acme Inc', current_user_role: 'owner' };
const personal: TestOrg = {
  objid: 'o2',
  extid: 'org2',
  display_name: 'Personal',
  is_default: true,
  current_user_role: 'owner',
};

const mockOrganizations = ref<TestOrg[]>([acme, personal]);
const mockCurrentOrganization = ref<TestOrg | null>(acme);
const mockSetCurrentOrganization = vi.fn();
const mockSelectOrganization = vi.fn();
const mockOrgStore = reactive({
  organizations: mockOrganizations,
  currentOrganization: mockCurrentOrganization,
  hasOrganizations: true,
  setCurrentOrganization: mockSetCurrentOrganization,
  selectOrganization: mockSelectOrganization,
});
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrgStore,
}));

const dropdown = (w: VueWrapper) =>
  w.find('[data-testid="org-scope-switcher-dropdown"]');

async function openMenu(w: VueWrapper) {
  await w.get('[data-testid="org-scope-switcher-trigger"]').trigger('click');
  await nextTick();
  await flushPromises();
  expect(dropdown(w).exists()).toBe(true);
}

describe('OrganizationScopeSwitcher real-HeadlessUI close behaviour', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.name = 'dashboard';
    mockRoute.meta = {};
    mockRoute.params = {};
    mockOrganizations.value = [acme, personal];
    mockCurrentOrganization.value = acme;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('closes the dropdown when the gear/settings icon is clicked (the twin bug)', async () => {
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    // Gear for the non-current org avoids interference from the active row's
    // checkmark; org2 has an extid so its gear renders.
    await wrapper.get('[data-testid="org-menu-item-org2"] [aria-label="web.organizations.organization_settings"]')
      .trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/org/org2');
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  // The settings route requires owner or admin (requiresOrgRole: 'admin'); a
  // gear on any other row would only bounce the user to the dashboard.
  it('shows the gear only on rows whose settings page the user can open', async () => {
    mockOrganizations.value = [
      acme,
      { objid: 'o3', extid: 'org3', display_name: 'Admin Of', current_user_role: 'admin' },
      { objid: 'o4', extid: 'org4', display_name: 'Member Of', current_user_role: 'member' },
      { objid: 'o5', extid: 'org5', display_name: 'Role Unknown' },
    ];
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    const gear = (extid: string) =>
      wrapper.find(
        `[data-testid="org-menu-item-${extid}"] [aria-label="web.organizations.organization_settings"]`
      );
    expect(gear('org1').exists()).toBe(true);
    expect(gear('org3').exists()).toBe(true);
    expect(gear('org4').exists()).toBe(false);
    expect(gear('org5').exists()).toBe(false);
  });

  it('closes the dropdown when an organization row is selected', async () => {
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="org-menu-item-org2"]').trigger('click');
    await nextTick();
    await flushPromises();

    // The explicit choice goes through the server-syncing action (#4565),
    // not the tab-local setter.
    expect(mockSelectOrganization).toHaveBeenCalledWith(personal);
    expect(mockSetCurrentOrganization).not.toHaveBeenCalled();
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('closes the dropdown when the "Manage Organizations" link is clicked', async () => {
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="org-scope-manage-link"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/orgs');
    expect(dropdown(wrapper).exists()).toBe(false);
  });
});
