// src/shared/stores/organizationStore.ts

import {
  organizationResponseSchema,
  organizationsResponseSchema,
} from '@/schemas/api/organizations';
import { loggingService } from '@/services/logging.service';
import type {
  CreateInvitationPayload,
  CreateOrganizationPayload,
  Organization,
  OrganizationInvitation,
  UpdateOrganizationPayload,
} from '@/types/organization';
import {
  createInvitationPayloadSchema,
  createOrganizationPayloadSchema,
  organizationInvitationSchema,
  updateOrganizationPayloadSchema,
} from '@/types/organization';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, inject, ref, watch } from 'vue';

import { useBootstrapStore } from './bootstrapStore';

/**
 * localStorage key for persisting selected organization across sessions.
 * Used internally by the store for persistence.
 */
export const SELECTED_ORG_STORAGE_KEY = 'selectedOrganizationId';

/**
 * Load persisted organization ID from localStorage with error handling.
 */
function loadPersistedOrgId(): string | null {
  try {
    return localStorage.getItem(SELECTED_ORG_STORAGE_KEY);
  } catch (error) {
    loggingService.error(new Error(`Failed to load persisted organization: ${error}`));
    return null;
  }
}

/**
 * Persist organization ID to localStorage with error handling.
 */
function persistOrgId(orgId: string | null): void {
  try {
    if (orgId) {
      localStorage.setItem(SELECTED_ORG_STORAGE_KEY, orgId);
    } else {
      localStorage.removeItem(SELECTED_ORG_STORAGE_KEY);
    }
  } catch (error) {
    loggingService.error(new Error(`Failed to persist organization selection: ${error}`));
  }
}

