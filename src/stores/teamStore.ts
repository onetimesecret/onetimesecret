// src/stores/teamStore.ts

import type {
  CreateTeamPayload,
  InviteMemberPayload,
  TeamMember,
  TeamWithRole,
  UpdateMemberRolePayload,
  UpdateTeamPayload,
} from '@/types/team';
import {
  createTeamPayloadSchema,
  inviteMemberPayloadSchema,
  teamMemberSchema,
  teamWithRoleSchema,
  updateMemberRolePayloadSchema,
  updateTeamPayloadSchema,
} from '@/types/team';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, inject, ref } from 'vue';
import { z } from 'zod';

const teamsResponseSchema = z.object({
  teams: z.array(teamWithRoleSchema),
});

const teamResponseSchema = z.object({
  team: teamWithRoleSchema,
});

const membersResponseSchema = z.object({
  members: z.array(teamMemberSchema),
});

const memberResponseSchema = z.object({
  member: teamMemberSchema,
});

/* eslint-disable max-lines-per-function */
export const useTeamStore = defineStore('team', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const teams = ref<TeamWithRole[]>([]);
  const activeTeam = ref<TeamWithRole | null>(null);
  const members = ref<TeamMember[]>([]);
  const _initialized = ref(false);
  const loading = ref(false);
  const abortController = ref<AbortController | null>(null);

  // Getters
  const hasTeams = computed(() => teams.value.length > 0);

  const isTeamOwner = computed(() => {
    if (!activeTeam.value) return false;
    return activeTeam.value.current_user_role === 'owner';
  });

  const isTeamAdmin = computed(() => {
    if (!activeTeam.value) return false;
    return (
      activeTeam.value.current_user_role === 'owner' ||
      activeTeam.value.current_user_role === 'admin'
    );
  });

  const getTeamById = computed(() => (teamId: string): TeamWithRole | undefined => teams.value.find((t) => t.id === teamId));

  const isInitialized = computed(() => _initialized.value);

  // Actions

  /**
   * Initialize the store
   */
  function init() {
    if (_initialized.value) return { hasTeams, isInitialized };

    _initialized.value = true;
    return { hasTeams, isInitialized };
  }

  /**
   * Abort ongoing requests
   */
  function abort() {
    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
  }

  /**
   * Fetch all teams for the current user
   */
  async function fetchTeams(): Promise<TeamWithRole[]> {
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get('/api/teams', {
        signal: abortController.value.signal,
      });

      const validated = teamsResponseSchema.parse(response.data);
      teams.value = validated.teams;
      return teams.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Fetch a single team by ID
   */
  async function fetchTeam(teamId: string): Promise<TeamWithRole> {
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get(`/api/teams/${teamId}`, {
        signal: abortController.value.signal,
      });

      const validated = teamResponseSchema.parse(response.data);
      activeTeam.value = validated.team;

      // Update in teams array if exists
      const index = teams.value.findIndex((t) => t.id === teamId);
      if (index !== -1) {
        teams.value[index] = validated.team;
      } else {
        teams.value.push(validated.team);
      }

      return validated.team;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Create a new team
   */
  async function createTeam(payload: CreateTeamPayload): Promise<TeamWithRole> {
    loading.value = true;

    try {
      const validated = createTeamPayloadSchema.parse(payload);

      const response = await $api.post('/api/teams', validated);

      const teamData = teamResponseSchema.parse(response.data);
      teams.value.push(teamData.team);
      activeTeam.value = teamData.team;

      return teamData.team;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Update a team
   */
  async function updateTeam(teamId: string, payload: UpdateTeamPayload): Promise<TeamWithRole> {
    loading.value = true;

    try {
      const validated = updateTeamPayloadSchema.parse(payload);

      const response = await $api.patch(`/api/teams/${teamId}`, validated);

      const teamData = teamResponseSchema.parse(response.data);

      // Update in teams array
      const index = teams.value.findIndex((t) => t.id === teamId);
      if (index !== -1) {
        teams.value[index] = teamData.team;
      }

      // Update activeTeam if it's the same team
      if (activeTeam.value?.id === teamId) {
        activeTeam.value = teamData.team;
      }

      return teamData.team;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Delete a team
   */
  async function deleteTeam(teamId: string): Promise<void> {
    loading.value = true;

    try {
      await $api.delete(`/api/teams/${teamId}`);

      // Remove from teams array
      teams.value = teams.value.filter((t) => t.id !== teamId);

      // Clear activeTeam if it's the deleted team
      if (activeTeam.value?.id === teamId) {
        activeTeam.value = null;
        members.value = [];
      }
    } finally {
      loading.value = false;
    }
  }

  /**
   * Fetch team members
   */
  async function fetchMembers(teamId: string): Promise<TeamMember[]> {
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get(`/api/teams/${teamId}/members`, {
        signal: abortController.value.signal,
      });

      const validated = membersResponseSchema.parse(response.data);
      members.value = validated.members;
      return members.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Invite a member to the team
   */
  async function inviteMember(teamId: string, payload: InviteMemberPayload): Promise<TeamMember> {
    loading.value = true;

    try {
      const validated = inviteMemberPayloadSchema.parse(payload);

      const response = await $api.post(`/api/teams/${teamId}/members`, validated);

      const memberData = memberResponseSchema.parse(response.data);
      members.value.push(memberData.member);

      // Update member count in team
      const team = teams.value.find((t) => t.id === teamId);
      if (team) {
        team.member_count += 1;
      }
      if (activeTeam.value?.id === teamId) {
        activeTeam.value.member_count += 1;
      }

      return memberData.member;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Update a member's role
   */
  async function updateMemberRole(
    teamId: string,
    memberId: string,
    payload: UpdateMemberRolePayload,
  ): Promise<TeamMember> {
    loading.value = true;

    try {
      const validated = updateMemberRolePayloadSchema.parse(payload);

      const response = await $api.patch(`/api/teams/${teamId}/members/${memberId}`, validated);

      const memberData = memberResponseSchema.parse(response.data);

      // Update in members array
      const index = members.value.findIndex((m) => m.id === memberId);
      if (index !== -1) {
        members.value[index] = memberData.member;
      }

      return memberData.member;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Remove a member from the team
   */
  async function removeMember(teamId: string, memberId: string): Promise<void> {
    loading.value = true;

    try {
      await $api.delete(`/api/teams/${teamId}/members/${memberId}`);

      // Remove from members array
      members.value = members.value.filter((m) => m.id !== memberId);

      // Update member count in team
      const team = teams.value.find((t) => t.id === teamId);
      if (team) {
        team.member_count -= 1;
      }
      if (activeTeam.value?.id === teamId) {
        activeTeam.value.member_count -= 1;
      }
    } finally {
      loading.value = false;
    }
  }

  /**
   * Set the active team
   */
  function setActiveTeam(team: TeamWithRole | null) {
    activeTeam.value = team;
    if (!team) {
      members.value = [];
    }
  }

  /**
   * Reset the store
   */
  function $reset() {
    abort();
    teams.value = [];
    activeTeam.value = null;
    members.value = [];
    _initialized.value = false;
    loading.value = false;
  }

  return {
    // State
    teams,
    activeTeam,
    members,
    loading,
    _initialized,

    // Getters
    hasTeams,
    isTeamOwner,
    isTeamAdmin,
    getTeamById,
    isInitialized,

    // Actions
    init,
    fetchTeams,
    fetchTeam,
    createTeam,
    updateTeam,
    deleteTeam,
    fetchMembers,
    inviteMember,
    updateMemberRole,
    removeMember,
    setActiveTeam,
    abort,
    $reset,
  };
});
