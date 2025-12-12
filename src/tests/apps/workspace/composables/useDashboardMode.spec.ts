// src/tests/apps/workspace/composables/useDashboardMode.spec.ts

/**
 * Unit tests for useDashboardMode composable
 *
 * This composable determines dashboard variant based on:
 * - Team management entitlements (from organization)
 * - Number of teams (from team store)
 * - Standalone vs hosted mode (from WindowService)
 *
 * Testing strategy:
 * - Test variant logic with different team counts and entitlements
 * - Test transition key format
 * - Test reactive updates when store state changes
 *
 * Note: These tests work with stores directly to test the composition logic.
 * Integration testing of the actual dashboard rendering happens in E2E tests.
 */

import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';
import { useDashboardMode } from '@/apps/workspace/composables/useDashboardMode';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useTeamStore } from '@/shared/stores/teamStore';
import { setupTestPinia } from '../../../setup';
import { setupWindowState } from '../../../setupWindow';
import type { Organization } from '@/types/organization';
import type { TeamWithRole } from '@/schemas/models/team';
import { TeamRole } from '@/schemas/models/team';

// Mock WindowService - set billing_enabled based on test needs
const mockWindowService = {
  billingEnabled: false, // Start with standalone mode (simpler)
};

vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn((key: string) => {
      if (key === 'billing_enabled') return mockWindowService.billingEnabled;
      return null;
    }),
  },
}));

describe('useDashboardMode', () => {
  const mockOrganization: Organization = {
    id: 'org-123',
    extid: 'org-extid-123',
    display_name: 'Test Organization',
    is_default: true,
    entitlements: ['CREATE_TEAM'],
    limits: {
      teams: 5,
      members_per_team: 10,
      custom_domains: 1,
    },
    planid: 'multi_team_v1',
    created: new Date('2024-01-01'),
    updated: new Date('2024-01-01'),
  };

  const mockTeam: TeamWithRole = {
    identifier: 'team-123-identifier',
    objid: 'team-123-objid',
    extid: 'team-123',
    display_name: 'Test Team',
    description: 'A test team',
    owner_id: 'user-123',
    org_id: null,
    member_count: 3,
    is_default: false,
    current_user_role: TeamRole.OWNER,
    feature_flags: {},
    created: new Date('2024-01-01'),
    updated: new Date('2024-01-01'),
  };

  beforeEach(async () => {
    mockWindowService.billingEnabled = false; // Standalone mode (simpler for testing)
    await setupTestPinia({ mockAxios: false });
    vi.stubGlobal('window', setupWindowState());

    // Mock fetchTeams to avoid actual API calls
    const teamStore = useTeamStore();
    vi.spyOn(teamStore, 'fetchTeams').mockResolvedValue([]);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  describe('Variant computation in standalone mode', () => {
    it('returns empty when 0 teams', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('empty');
    });

    it('returns single when has 1 team', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [mockTeam];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('single');
    });

    it('returns multi when has 2 teams', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [
        mockTeam,
        { ...mockTeam, extid: 'team-456', display_name: 'Second Team' },
      ];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('multi');
    });

    it('returns multi when has 3+ teams', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [
        mockTeam,
        { ...mockTeam, extid: 'team-456', display_name: 'Second Team' },
        { ...mockTeam, extid: 'team-789', display_name: 'Third Team' },
      ];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('multi');
    });
  });

  describe('Standalone mode behavior', () => {
    it('has team entitlement even with empty entitlements array', () => {
      const orgStore = useOrganizationStore();

      orgStore.currentOrganization = {
        ...mockOrganization,
        entitlements: [], // Empty in standalone mode still grants access
      };

      const { hasTeamEntitlement } = useDashboardMode();

      expect(hasTeamEntitlement.value).toBe(true);
    });

    it('has team entitlement with null organization', () => {
      const orgStore = useOrganizationStore();
      orgStore.currentOrganization = null;

      const { hasTeamEntitlement } = useDashboardMode();

      expect(hasTeamEntitlement.value).toBe(true);
    });
  });

  describe('Transition key', () => {
    it('includes standalone prefix in standalone mode', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [];

      const { transitionKey } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(transitionKey.value).toBe('standalone-empty');
    });

    it('updates when variant changes via team count', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [];

      const { transitionKey } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(transitionKey.value).toBe('standalone-empty');

      // Add team
      teamStore.teams = [mockTeam];
      await nextTick();

      expect(transitionKey.value).toBe('standalone-single');
    });

    it('updates when variant changes from single to multi', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [mockTeam];

      const { transitionKey } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(transitionKey.value).toBe('standalone-single');

      // Add second team
      teamStore.teams = [
        mockTeam,
        { ...mockTeam, extid: 'team-456', display_name: 'Second Team' },
      ];
      await nextTick();

      expect(transitionKey.value).toBe('standalone-multi');
    });
  });

  describe('Reactive updates', () => {
    it('updates variant when teams are added', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('empty');

      // Add teams
      teamStore.teams = [mockTeam];
      await nextTick();

      expect(variant.value).toBe('single');

      teamStore.teams = [
        mockTeam,
        { ...mockTeam, extid: 'team-456', display_name: 'Second Team' },
      ];
      await nextTick();

      expect(variant.value).toBe('multi');
    });

    it('updates variant when teams are removed', async () => {
      const orgStore = useOrganizationStore();
      const teamStore = useTeamStore();

      orgStore.currentOrganization = mockOrganization;
      teamStore.teams = [
        mockTeam,
        { ...mockTeam, extid: 'team-456', display_name: 'Second Team' },
      ];

      const { variant } = useDashboardMode();

      await nextTick();
      await nextTick();

      expect(variant.value).toBe('multi');

      // Remove team
      teamStore.teams = [mockTeam];
      await nextTick();

      expect(variant.value).toBe('single');

      // Remove all teams
      teamStore.teams = [];
      await nextTick();

      expect(variant.value).toBe('empty');
    });
  });
});
