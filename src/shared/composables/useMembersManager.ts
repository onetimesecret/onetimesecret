// src/shared/composables/useMembersManager.ts

/**
 * Composable for managing organization members with UI logic
 * Wraps the members store with permission checks, confirmations, and notifications
 */

import { ApplicationError } from '@/schemas/errors';
import {
  AsyncHandlerOptions,
  useAsyncHandler,
} from '@/shared/composables/useAsyncHandler';
import { useMembersStore, useNotificationsStore } from '@/shared/stores';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type {
  OrganizationMember,
  OrganizationRole,
  UpdateMemberRolePayload,
} from '@/types/organization';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

/**
 * Composable for managing organization members
 *
 * Provides:
 * - Permission-aware member management
 * - Role update with validation
 * - Member removal with confirmation
 * - Loading and error state management
 */
/* eslint-disable max-lines-per-function */
export function useMembersManager() {
  const store = useMembersStore();
  const orgStore = useOrganizationStore();
  const notifications = useNotificationsStore();
  const router = useRouter();
  const { t } = useI18n();

  const { members, loading: storeLoading } = storeToRefs(store);
  const { currentOrganization } = storeToRefs(orgStore);

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  // Computed properties for permissions
  const currentUserRole = computed(
    () => currentOrganization.value?.current_user_role
  );

  const canManageMembers = computed(() => {
    const role = currentUserRole.value;
    return role === 'owner' || role === 'admin';
  });

  const canChangeRoles = computed(() => currentUserRole.value === 'owner');

  const memberCount = computed(() => store.memberCount);

  // Async handler configuration
  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      notifications.show(message, severity);
    },
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      if (err.code === 404) {
        return router.push({ name: 'NotFound' });
      }
      error.value = err;
      if (err.message) {
        notifications.show(err.message, 'error');
      }
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Fetch members for an organization
   */
  const fetchMembers = async (orgExtid: string) =>
    wrap(async () => {
      const result = await store.fetchMembers(orgExtid);
      return result;
    });

  /**
   * Check if the current user can modify a specific member
   */
  const canModifyMember = (member: OrganizationMember): boolean => {
    if (!canManageMembers.value) return false;

    // Cannot modify owners (except by other owners for non-role changes)
    if (member.role === 'owner') return false;

    return true;
  };

  /**
   * Check if the current user can change a member's role
   */
  const canChangeRole = (member: OrganizationMember): boolean => {
    if (!canChangeRoles.value) return false;

    // Cannot change owner's role
    if (member.role === 'owner') return false;

    return true;
  };

  /**
   * Get available roles that can be assigned to a member
   * Owners can only assign admin/member roles (not owner)
   */
  const getAssignableRoles = (): OrganizationRole[] => {
    if (!canChangeRoles.value) return [];
    return ['admin', 'member'];
  };

  /**
   * Update a member's role
   */
  const updateMemberRole = async (
    orgExtid: string,
    memberExtid: string,
    newRole: OrganizationRole
  ) =>
    wrap(async () => {
      const member = store.getMemberByExtid(memberExtid);

      if (!member) {
        throw new Error('Member not found');
      }

      if (!canChangeRole(member)) {
        notifications.show(
          t('web.organizations.members.insufficient_permissions'),
          'error'
        );
        return undefined;
      }

      if (newRole === 'owner') {
        notifications.show(
          t('web.organizations.members.cannot_change_own_role'),
          'error'
        );
        return undefined;
      }

      const payload: UpdateMemberRolePayload = { role: newRole as 'admin' | 'member' };
      const result = await store.updateMemberRole(orgExtid, memberExtid, payload);

      notifications.show(
        t('web.organizations.members.role_updated'),
        'success'
      );

      return result;
    });

  /**
   * Remove a member from the organization
   * Should be called after user confirms the action
   */
  const removeMember = async (orgExtid: string, memberExtid: string) =>
    wrap(async () => {
      const member = store.getMemberByExtid(memberExtid);

      if (!member) {
        throw new Error('Member not found');
      }

      if (!canModifyMember(member)) {
        if (member.role === 'owner') {
          notifications.show(
            t('web.organizations.members.cannot_remove_owner'),
            'error'
          );
        } else {
          notifications.show(
            t('web.organizations.members.insufficient_permissions'),
            'error'
          );
        }
        return undefined;
      }

      await store.removeMember(orgExtid, memberExtid);

      notifications.show(
        t('web.organizations.members.member_removed'),
        'success'
      );

      return true;
    });

  /**
   * Get role display label
   */
  const getRoleLabel = (role: OrganizationRole): string => t(`web.organizations.members.roles.${role}`);

  /**
   * Get role description
   */
  const getRoleDescription = (role: OrganizationRole): string => t(`web.organizations.members.role_descriptions.${role}`);

  /**
   * Clear error state
   */
  const clearError = () => {
    error.value = null;
  };

  return {
    // State
    members,
    isLoading: computed(() => isLoading.value || storeLoading.value),
    error,

    // Getters
    memberCount,
    currentUserRole,
    canManageMembers,
    canChangeRoles,

    // Permission checks
    canModifyMember,
    canChangeRole,
    getAssignableRoles,

    // Actions
    fetchMembers,
    updateMemberRole,
    removeMember,

    // Helpers
    getRoleLabel,
    getRoleDescription,
    clearError,
  };
}
