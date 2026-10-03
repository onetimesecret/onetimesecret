// src/tests/composables/useMembersManager.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';

import { useMembersManager } from '@/shared/composables/useMembersManager';
import { lenientExtIdSchema } from '@/types/identifiers';
import type { OrganizationMember, OrganizationRole } from '@/types/organization';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const mockRemoveMember = vi.fn();
const mockMembers = ref<OrganizationMember[]>([]);
const mockMembersStore = reactive({
  members: mockMembers,
  loading: ref(false),
  memberCount: 0,
  getMemberById: (id: string) => mockMembers.value.find((m) => m.extid === id),
  removeMember: mockRemoveMember,
  updateMemberRole: vi.fn(),
  fetchMembers: vi.fn(),
});
const mockShow = vi.fn();
vi.mock('@/shared/stores', () => ({
  useMembersStore: () => mockMembersStore,
  useNotificationsStore: () => ({ show: mockShow }),
}));

const mockCurrentOrganization = ref<{ current_user_role?: OrganizationRole } | null>(null);
const mockOrgStore = reactive({ currentOrganization: mockCurrentOrganization });
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrgStore,
}));

const member = (role: OrganizationRole, id = `mem_${role}`): OrganizationMember => ({
  extid: lenientExtIdSchema.parse(id),
  email: `${role}@example.com`,
  role,
  joined_at: 1704067200,
  is_owner: role === 'owner',
  is_current_user: false,
});

describe('useMembersManager', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockMembers.value = [];
    mockCurrentOrganization.value = null;
  });

  // The removal rules mirror OrganizationAPI RemoveMember#validate_removal!
  describe('canModifyMember', () => {
    it.each<[OrganizationRole, OrganizationRole, boolean]>([
      ['owner', 'admin', true],
      ['owner', 'member', true],
      ['owner', 'owner', false],
      ['admin', 'member', true],
      ['admin', 'admin', false],
      ['admin', 'owner', false],
      ['member', 'member', false],
      ['member', 'admin', false],
    ])('%s viewing a %s row → %s', (viewer, target, expected) => {
      mockCurrentOrganization.value = { current_user_role: viewer };
      const { canModifyMember } = useMembersManager();

      expect(canModifyMember(member(target))).toBe(expected);
    });

    it('is false without an organization role', () => {
      const { canModifyMember } = useMembersManager();

      expect(canModifyMember(member('member'))).toBe(false);
    });
  });

  describe('canChangeRole', () => {
    it.each<[OrganizationRole, OrganizationRole, boolean]>([
      ['owner', 'admin', true],
      ['owner', 'member', true],
      ['owner', 'owner', false],
      ['admin', 'member', false],
      ['admin', 'admin', false],
    ])('%s changing a %s → %s', (viewer, target, expected) => {
      mockCurrentOrganization.value = { current_user_role: viewer };
      const { canChangeRole } = useMembersManager();

      expect(canChangeRole(member(target))).toBe(expected);
    });
  });

  describe('removeMember', () => {
    it('refuses an admin removing another admin without calling the API', async () => {
      mockCurrentOrganization.value = { current_user_role: 'admin' };
      const target = member('admin');
      mockMembers.value = [target];
      const { removeMember } = useMembersManager();

      const result = await removeMember('on1abc123', target.extid);

      expect(result).toBeUndefined();
      expect(mockRemoveMember).not.toHaveBeenCalled();
      expect(mockShow).toHaveBeenCalledWith(
        'web.organizations.members.insufficient_permissions',
        'error',
        'top'
      );
    });

    it('lets an admin remove a member', async () => {
      mockCurrentOrganization.value = { current_user_role: 'admin' };
      const target = member('member');
      mockMembers.value = [target];
      mockRemoveMember.mockResolvedValue(undefined);
      const { removeMember } = useMembersManager();

      const result = await removeMember('on1abc123', target.extid);

      expect(result).toBe(true);
      expect(mockRemoveMember).toHaveBeenCalledWith('on1abc123', target.extid);
    });
  });
});
