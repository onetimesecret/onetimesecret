// src/shared/composables/useOrgPermissions.ts

import { computed, type ComputedRef, type MaybeRef, unref } from 'vue';
import { storeToRefs } from 'pinia';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';

export type OrganizationRole = 'owner' | 'admin' | 'member';

export interface OrgPermissions {
  /** The user's role in the resolved org, or null when unknown / unauthenticated. */
  currentRole: ComputedRef<OrganizationRole | null>;
  /** True when the role is owner or admin. */
  isOwnerOrAdmin: ComputedRef<boolean>;
  /** Hide the Add Domain control unless the user can act on it (per #3033). */
  canCreateDomain: ComputedRef<boolean>;
  /** Reserved for §2 organizations and §6 invite gates (mirrors backend gates). */
  canCreateOrganization: ComputedRef<boolean>;
  canInviteMembers: ComputedRef<boolean>;
  canManageDomain: ComputedRef<boolean>;
}

/**
 * Role-based permission predicates for the org that governs a given UI surface.
 *
 * Pass an explicit org ref when the surface is org-scoped (e.g. a domains table
 * for a specific org). Omit it to use the active organization from the store.
 *
 * The single source of truth is `current_user_role` on the Organization record,
 * which the backend populates from `OrganizationMembership` (see
 * apps/api/organizations/logic/base.rb#determine_user_role).
 */
export function useOrgPermissions(
  org?: MaybeRef<Organization | null | undefined>
): OrgPermissions {
  const organizationStore = useOrganizationStore();
  const { currentOrganization } = storeToRefs(organizationStore);

  // When the caller passes an org parameter (ref or value), respect it as-is —
  // a null/undefined value means "role not yet resolved", not "use active org".
  // Falling back here would flash incorrect permissions for the active org
  // while the explicit one is still loading.
  const callerProvidedOrg = org !== undefined;

  const activeOrg = computed<Organization | null>(() => {
    if (callerProvidedOrg) {
      return unref(org) ?? null;
    }
    return currentOrganization.value ?? null;
  });

  const currentRole = computed<OrganizationRole | null>(
    () => (activeOrg.value?.current_user_role as OrganizationRole | null | undefined) ?? null
  );

  const isOwnerOrAdmin = computed(() => {
    const role = currentRole.value;
    return role === 'owner' || role === 'admin';
  });

  return {
    currentRole,
    isOwnerOrAdmin,
    canCreateDomain: isOwnerOrAdmin,
    canCreateOrganization: isOwnerOrAdmin,
    canInviteMembers: isOwnerOrAdmin,
    canManageDomain: isOwnerOrAdmin,
  };
}
