import { flushPromises, mount, RouterLinkStub, type VueWrapper } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = { post: vi.fn(), delete: vi.fn() };
const notify = vi.hoisted(() => vi.fn());
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));
vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => ({ show: notify }),
}));

import OrganizationMembersSection from '@/apps/admin/components/organizations/OrganizationMembersSection.vue';
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import type { ColonelOrganizationDetailMember } from '@/schemas/api/internal/responses/colonel-organizations';
import { createTestI18n } from '@tests/setup';

const ORG_URL = '/api/colonel/organizations/on_first';
const member = (): ColonelOrganizationDetailMember => ({
  extid: 'mem_2',
  email: 'bob@example.com',
  role: 'member',
  status: 'active',
  is_owner: false,
  joined_at: new Date(1700000100 * 1000),
  created: new Date(1700000100 * 1000),
});

const dialogOpen = (w: VueWrapper) =>
  w.findAllComponents({ name: 'AdminConfirmDialog' }).map((dialog) => dialog.props('open'));
const button = (w: VueWrapper, verb: 'change-role' | 'remove') =>
  w.find(`[data-testid="member-${verb}-mem_2"]`);

describe('OrganizationMembersSection — elevation openers', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    __resetColonelElevationState({ statusRead: true });
    wrapper = mount(OrganizationMembersSection, {
      props: { orgUrl: ORG_URL, orgName: 'First', members: [member()] },
      global: {
        plugins: [createTestI18n()],
        stubs: {
          AdminConfirmDialog: true,
          RevealEmail: true,
          OIcon: true,
          RouterLink: RouterLinkStub,
        },
      },
    });
  });

  afterEach(() => {
    wrapper.unmount();
    __resetColonelElevationState();
  });

  it.each(['change-role', 'remove'] as const)('shares the opener lock for %s', async (first) => {
    const second = first === 'change-role' ? 'remove' : 'change-role';
    await button(wrapper, first).trigger('click');
    await flushPromises();
    expect(useColonelElevation().promptOpen.value).toBe(true);
    expect(button(wrapper, second).attributes('disabled')).toBeDefined();
    await button(wrapper, second).trigger('click');
    useColonelElevation().resolvePrompt(true);
    await flushPromises();

    const expected = first === 'change-role' ? [true, false] : [false, true];
    expect(dialogOpen(wrapper)).toEqual(expected);
    // The opener lock has released; the dialog guard must still refuse.
    await button(wrapper, second).trigger('click');
    await flushPromises();
    expect(dialogOpen(wrapper)).toEqual(expected);
    expect(useColonelElevation().promptOpen.value).toBe(false);
  });

  it.each([
    ['change-role', false],
    ['change-role', true],
    ['remove', false],
    ['remove', true],
  ] as const)(
    'drops %s after the organization changes (returns to original: %s)',
    async (verb, returnToOriginal) => {
      await button(wrapper, verb).trigger('click');
      await flushPromises();
      expect(useColonelElevation().promptOpen.value).toBe(true);
      await wrapper.setProps({ orgUrl: '/api/colonel/organizations/on_other' });
      if (returnToOriginal) await wrapper.setProps({ orgUrl: ORG_URL });
      useColonelElevation().resolvePrompt(true);
      await flushPromises();

      expect(dialogOpen(wrapper)).toEqual([false, false]);
      expect(mockApi.post).not.toHaveBeenCalled();
      expect(mockApi.delete).not.toHaveBeenCalled();
    }
  );

  it.each(['change-role', 'remove'] as const)(
    'rechecks membership eligibility for %s after elevation',
    async (verb) => {
      await button(wrapper, verb).trigger('click');
      await flushPromises();
      await wrapper.setProps({ members: [{ ...member(), role: 'owner' }] });
      useColonelElevation().resolvePrompt(true);
      await flushPromises();
      expect(dialogOpen(wrapper)).toEqual([false, false]);
    }
  );
});

// A failed default_org_id cleanup does not undo the removal (#4860): the
// toast says so instead of reporting a clean removal.
describe('OrganizationMembersSection — remove outcome', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    __resetColonelElevationState({ statusRead: true });
    wrapper = mount(OrganizationMembersSection, {
      props: { orgUrl: ORG_URL, orgName: 'First', members: [member()] },
      global: {
        plugins: [createTestI18n()],
        stubs: {
          AdminConfirmDialog: true,
          RevealEmail: true,
          OIcon: true,
          RouterLink: RouterLinkStub,
        },
      },
    });
  });

  afterEach(() => {
    wrapper.unmount();
    __resetColonelElevationState();
  });

  async function removeWith(defaultOrgCleanup: string) {
    mockApi.delete.mockResolvedValue({
      data: {
        record: { org_id: 'on_first', member_id: 'mem_2', status: 'success', role: 'member' },
        details: { default_org_cleanup: defaultOrgCleanup },
      },
    });
    await button(wrapper, 'remove').trigger('click');
    await flushPromises();
    useColonelElevation().resolvePrompt(true);
    await flushPromises();
    wrapper.findAllComponents({ name: 'AdminConfirmDialog' })[1].vm.$emit('confirm');
    await flushPromises();
  }

  it('warns when the default organization may still point to the org', async () => {
    await removeWith('failed');

    expect(mockApi.delete).toHaveBeenCalledOnce();
    expect(notify).toHaveBeenCalledOnce();
    expect(notify).toHaveBeenCalledWith(
      'web.admin.organizations.members.remove.defaultOrgCleanupFailed',
      'warning'
    );
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('reports a clean removal otherwise', async () => {
    await removeWith('unchanged');

    expect(notify).toHaveBeenCalledOnce();
    expect(notify).toHaveBeenCalledWith(
      'web.admin.organizations.members.remove.success',
      'success'
    );
  });
});
