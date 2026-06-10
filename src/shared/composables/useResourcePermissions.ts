// src/shared/composables/useResourcePermissions.ts

/**
 * Resource-scoped permission checks via the permissions API.
 *
 * Unlike useOrgPermissions (which derives permissions from the context bar's
 * current org), this composable fetches authoritative permissions from the
 * backend for a specific resource. Use this for:
 *
 * - Route guards that validate deep links (e.g. /org/:id/domains/:domainId)
 * - UI controls that need permissions for a resource other than the active org
 * - Any case where the context bar's org doesn't match the resource's org
 *
 * @see apps/api/account/logic/account/get_permissions.rb
 */

import { ref, type Ref } from 'vue';
import { useApi } from '@/shared/composables/useApi';
import {
  bulkPermissionsResponseSchema,
  singleResourcePermissionsResponseSchema,
  type BulkPermissionsResponse,
  type SingleResourcePermissionsResponse,
  type OrganizationPermissions,
  type DomainPermissions,
} from '@/schemas/api/account/responses/permissions';

export type ResourceType = 'domain' | 'organization';

export interface UseResourcePermissionsReturn {
  isLoading: Ref<boolean>;
  error: Ref<string | null>;
  fetchAllPermissions: () => Promise<BulkPermissionsResponse | null>;
  fetchResourcePermissions: (
    resourceType: ResourceType,
    resourceId: string
  ) => Promise<SingleResourcePermissionsResponse | null>;
  allPermissions: Ref<BulkPermissionsResponse | null>;
  getOrgPermissions: (orgExtid: string) => OrganizationPermissions | null;
  getDomainPermissions: (domainExtid: string) => DomainPermissions | null;
  canAccess: (resourceType: ResourceType, resourceId: string) => Promise<boolean>;
  canEdit: (resourceType: ResourceType, resourceId: string) => Promise<boolean>;
}

function handleFetchError(
  err: unknown,
  errorRef: Ref<string | null>
): void {
  const axiosErr = err as { response?: { status?: number; data?: { error?: string } } };
  if (axiosErr?.response?.status === 403) {
    errorRef.value = 'Access denied';
  } else if (axiosErr?.response?.status === 404) {
    errorRef.value = 'Resource not found';
  } else {
    errorRef.value = axiosErr?.response?.data?.error || 'Failed to load permissions';
  }
}

function findOrgPermissions(
  allPermissions: BulkPermissionsResponse | null,
  orgExtid: string
): OrganizationPermissions | null {
  if (!allPermissions) return null;
  return allPermissions.organizations.find(org => org.extid === orgExtid) ?? null;
}

function findDomainPermissions(
  allPermissions: BulkPermissionsResponse | null,
  domainExtid: string
): DomainPermissions | null {
  if (!allPermissions) return null;
  for (const org of allPermissions.organizations) {
    const domain = org.domains.find(d => d.extid === domainExtid);
    if (domain) return domain;
  }
  return null;
}

export function useResourcePermissions(): UseResourcePermissionsReturn {
  const $api = useApi();
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const allPermissions = ref<BulkPermissionsResponse | null>(null);

  async function fetchAllPermissions(): Promise<BulkPermissionsResponse | null> {
    isLoading.value = true;
    error.value = null;
    try {
      const response = await $api.get('/api/account/permissions');
      const validated = bulkPermissionsResponseSchema.parse(response.data);
      allPermissions.value = validated;
      return validated;
    } catch (err: unknown) {
      handleFetchError(err, error);
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  async function fetchResourcePermissions(
    resourceType: ResourceType,
    resourceId: string
  ): Promise<SingleResourcePermissionsResponse | null> {
    isLoading.value = true;
    error.value = null;
    try {
      const response = await $api.get('/api/account/permissions', {
        params: { resource_type: resourceType, resource_id: resourceId },
      });
      return singleResourcePermissionsResponseSchema.parse(response.data);
    } catch (err: unknown) {
      handleFetchError(err, error);
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  const getOrgPermissions = (extid: string) => findOrgPermissions(allPermissions.value, extid);
  const getDomainPermissions = (extid: string) =>
    findDomainPermissions(allPermissions.value, extid);

  async function canAccess(resourceType: ResourceType, resourceId: string): Promise<boolean> {
    if (allPermissions.value) {
      const perms = resourceType === 'organization'
        ? getOrgPermissions(resourceId)?.permissions
        : getDomainPermissions(resourceId)?.permissions;
      return perms?.can_view ?? false;
    }
    const result = await fetchResourcePermissions(resourceType, resourceId);
    return result?.permissions.can_view ?? false;
  }

  async function canEdit(resourceType: ResourceType, resourceId: string): Promise<boolean> {
    if (allPermissions.value) {
      const perms = resourceType === 'organization'
        ? getOrgPermissions(resourceId)?.permissions
        : getDomainPermissions(resourceId)?.permissions;
      return perms?.can_edit ?? false;
    }
    const result = await fetchResourcePermissions(resourceType, resourceId);
    return result?.permissions.can_edit ?? false;
  }

  return {
    isLoading, error, fetchAllPermissions, fetchResourcePermissions,
    allPermissions, getOrgPermissions, getDomainPermissions, canAccess, canEdit,
  };
}
