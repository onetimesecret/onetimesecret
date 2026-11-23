import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import { createTestI18n } from '@tests/setup';

const routeState = { path: '/billing/on1abc123/overview', params: { extid: 'on1abc123' } };
const storeState = {
  organizations: [] as Array<{ extid: string; current_user_role: string | null }>,
  currentOrganization: null as { extid: string; current_user_role: string | null } | null,
};

vi.mock('vue-router', () => ({ useRoute: () => routeState }));
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    getOrganizationByExtid: (extid: string) =>
      storeState.organizations.find((org) => org.extid === extid),
    get currentOrganization() { return storeState.currentOrganization; },
  }),
}));
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { template: '<span />' },
}));

const routerLinkStub = {
  template: '<a :href="to"><slot /></a>',
  props: ['to'],
};

describe('BillingLayout', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    routeState.params.extid = 'on1abc123';
    storeState.organizations = [];
    storeState.currentOrganization = null;
  });

  afterEach(() => wrapper?.unmount());

  const mountLayout = () => mount(BillingLayout, {
    global: { plugins: [createTestI18n()], stubs: { RouterLink: routerLinkStub } },
  });

  it('shows invoices for the owner of the organization in the route', () => {
    storeState.organizations = [{ extid: 'on1abc123', current_user_role: 'owner' }];
    wrapper = mountLayout();

    expect(wrapper.find('a[href="/billing/on1abc123/invoices"]').exists()).toBe(true);
  });

  it('hides invoices from a member while keeping overview and plans visible', () => {
    storeState.organizations = [{ extid: 'on1abc123', current_user_role: 'member' }];
    wrapper = mountLayout();

    expect(wrapper.find('a[href="/billing/on1abc123/invoices"]').exists()).toBe(false);
    expect(wrapper.find('a[href="/billing/on1abc123/overview"]').exists()).toBe(true);
    expect(wrapper.find('a[href="/billing/on1abc123/plans"]').exists()).toBe(true);
  });

  it('does not use the owner role of a different current organization', () => {
    storeState.currentOrganization = { extid: 'on2def456', current_user_role: 'owner' };
    wrapper = mountLayout();

    expect(wrapper.find('a[href="/billing/on1abc123/invoices"]').exists()).toBe(false);
  });
});