/* eslint-disable max-lines-per-function */
export const useOrganizationStore = defineStore('organization', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const organizations = ref<Organization[]>([]);
  const currentOrganization = ref<Organization | null>(null);
  const invitations = ref<OrganizationInvitation[]>([]);
  const _initialized = ref(false);
  const _listFetched = ref(false); // Tracks whether fetchOrganizations() was called (full list)
  const loading = ref(false);
  const entitlementsError = ref<string | null>(null);
  // AbortController for list fetches only - single-org fetches don't need cancellation
  const abortController = ref<AbortController | null>(null);

  // Getters
  const hasOrganizations = computed(() => organizations.value.length > 0);

  const hasNonDefaultOrganizations = computed(() =>
    organizations.value.some((org) => !org.is_default)
  );

  const getOrganizationById = computed(
    () =>
      (orgId: string): Organization | undefined =>
        organizations.value.find((o) => o.id === orgId)
  );

  const isInitialized = computed(() => _initialized.value);
  const isListFetched = computed(() => _listFetched.value);

  // Actions

  /**
   * Initialize the store
   */
  function init() {
    if (_initialized.value) return { hasOrganizations, isInitialized };

    _initialized.value = true;
    return { hasOrganizations, isInitialized };
  }

  /**
   * Abort ongoing list fetch request
   */
  function abort() {
    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
  }

  /**
   * Fetch all organizations for the current user
   */
  async function fetchOrganizations(): Promise<Organization[]> {
    abort(); // Cancel any previous list fetch (deduplication)
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get('/api/organizations', {
        signal: abortController.value.signal,
      });

      const validated = organizationsResponseSchema.parse(response.data);
      organizations.value = validated.records;
      _listFetched.value = true;
      return organizations.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Fetch a single organization by external ID (extid)
   *
   * @param extid - The external ID for API calls (e.g., "on1234abc")
   */
  async function fetchOrganization(extid: string): Promise<Organization> {
    // No abort() call here - single-org fetches are fast and shouldn't
    // cancel in-flight list fetches (which would break the org dropdown)
    loading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${extid}`);

      const validated = organizationResponseSchema.parse(response.data);
      currentOrganization.value = validated.record;

      // Update in organizations array if exists (use returned id for matching)
      const index = organizations.value.findIndex((o) => o.id === validated.record.id);
      if (index !== -1) {
        organizations.value[index] = validated.record;
      } else {
        organizations.value.push(validated.record);
      }

      return validated.record;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Create a new organization
   */
  async function createOrganization(payload: CreateOrganizationPayload): Promise<Organization> {
    loading.value = true;

    try {
      const validated = createOrganizationPayloadSchema.parse(payload);

      const response = await $api.post('/api/organizations', validated);

      const orgData = organizationResponseSchema.parse(response.data);
      organizations.value.push(orgData.record);
      currentOrganization.value = orgData.record;

      return orgData.record;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Update an organization
   *
   * @param extid - The external ID for API calls
   */
  async function updateOrganization(
    extid: string,
    payload: UpdateOrganizationPayload
  ): Promise<Organization> {
    loading.value = true;

    try {
      const validated = updateOrganizationPayloadSchema.parse(payload);

      const response = await $api.put(`/api/organizations/${extid}`, validated);

      const orgData = organizationResponseSchema.parse(response.data);

      // Update in organizations array (use returned id for matching)
      const index = organizations.value.findIndex((o) => o.id === orgData.record.id);
      if (index !== -1) {
        organizations.value[index] = orgData.record;
      }

      // Update currentOrganization if it's the same organization
      if (currentOrganization.value?.id === orgData.record.id) {
        currentOrganization.value = orgData.record;
      }

      return orgData.record;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Delete an organization
   *
   * @param extid - The external ID for API calls
   */
  async function deleteOrganization(extid: string): Promise<void> {
    loading.value = true;

    try {
      // Find the org before deleting to get internal ID for cleanup
      const orgToDelete = organizations.value.find((o) => o.extid === extid);
      await $api.delete(`/api/organizations/${extid}`);

      // Remove from organizations array using internal ID (always present)
      if (orgToDelete) {
        organizations.value = organizations.value.filter((o) => o.id !== orgToDelete.id);

        // Clear currentOrganization if it's the deleted organization
        if (currentOrganization.value?.id === orgToDelete.id) {
          currentOrganization.value = null;
        }
      }
    } finally {
      loading.value = false;
    }
  }

  /**
   * Set the current organization
   */
  function setCurrentOrganization(org: Organization | null) {
    currentOrganization.value = org;
  }

  /**
   * Fetch entitlements for an organization
   * This method fetches the organization's billing entitlements and limits
   *
   * @param extid - The external ID for API calls
   * @param options.throwOnError - If true, throws on error instead of swallowing
   */
  async function fetchEntitlements(
    extid: string,
    options: { throwOnError?: boolean } = {}
  ): Promise<void> {
    entitlementsError.value = null;

    try {
      const response = await $api.get(`/billing/api/entitlements/${extid}`);

      // Update the organization with entitlements (find by extid)
      const index = organizations.value.findIndex((o) => o.extid === extid);
      if (index !== -1) {
        organizations.value[index] = {
          ...organizations.value[index],
          planid: response.data.planid,
          entitlements: response.data.entitlements,
          limits: response.data.limits,
        };
      } else {
        console.debug('[OrganizationStore] Organization not in cache, skipping list update:', extid);
      }

      // Update current organization if it matches
      if (currentOrganization.value?.extid === extid) {
        currentOrganization.value = {
          ...currentOrganization.value,
          planid: response.data.planid,
          entitlements: response.data.entitlements,
          limits: response.data.limits,
        };
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load entitlements';
      entitlementsError.value = message;
      console.error('[OrganizationStore] Error fetching entitlements:', err);

      // Optionally throw for callers that want to handle errors explicitly
      if (options.throwOnError) {
        throw err;
      }
      // Otherwise, fail gracefully - entitlements are optional enhancements
    }
  }

  /**
   * Clear the entitlements error state
   */
  function clearEntitlementsError(): void {
    entitlementsError.value = null;
  }

  /**
   * Fetch pending invitations for an organization
   *
   * @param extid - The external ID for API calls
   */
  async function fetchInvitations(extid: string): Promise<OrganizationInvitation[]> {
    loading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${extid}/invitations`);

      const validated = response.data.records.map((inv: unknown) =>
        organizationInvitationSchema.parse(inv)
      );
      invitations.value = validated;
      return invitations.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Create an invitation for an organization
   *
   * @param extid - The external ID for API calls
   */
  async function createInvitation(
    extid: string,
    payload: CreateInvitationPayload
  ): Promise<OrganizationInvitation> {
    loading.value = true;

    try {
      const validated = createInvitationPayloadSchema.parse(payload);

      const response = await $api.post(`/api/organizations/${extid}/invitations`, validated);

      const invitation = organizationInvitationSchema.parse(response.data.record);
      invitations.value.push(invitation);

      return invitation;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Resend an invitation
   *
   * @param extid - The external ID for API calls
   */
  async function resendInvitation(extid: string, token: string): Promise<void> {
    loading.value = true;

    try {
      await $api.post(`/api/organizations/${extid}/invitations/${token}/resend`);

      // Refresh invitations to get updated resend count
      await fetchInvitations(extid);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Revoke an invitation
   *
   * @param extid - The external ID for API calls
   */
  async function revokeInvitation(extid: string, token: string): Promise<void> {
    loading.value = true;

    try {
      await $api.delete(`/api/organizations/${extid}/invitations/${token}`);

      // Remove from invitations array
      invitations.value = invitations.value.filter((inv) => inv.token !== token);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Reset the store
   */
  function $reset() {
    abort();
    organizations.value = [];
    currentOrganization.value = null;
    invitations.value = [];
    _initialized.value = false;
    _listFetched.value = false;
    loading.value = false;
    entitlementsError.value = null;
  }

  /**
   * Restore persisted organization selection from localStorage.
   * Returns the restored organization or null if not found.
   * Priority: localStorage saved org > default org > first org
   */
  function restorePersistedSelection(): Organization | null {
    if (organizations.value.length === 0) return null;

    const savedOrgId = loadPersistedOrgId();
    if (savedOrgId) {
      const savedOrg = organizations.value.find(
        (o) => o.id === savedOrgId || o.extid === savedOrgId
      );
      if (savedOrg) return savedOrg;
    }

    // Fall back to default org, then first org
    return organizations.value.find((o) => o.is_default) ?? organizations.value[0] ?? null;
  }

  // Watch currentOrganization and persist to localStorage
  watch(
    () => currentOrganization.value?.id,
    (newOrgId) => {
      persistOrgId(newOrgId ?? null);
    }
  );

  // Watch bootstrap auth state and reset on logout
  // This ensures organization data is cleared when the user logs out
  //
  // Why no `immediate: true`:
  // - This watch handles the logout TRANSITION (authenticated → unauthenticated)
  // - On store initialization, state is already in default/reset form
  // - Adding `immediate` would cause unnecessary $reset() calls for anonymous users
  //
  // Edge cases to monitor:
  // - If org data ever persists across page loads (e.g., localStorage caching),
  //   consider adding `immediate: true` to clear stale data on init
  // - Currently Pinia stores initialize fresh, so this isn't needed
  const bootstrap = useBootstrapStore();
  watch(
    () => bootstrap.authenticated,
    (authenticated) => {
      if (!authenticated) {
        $reset();
      }
    }
  );

  return {
    // State
    organizations,
    currentOrganization,
    invitations,
    loading,
    entitlementsError,
    _initialized,

    // Getters
    hasOrganizations,
    hasNonDefaultOrganizations,
    getOrganizationById,
    isInitialized,
    isListFetched,

    // Actions
    init,
    fetchOrganizations,
    fetchOrganization,
    createOrganization,
    updateOrganization,
    deleteOrganization,
    setCurrentOrganization,
    restorePersistedSelection,
    fetchEntitlements,
    clearEntitlementsError,
    fetchInvitations,
    createInvitation,
    resendInvitation,
    revokeInvitation,
    abort,
    $reset,
  };
});
