// src/tests/stores/teamStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

import { useTeamStore } from '@/stores/teamStore';
import type { TeamWithRole } from '@/types/team';
import { TeamRole } from '@/types/team';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type AxiosMockAdapter from 'axios-mock-adapter';

describe('Team Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let store: ReturnType<typeof useTeamStore>;

  const mockTeam: TeamWithRole = {
    id: 'team-123',
    name: 'Test Team',
    description: 'A test team',
    owner_id: 'user-123',
    member_count: 3,
    current_user_role: TeamRole.OWNER,
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  };

  const mockMember = {
    id: 'member-123',
    team_id: 'team-123',
    user_id: 'user-456',
    email: 'member@example.com',
    role: TeamRole.MEMBER,
    status: 'active' as const,
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  };

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;

    vi.stubGlobal('window', setupWindowState());
    store = useTeamStore();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock?.reset();
  });

  describe('Initialization', () => {
    it('initializes with empty state', () => {
      store.init();

      expect(store.teams).toEqual([]);
      expect(store.activeTeam).toBeNull();
      expect(store.members).toEqual([]);
      expect(store.isInitialized).toBe(true);
    });

    it('prevents double initialization', () => {
      const result1 = store.init();
      const result2 = store.init();

      expect(result1).toBe(result2);
      expect(store.isInitialized).toBe(true);
    });
  });

  describe('Fetching teams', () => {
    it('fetches all teams successfully', async () => {
      axiosMock?.onGet('/api/teams').reply(200, {
        teams: [mockTeam],
      });

      await store.fetchTeams();

      expect(store.teams).toHaveLength(1);
      expect(store.teams[0]).toEqual(mockTeam);
      expect(store.hasTeams).toBe(true);
    });

    it('handles empty teams response', async () => {
      axiosMock?.onGet('/api/teams').reply(200, {
        teams: [],
      });

      await store.fetchTeams();

      expect(store.teams).toEqual([]);
      expect(store.hasTeams).toBe(false);
    });

    it('fetches a single team by ID', async () => {
      axiosMock?.onGet('/api/teams/team-123').reply(200, {
        team: mockTeam,
      });

      const team = await store.fetchTeam('team-123');

      expect(team).toEqual(mockTeam);
      expect(store.activeTeam).toEqual(mockTeam);
    });
  });

  describe('Creating teams', () => {
    it('creates a new team successfully', async () => {
      const newTeamPayload = {
        name: 'New Team',
        description: 'A new test team',
      };

      axiosMock?.onPost('/api/teams').reply(200, {
        team: mockTeam,
      });

      const team = await store.createTeam(newTeamPayload);

      expect(team).toEqual(mockTeam);
      expect(store.teams).toContain(mockTeam);
      expect(store.activeTeam).toEqual(mockTeam);
    });
  });

  describe('Updating teams', () => {
    beforeEach(async () => {
      store.teams = [mockTeam];
      store.activeTeam = mockTeam;
    });

    it('updates a team successfully', async () => {
      const updates = {
        name: 'Updated Team Name',
      };

      const updatedTeam = { ...mockTeam, ...updates };

      axiosMock?.onPatch('/api/teams/team-123').reply(200, {
        team: updatedTeam,
      });

      const result = await store.updateTeam('team-123', updates);

      expect(result.name).toBe('Updated Team Name');
      expect(store.teams[0].name).toBe('Updated Team Name');
      expect(store.activeTeam?.name).toBe('Updated Team Name');
    });
  });

  describe('Deleting teams', () => {
    beforeEach(() => {
      store.teams = [mockTeam];
      store.activeTeam = mockTeam;
    });

    it('deletes a team successfully', async () => {
      axiosMock?.onDelete('/api/teams/team-123').reply(200);

      await store.deleteTeam('team-123');

      expect(store.teams).toEqual([]);
      expect(store.activeTeam).toBeNull();
    });
  });

  describe('Managing members', () => {
    beforeEach(async () => {
      store.activeTeam = mockTeam;
    });

    it('fetches team members', async () => {
      axiosMock?.onGet('/api/teams/team-123/members').reply(200, {
        members: [mockMember],
      });

      const members = await store.fetchMembers('team-123');

      expect(members).toHaveLength(1);
      expect(members[0]).toEqual(mockMember);
      expect(store.members).toEqual([mockMember]);
    });

    it('invites a new member', async () => {
      const invitePayload = {
        email: 'newmember@example.com',
        role: TeamRole.MEMBER,
      };

      const newMember = { ...mockMember, email: 'newmember@example.com' };

      axiosMock?.onPost('/api/teams/team-123/members').reply(200, {
        member: newMember,
      });

      const member = await store.inviteMember('team-123', invitePayload);

      expect(member.email).toBe('newmember@example.com');
      expect(store.members).toContain(newMember);
    });

    it('updates a member role', async () => {
      store.members = [mockMember];

      const updatedMember = { ...mockMember, role: TeamRole.ADMIN };

      axiosMock?.onPatch('/api/teams/team-123/members/member-123').reply(200, {
        member: updatedMember,
      });

      const result = await store.updateMemberRole('team-123', 'member-123', {
        role: TeamRole.ADMIN,
      });

      expect(result.role).toBe(TeamRole.ADMIN);
      expect(store.members[0].role).toBe(TeamRole.ADMIN);
    });

    it('removes a member', async () => {
      store.members = [mockMember];

      axiosMock?.onDelete('/api/teams/team-123/members/member-123').reply(200);

      await store.removeMember('team-123', 'member-123');

      expect(store.members).toEqual([]);
    });
  });

  describe('Getters', () => {
    it('computes hasTeams correctly', () => {
      expect(store.hasTeams).toBe(false);

      store.teams = [mockTeam];
      expect(store.hasTeams).toBe(true);
    });

    it('computes isTeamOwner correctly', () => {
      expect(store.isTeamOwner).toBe(false);

      store.activeTeam = mockTeam;
      expect(store.isTeamOwner).toBe(true);

      store.activeTeam = { ...mockTeam, current_user_role: TeamRole.ADMIN };
      expect(store.isTeamOwner).toBe(false);
    });

    it('computes isTeamAdmin correctly', () => {
      expect(store.isTeamAdmin).toBe(false);

      store.activeTeam = { ...mockTeam, current_user_role: TeamRole.OWNER };
      expect(store.isTeamAdmin).toBe(true);

      store.activeTeam = { ...mockTeam, current_user_role: TeamRole.ADMIN };
      expect(store.isTeamAdmin).toBe(true);

      store.activeTeam = { ...mockTeam, current_user_role: TeamRole.MEMBER };
      expect(store.isTeamAdmin).toBe(false);
    });

    it('finds team by ID', () => {
      store.teams = [mockTeam];

      const found = store.getTeamById('team-123');
      expect(found).toEqual(mockTeam);

      const notFound = store.getTeamById('nonexistent');
      expect(notFound).toBeUndefined();
    });
  });

  describe('Reset functionality', () => {
    it('resets store to initial state', () => {
      store.teams = [mockTeam];
      store.activeTeam = mockTeam;
      store.members = [mockMember];

      store.$reset();

      expect(store.teams).toEqual([]);
      expect(store.activeTeam).toBeNull();
      expect(store.members).toEqual([]);
      expect(store._initialized).toBe(false);
    });
  });
});
