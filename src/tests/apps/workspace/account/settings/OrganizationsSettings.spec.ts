// src/tests/apps/workspace/account/settings/OrganizationsSettings.spec.ts

/**
 * The /orgs list: the "Default" badge and the "Make default" action.
 *
 * The badge follows `is_current_user_default` (this user's default), not
 * `is_default` (the OWNER's auto-created workspace), which a member of the
 * company's default workspace sees set too. The action runs through the real
 * organization store against the shared axios mock, so the request body, the
 * refetch, and the badge moving are all observed end to end.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createTestI18n } from '@tests/setup';
import { createSharedApiInstance, getGlobalAxiosMock } from '../../../../setup-stores';

const showMock = vi.fn();
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: showMock }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class'],
  },
}));

import OrganizationsSettings from '@/apps/workspace/account/settings/OrganizationsSettings.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

const i18n = createTestI18n();

const LIST_URL = '/api/organizations';
const DEFAULT_URL = '/api/account/update-default-organization';

/** An organizations-list wire record */
const orgRecord = (objid: string, extid: string, over: Record<string, unknown> = {}) => ({
  objid,
  extid,
  display_name: objid,
  description: null,
  owner_id: 'cust-owner',
  contact_email: null,
  planid: 'free_v1',
  is_default: false,
  is_current_user_default: false,
  current_user_role: 'owner',
  created: 1700000000,
  updated: 1700000000,
  ...over,
});

// The reported setup: the user's own free default workspace, and the
// company's paid org they were invited into, which is the COMPANY ADMIN's
// default workspace (is_default true for every member).
const own = orgRecord('org-own', 'on_own', { is_default: true, is_current_user_default: true });
const company = orgRecord('org-company', 'on_company', {
  is_default: true,
  planid: 'identity_plus_v1',
  current_user_role: 'member',
});

describe('OrganizationsSettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    getGlobalAxiosMock().reset();
    vi.clearAllMocks();
  });

  afterEach(() => {
    wrapper?.unmount();
    getGlobalAxiosMock().reset();
  });

  const mountPage = async () => {
    wrapper = mount(OrganizationsSettings, {
      global: {
        plugins: [i18n],
        provide: { api: createSharedApiInstance() },
        stubs: { CreateOrganizationModal: true },
      },
    });
    await flushPromises();
    return wrapper;
  };

  const badge = (extid: string) => wrapper.find(`[data-testid="org-default-badge-${extid}"]`);
  const makeDefault = (extid: string) => wrapper.find(`[data-testid="org-make-default-${extid}"]`);

  it("badges this user's default, and offers Make default on the others", async () => {
    getGlobalAxiosMock()
      .onGet(LIST_URL)
      .reply(200, { records: [own, company], count: 2 });
    await mountPage();

    expect(badge('on_own').exists()).toBe(true);
    expect(makeDefault('on_own').exists()).toBe(false);
    // is_default alone (the company admin's workspace) earns no badge
    expect(badge('on_company').exists()).toBe(false);
    expect(makeDefault('on_company').exists()).toBe(true);
    expect(makeDefault('on_company').attributes('aria-label')).toBe(
      'web.organizations.make_default_label'
    );
  });

  it('makes an org the default: posts its objid, moves the badge, and makes it current', async () => {
    const axiosMock = getGlobalAxiosMock();
    axiosMock.onGet(LIST_URL).replyOnce(200, { records: [own, company], count: 2 });
    axiosMock.onPost(DEFAULT_URL).reply(200, {
      organization_id: 'org-company',
      previous_default_organization_id: 'org-own',
    });
    axiosMock.onGet(LIST_URL).reply(200, {
      records: [
        { ...own, is_current_user_default: false },
        { ...company, is_current_user_default: true },
      ],
      count: 2,
    });
    await mountPage();

    await makeDefault('on_company').trigger('click');
    await flushPromises();

    expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({
      organization_id: 'org-company',
    });
    expect(badge('on_company').exists()).toBe(true);
    expect(badge('on_own').exists()).toBe(false);
    expect(makeDefault('on_own').exists()).toBe(true);
    expect(useOrganizationStore().currentOrganization?.objid).toBe('org-company');
    expect(showMock).toHaveBeenCalledWith(
      'web.organizations.make_default_success',
      'success',
      'top'
    );
  });

  it('reports a refusal and leaves the badge where it was', async () => {
    const axiosMock = getGlobalAxiosMock();
    axiosMock.onGet(LIST_URL).reply(200, { records: [own, company], count: 2 });
    axiosMock.onPost(DEFAULT_URL).reply(422, { message: 'Invalid organization' });
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    await mountPage();

    await makeDefault('on_company').trigger('click');
    await flushPromises();

    expect(showMock).toHaveBeenCalledWith('web.organizations.make_default_error', 'error', 'top');
    expect(badge('on_own').exists()).toBe(true);
    expect(makeDefault('on_company').exists()).toBe(true);
    expect(makeDefault('on_company').attributes('disabled')).toBeUndefined();
    errorSpy.mockRestore();
  });
});
