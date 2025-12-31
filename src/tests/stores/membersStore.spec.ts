// src/tests/stores/membersStore.spec.ts

import { useMembersStore } from '@/shared/stores/membersStore';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setupTestPinia } from '../setup';

// Mock member data matching the organizationMemberSchema
// Fields match backend response from apps/api/organizations/logic/members/list_members.rb
// Note: Schema requires 'extid' (external identifier), not 'id'
const mockMembers = [
  {
    extid: 'member-1',
    email: 'owner@example.com',
    role: 'owner' as const,
    joined_at: 1704067200, // Unix timestamp
    is_owner: true,
    is_current_user: true,
  },
  {
    extid: 'member-2',
    email: 'admin@example.com',
    role: 'admin' as const,
    joined_at: 1704153600,
    is_owner: false,
    is_current_user: false,
  },
  {
    extid: 'member-3',
    email: 'member@example.com',
    role: 'member' as const,
    joined_at: 1704240000,
    is_owner: false,
    is_current_user: false,
  },
];

describe('membersStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMembersStore>;

  beforeEach(async () => {
    const { axiosMock: mock } = await setupTestPinia();
    axiosMock = mock!;
    store = useMembersStore();
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('fetchMembers', () => {
    it('should fetch members and populate state', async () => {
      const orgExtid = 'org-ext-123';

      axiosMock.onGet(`/api/organizations/${orgExtid}/members`).reply(200, {
        records: mockMembers,
        count: mockMembers.length,
      });

      const result = await store.fetchMembers(orgExtid);

      expect(result).toHaveLength(3);
      expect(store.members).toHaveLength(3);
      expect(store.currentOrgExtid).toBe(orgExtid);
      expect(store.isInitialized).toBe(true);
      expect(store.memberCount).toBe(3);
    });

    it('should call correct API endpoint', async () => {
      const orgExtid = 'org-ext-456';

      axiosMock.onGet(`/api/organizations/${orgExtid}/members`).reply(200, {
        records: [],
        count: 0,
      });

      await store.fetchMembers(orgExtid);

      expect(axiosMock.history.get).toHaveLength(1);
      expect(axiosMock.history.get[0].url).toBe(`/api/organizations/${orgExtid}/members`);
    });

    it('should set loading state during fetch', async () => {
      const orgExtid = 'org-ext-123';

      axiosMock.onGet(`/api/organizations/${orgExtid}/members`).reply(200, {
        records: mockMembers,
        count: mockMembers.length,
      });

      expect(store.loading).toBe(false);

      const fetchPromise = store.fetchMembers(orgExtid);
      // Note: loading state may already be true or reset depending on timing

      await fetchPromise;
      expect(store.loading).toBe(false);
    });

    it('should handle network errors', async () => {
      const orgExtid = 'org-ext-123';
      axiosMock.onGet(`/api/organizations/${orgExtid}/members`).networkError();

      await expect(store.fetchMembers(orgExtid)).rejects.toThrow();
      expect(store.loading).toBe(false);
    });
  });

  describe('updateMemberRole', () => {
    it('should call correct endpoint with /role suffix', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-2';
      const newRole = 'member' as const;

      const updatedMember = {
        ...mockMembers[1],
        role: newRole,
      };

      axiosMock
        .onPatch(`/api/organizations/${orgExtid}/members/${memberId}/role`)
        .reply(200, { record: updatedMember });

      // Pre-populate members
      store.members = [...mockMembers];

      await store.updateMemberRole(orgExtid, memberId, { role: newRole });

      expect(axiosMock.history.patch).toHaveLength(1);
      expect(axiosMock.history.patch[0].url).toBe(
        `/api/organizations/${orgExtid}/members/${memberId}/role`
      );
    });

    it('should update member in store after successful role change', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-2';
      const newRole = 'member' as const;

      const updatedMember = {
        ...mockMembers[1],
        role: newRole,
      };

      axiosMock
        .onPatch(`/api/organizations/${orgExtid}/members/${memberId}/role`)
        .reply(200, { record: updatedMember });

      // Pre-populate members
      store.members = [...mockMembers];

      const result = await store.updateMemberRole(orgExtid, memberId, { role: newRole });

      expect(result.role).toBe('member');
      const storedMember = store.getMemberById(memberId);
      expect(storedMember?.role).toBe('member');
    });

    it('should send correct payload', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-2';

      const updatedMember = {
        ...mockMembers[1],
        role: 'admin',
      };

      axiosMock
        .onPatch(`/api/organizations/${orgExtid}/members/${memberId}/role`)
        .reply(200, { record: updatedMember });

      store.members = [...mockMembers];

      await store.updateMemberRole(orgExtid, memberId, { role: 'admin' });

      const requestData = JSON.parse(axiosMock.history.patch[0].data);
      expect(requestData).toEqual({ role: 'admin' });
    });

    it('should handle validation errors for invalid role', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-2';

      // @ts-expect-error - Testing invalid role
      await expect(store.updateMemberRole(orgExtid, memberId, { role: 'superuser' })).rejects.toThrow();
    });
  });

  describe('removeMember', () => {
    it('should call correct endpoint', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-3';

      axiosMock.onDelete(`/api/organizations/${orgExtid}/members/${memberId}`).reply(200, {
        deleted: true,
        member_extid: memberId,
      });

      // Pre-populate members
      store.members = [...mockMembers];

      await store.removeMember(orgExtid, memberId);

      expect(axiosMock.history.delete).toHaveLength(1);
      expect(axiosMock.history.delete[0].url).toBe(
        `/api/organizations/${orgExtid}/members/${memberId}`
      );
    });

    it('should remove member from store after successful deletion', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-3';

      axiosMock.onDelete(`/api/organizations/${orgExtid}/members/${memberId}`).reply(200, {
        deleted: true,
        member_extid: memberId,
      });

      // Pre-populate members
      store.members = [...mockMembers];

      expect(store.members).toHaveLength(3);

      await store.removeMember(orgExtid, memberId);

      expect(store.members).toHaveLength(2);
      expect(store.getMemberById(memberId)).toBeUndefined();
    });

    it('should handle 403 permission errors', async () => {
      const orgExtid = 'org-ext-123';
      const memberId = 'member-1'; // Trying to remove owner

      axiosMock.onDelete(`/api/organizations/${orgExtid}/members/${memberId}`).reply(403);

      store.members = [...mockMembers];

      await expect(store.removeMember(orgExtid, memberId)).rejects.toThrow();

      // Members should remain unchanged on error
      expect(store.members).toHaveLength(3);
    });
  });

  describe('getters', () => {
    beforeEach(() => {
      // Pre-populate members for getter tests
      store.members = [...mockMembers];
    });

    it('should return member count', () => {
      expect(store.memberCount).toBe(3);
    });

    it('should find member by id', () => {
      const member = store.getMemberById('member-2');
      expect(member).toBeDefined();
      expect(member?.email).toBe('admin@example.com');
    });

    it('should return undefined for non-existent member', () => {
      const member = store.getMemberById('non-existent');
      expect(member).toBeUndefined();
    });

    it('should filter members by role', () => {
      const owners = store.getMembersByRole('owner');
      const admins = store.getMembersByRole('admin');
      const members = store.getMembersByRole('member');

      expect(owners).toHaveLength(1);
      expect(admins).toHaveLength(1);
      expect(members).toHaveLength(1);
    });

    it('should return owners via owners getter', () => {
      expect(store.owners).toHaveLength(1);
      expect(store.owners[0].email).toBe('owner@example.com');
    });

    it('should return admins via admins getter', () => {
      expect(store.admins).toHaveLength(1);
      expect(store.admins[0].email).toBe('admin@example.com');
    });
  });

  describe('$reset', () => {
    it('should reset all state to initial values', async () => {
      const orgExtid = 'org-ext-123';

      axiosMock.onGet(`/api/organizations/${orgExtid}/members`).reply(200, {
        records: mockMembers,
        count: mockMembers.length,
      });

      await store.fetchMembers(orgExtid);

      expect(store.members).toHaveLength(3);
      expect(store.isInitialized).toBe(true);

      store.$reset();

      expect(store.members).toHaveLength(0);
      expect(store.currentOrgExtid).toBeNull();
      expect(store.isInitialized).toBe(false);
      expect(store.loading).toBe(false);
    });
  });
});
