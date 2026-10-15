// src/tests/apps/workspace/components/navigation/OrganizationScopeSwitcher.spec.ts

/**
 * Switching organizations from the Organization Scope Switcher.
 *
 * A switch that navigates changes the organization only once the page has let
 * the navigation through. A page's unsaved-changes guard can refuse it; the
 * page then still shows the previous organization, and an organization
 * switched early would leave the switcher, the domain list and the API's
 * organization header naming one the page does not show.
 *
 * The router is real (memory history) so the ordering under test is the
 * router's own: leave and update guards, then beforeResolve, then the
 * destination renders. Only the component's data dependencies are stubbed.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, reactive, ref } from 'vue';
import { createMemoryHistory, createRouter, type Router } from 'vue-router';
import OrganizationScopeSwitcher from '@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue';

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

// The component reads the route's meta and name through useRoute and
// navigates through useRouter; both come from here (read when the component
// calls them, after this module has initialized). Everything else in
// vue-router stays real so the specs can build a real router.
const mockRoute = reactive<{
  name?: string;
  meta: Record<string, unknown>;
  params: Record<string, unknown>;
}>({ name: 'Dashboard', meta: {}, params: {} });
let router: Router;
vi.mock('vue-router', async (importOriginal) => ({
  ...(await importOriginal<typeof import('vue-router')>()),
  useRoute: () => mockRoute,
  useRouter: () => router,
}));

type TestOrg = {
  objid: string;
  extid?: string;
  display_name: string;
  is_current_user_default?: boolean;
  current_user_role?: 'owner' | 'admin' | 'member' | null;
};

const acme: TestOrg = {
  objid: 'o1',
  extid: 'org1',
  display_name: 'Acme Inc',
  current_user_role: 'owner',
};
const globex: TestOrg = {
  objid: 'o2',
  extid: 'org2',
  display_name: 'Globex',
  current_user_role: 'owner',
};

const mockOrganizations = ref<TestOrg[]>([acme, globex]);
const mockCurrentOrganization = ref<TestOrg | null>(acme);
const mockSelectOrganization = vi.fn(async () => undefined);
const mockOrgStore = reactive({
  organizations: mockOrganizations,
  currentOrganization: mockCurrentOrganization,
  hasOrganizations: true,
  setCurrentOrganization: vi.fn(),
  selectOrganization: mockSelectOrganization,
});
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrgStore,
}));

const Page = { render: () => null };

async function selectGlobex(wrapper: VueWrapper) {
  await wrapper.get('[data-testid="org-scope-switcher-trigger"]').trigger('click');
  await nextTick();
  await flushPromises();
  await wrapper.get('[data-testid="org-menu-item-org2"]').trigger('click');
  await flushPromises();
}

describe('OrganizationScopeSwitcher switching organizations', () => {
  let wrapper: VueWrapper;

  beforeEach(async () => {
    vi.clearAllMocks();
    mockOrganizations.value = [acme, globex];
    mockCurrentOrganization.value = acme;
    mockRoute.name = 'Dashboard';
    mockRoute.meta = { scopesAvailable: { onOrgSwitch: '/dashboard' } };
    mockRoute.params = {};

    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/here', component: Page },
        { path: '/elsewhere', component: Page },
        { path: '/dashboard', name: 'Dashboard', component: Page },
        { path: '/org/:extid', name: 'OrganizationSettings', component: Page },
      ],
    });
    await router.push('/here');
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('switches the organization once the navigation is let through, before the destination renders', async () => {
    let selectedWhenLanding: number | null = null;
    router.afterEach(() => {
      selectedWhenLanding = mockSelectOrganization.mock.calls.length;
    });
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });

    await selectGlobex(wrapper);

    expect(router.currentRoute.value.path).toBe('/dashboard');
    expect(mockSelectOrganization).toHaveBeenCalledTimes(1);
    expect(mockSelectOrganization).toHaveBeenCalledWith(globex);
    // Already switched when the navigation landed (afterEach), not after.
    expect(selectedWhenLanding).toBe(1);
  });

  it('leaves the organization as it is when the page refuses the navigation', async () => {
    // Stands in for a page's unsaved-changes guard: it runs before beforeResolve.
    router.beforeEach((to) => to.path !== '/dashboard');
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });

    await selectGlobex(wrapper);

    expect(router.currentRoute.value.path).toBe('/here');
    expect(mockSelectOrganization).not.toHaveBeenCalled();

    // The one-shot hook is gone: a later navigation does not switch either.
    await router.push('/elsewhere');
    expect(router.currentRoute.value.path).toBe('/elsewhere');
    expect(mockSelectOrganization).not.toHaveBeenCalled();
  });

  it('switches the organization when the page is already where the switch goes', async () => {
    await router.push('/dashboard');
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });

    await selectGlobex(wrapper);

    expect(router.currentRoute.value.path).toBe('/dashboard');
    expect(mockSelectOrganization).toHaveBeenCalledWith(globex);
  });

  it('switches the organization at once when the route configures no navigation', async () => {
    mockRoute.meta = {};
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });

    await selectGlobex(wrapper);

    expect(router.currentRoute.value.path).toBe('/here');
    expect(mockSelectOrganization).toHaveBeenCalledWith(globex);
  });

  it('stays on the same route with the new extid for an onOrgSwitch of same', async () => {
    await router.push('/org/org1');
    mockRoute.name = 'OrganizationSettings';
    mockRoute.params = { extid: 'org1' };
    mockRoute.meta = { scopesAvailable: { onOrgSwitch: 'same' } };
    wrapper = mount(OrganizationScopeSwitcher, { attachTo: document.body });

    await selectGlobex(wrapper);

    expect(router.currentRoute.value.path).toBe('/org/org2');
    expect(mockSelectOrganization).toHaveBeenCalledWith(globex);
  });
});
