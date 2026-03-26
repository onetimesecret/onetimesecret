// src/shared/stores/membersStore.ts

/**
 * Pinia store for managing organization members
 * Handles fetching, updating roles, and removing members
 */

import {
  memberDeleteResponseSchema,
  memberResponseSchema,
  membersResponseSchema,
} from '@/schemas/api/organizations';
import type {
  OrganizationMember,
  OrganizationRole,
  UpdateMemberRolePayload,
} from '@/types/organization';
import { updateMemberRolePayloadSchema } from '@/types/organization';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

/* eslint-disable max-lines-per-function */
export const useMembersStore = defineStore('members', () => {
  const $api = useApi();

  // State
  const members = ref<OrganizationMember[]>([]);
  const currentOrgExtid = ref<string | null>(null);
  const _initialized = ref(false);
  const loading = ref(false);
  const abortController = ref<AbortController | null>(null);

  // Getters
  const memberCount = computed(() => members.value.length);

  const isInitialized = computed(() => _initialized.value);

  const getMemberById = computed(
    () =>
      (extid: string): OrganizationMember | undefined =>
        members.value.find((m) => m.extid === extid)
  );

  const getMembersByRole = computed(
    () =>
      (role: OrganizationRole): OrganizationMember[] =>
        members.value.filter((m) => m.role === role)
  );

  const owners = computed(() => getMembersByRole.value('owner'));
  const admins = computed(() => getMembersByRole.value('admin'));

  // Actions

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
   * Fetch all members for an organization
   */
  async function fetchMembers(orgExtid: string): Promise<OrganizationMember[]> {
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${orgExtid}/members`, {
        signal: abortController.value.signal,
      });

      const result = gracefulParse(membersResponseSchema, response.data, 'MembersResponse');
      if (!result.ok) {
        throw new Error('Unable to load members. Please try again.');
      }
      members.value = result.data.records;
      currentOrgExtid.value = orgExtid;
      _initialized.value = true;

      return members.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Update a member's role
   */
  async function updateMemberRole(
    orgExtid: string,
    memberExtid: string,
    payload: UpdateMemberRolePayload
  ): Promise<OrganizationMember> {
    loading.value = true;

    try {
      const payloadResult = gracefulParse(updateMemberRolePayloadSchema, payload, 'UpdateMemberRolePayload');
      if (!payloadResult.ok) {
        throw new Error('Invalid member role update data.');
      }

      const response = await $api.patch(
        `/api/organizations/${orgExtid}/members/${memberExtid}/role`,
        payloadResult.data
      );

      const memberResult = gracefulParse(memberResponseSchema, response.data, 'MemberResponse');
      if (!memberResult.ok) {
        throw new Error('Unable to update member role. Please try again.');
      }

      // Update in members array
      const index = members.value.findIndex((m) => m.extid === memberExtid);
      if (index !== -1) {
        members.value[index] = memberResult.data.record;
      }

      return memberResult.data.record;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Remove a member from the organization
   */
  async function removeMember(orgExtid: string, memberExtid: string): Promise<void> {
    loading.value = true;

    try {
      const response = await $api.delete(
        `/api/organizations/${orgExtid}/members/${memberExtid}`
      );

      const deleteResult = gracefulParse(memberDeleteResponseSchema, response.data, 'MemberDeleteResponse');
      if (!deleteResult.ok) {
        throw new Error('Unable to remove member. Please try again.');
      }

      // Remove from members array
      members.value = members.value.filter((m) => m.extid !== memberExtid);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Reset the store
   */
  function $reset() {
    abort();
    members.value = [];
    currentOrgExtid.value = null;
    _initialized.value = false;
    loading.value = false;
  }

  return {
    // State
    members,
    currentOrgExtid,
    loading,
    _initialized,

    // Getters
    memberCount,
    isInitialized,
    getMemberById,
    getMembersByRole,
    owners,
    admins,

    // Actions
    fetchMembers,
    updateMemberRole,
    removeMember,
    abort,
    $reset,
  };
});
