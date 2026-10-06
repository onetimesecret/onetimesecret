// src/shared/stores/organizationStore.ts
// @see src/tests/stores/organizationStore.spec.ts - Test fixtures for Organization schema

import {
  organizationResponseSchema,
  organizationsResponseSchema,
} from '@/schemas/api/organizations';
import { loggingService } from '@/services/logging.service';
import { gracefulParse } from '@/utils/schemaValidation';
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
import { useApi } from '@/shared/composables/useApi';
import { defineStore } from 'pinia';
import { computed, ref, watch } from 'vue';
import { z } from 'zod';

import { useAuthStore } from './authStore';
import { useBootstrapStore } from './bootstrapStore';

/* eslint-disable max-lines-per-function */
export const useOrganizationStore = defineStore('organization', () => {
  const $api = useApi();

  // State
  const organizations = ref<Organization[]>([]);
  const currentOrganization = ref<Organization | null>(null);
  const invitations = ref<OrganizationInvitation[]>([]);
  const _initialized = ref(false);
  const _listFetched = ref(false); // Tracks whether fetchOrganizations() was called (full list)
  const loading = ref(false);
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
        organizations.value.find((o) => o.objid === orgId)
  );

  /**
   * Lookup by external (route-visible) id. Mirrors `getOrganizationById` but
   * uses the `extid` field that route params and the auth-result envelope
   * carry. Returns `undefined` when the list hasn't loaded the org yet —
   * callers that want to fall back to the active org compose that themselves
   * (e.g. `getOrganizationByExtid(extid) ?? currentOrganization`).
   */
  const getOrganizationByExtid = computed(
    () =>
      (extid: string): Organization | undefined =>
        organizations.value.find((o) => o.extid === extid)
  );

  /**
   * The organization to fall back to when nothing is selected: the default
   * org, then the first in the list. Null until the list has an entry.
   */
  const defaultOrganization = computed(
    (): Organization | null =>
      organizations.value.find((o) => o.is_default) ?? organizations.value[0] ?? null
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

      const result = gracefulParse(organizationsResponseSchema, response.data, 'OrganizationsResponse');
      if (!result.ok) {
        organizations.value = [];
        _listFetched.value = true;
        return [];
      }
      organizations.value = result.data.records;
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

      const result = gracefulParse(organizationResponseSchema, response.data, 'OrganizationResponse');
      if (!result.ok) {
        throw new Error('Unable to load organization. Please try again.');
      }
      currentOrganization.value = result.data.record;

      // Update in organizations array if exists (use returned objid for matching)
      const index = organizations.value.findIndex((o) => o.objid === result.data.record.objid);
      if (index !== -1) {
        organizations.value[index] = result.data.record;
      } else {
        organizations.value.push(result.data.record);
      }

      return result.data.record;
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
      const payloadResult = gracefulParse(createOrganizationPayloadSchema, payload, 'CreateOrganizationPayload');
      if (!payloadResult.ok) {
        throw new Error('Invalid organization data.');
      }

      const response = await $api.post('/api/organizations', payloadResult.data);

      const orgResult = gracefulParse(organizationResponseSchema, response.data, 'OrganizationResponse');
      if (!orgResult.ok) {
        throw new Error('Unable to create organization. Please try again.');
      }
      organizations.value.push(orgResult.data.record);
      // The app moves the user into the org they just created; record that
      // server-side too so a reload does not drop them back into the old one.
      await selectOrganization(orgResult.data.record);

      return orgResult.data.record;
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
      const payloadResult = gracefulParse(updateOrganizationPayloadSchema, payload, 'UpdateOrganizationPayload');
      if (!payloadResult.ok) {
        throw new Error('Invalid organization update data.');
      }

      const response = await $api.put(`/api/organizations/${extid}`, payloadResult.data);

      const orgResult = gracefulParse(organizationResponseSchema, response.data, 'OrganizationResponse');
      if (!orgResult.ok) {
        throw new Error('Unable to update organization. Please try again.');
      }

      // Update in organizations array (use returned objid for matching)
      const index = organizations.value.findIndex((o) => o.objid === orgResult.data.record.objid);
      if (index !== -1) {
        organizations.value[index] = orgResult.data.record;
      }

      // Update currentOrganization if it's the same organization
      if (currentOrganization.value?.objid === orgResult.data.record.objid) {
        currentOrganization.value = orgResult.data.record;
      }

      return orgResult.data.record;
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

      // Remove from organizations array using internal objid (always present)
      if (orgToDelete) {
        organizations.value = organizations.value.filter((o) => o.objid !== orgToDelete.objid);

        // Clear currentOrganization if it's the deleted organization
        if (currentOrganization.value?.objid === orgToDelete.objid) {
          currentOrganization.value = null;
        }
      }
    } finally {
      loading.value = false;
    }
  }

  /**
   * Set the current organization for this tab only. Route-driven and
   * housekeeping callers use this; it does not change what the server will
   * hand back on the next page load. A user's explicit choice goes through
   * selectOrganization.
   */
  function setCurrentOrganization(org: Organization | null) {
    currentOrganization.value = org;
  }

  /**
   * Sync the selected organization to the backend (fire-and-forget). Resolves
   * once this selection has been sent, or skipped because a later one
   * replaced it while it waited.
   *
   * Page loads carry no O-Organization-ID header, so the bootstrap payload can
   * only name the selected org if the server session remembers it. Sends the
   * same identifier the axios request interceptor puts in that header (objid).
   *
   * The POST is a protected action (ADR-046#authority-action-gating), gated the
   * same way as syncDomainContextToServer: the local selection still changes;
   * only the server write is withheld.
   */
  async function syncOrganizationContextToServer(org: Organization): Promise<void> {
    if (!org.objid) return;
    if (!useAuthStore().protectedActionsAvailable) return;
    if (syncInFlight) {
      // Wait for the reply, then send only the newest selection made since.
      queuedSelection = org;
      return syncInFlight;
    }
    syncInFlight = postOrganizationContexts(org);
    return syncInFlight;
  }

  // Selections are written one at a time, in the order they were made: the
  // server keeps whichever write lands last, and two requests in flight at
  // once can land in either order. While a write is in flight, later
  // selections replace each other in `queuedSelection`; only the newest is
  // sent once the reply arrives. $reset bumps the generation so a chain
  // that outlives it (logout, in-place account change) sends nothing more.
  let syncInFlight: Promise<void> | null = null;
  let queuedSelection: Organization | null = null;
  let syncGeneration = 0;

  async function postOrganizationContexts(first: Organization): Promise<void> {
    const generation = syncGeneration;
    let next: Organization | null = first;
    try {
      while (next) {
        const org = next;
        next = null;
        try {
          await $api.post('/api/account/update-organization-context', {
            organization_id: org.objid,
          });
        } catch (error) {
          console.warn('[organizationStore] Failed to sync to server:', error);
        }
        if (generation !== syncGeneration) return;
        if (!useAuthStore().protectedActionsAvailable) return;
        next = queuedSelection;
        queuedSelection = null;
      }
    } finally {
      if (generation === syncGeneration) syncInFlight = null;
    }
  }

  /**
   * Make `org` the current organization as an explicit user choice (the scope
   * switcher) and record it in the server session, which is the one authority
   * for the selection across page loads. A failed sync leaves the in-app
   * selection in place.
   */
  async function selectOrganization(org: Organization): Promise<void> {
    currentOrganization.value = org;
    await syncOrganizationContextToServer(org);
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

      const result = gracefulParse(
        z.array(organizationInvitationSchema),
        response.data.records,
        'OrganizationInvitations'
      );
      if (!result.ok) {
        invitations.value = [];
        return [];
      }
      invitations.value = result.data;
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
      const payloadResult = gracefulParse(createInvitationPayloadSchema, payload, 'CreateInvitationPayload');
      if (!payloadResult.ok) {
        throw new Error('Invalid invitation data.');
      }

      const response = await $api.post(`/api/organizations/${extid}/invitations`, payloadResult.data);

      const invResult = gracefulParse(organizationInvitationSchema, response.data.record, 'OrganizationInvitation');
      if (!invResult.ok) {
        throw new Error('Unable to create invitation. Please try again.');
      }
      invitations.value.push(invResult.data);

      return invResult.data;
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
    syncGeneration += 1;
    queuedSelection = null;
    syncInFlight = null;
    organizations.value = [];
    currentOrganization.value = null;
    invitations.value = [];
    _initialized.value = false;
    _listFetched.value = false;
    loading.value = false;
  }

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

  // Initialize currentOrganization from bootstrap payload
  // This eliminates the race condition where domain context needs organization
  // before fetchOrganizations completes. Bootstrap provides organization from
  // server-side OrganizationLoader, ensuring it's available immediately.
  // It is also the only thing that restores the selection after a page load:
  // the server session remembers the last selectOrganization() (#4565), so
  // there is no client-side copy to restore from or to keep in agreement.
  watch(
    () => bootstrap.organization,
    (bootstrapOrg) => {
      // Only seed if we don't already have a currentOrganization
      // This prevents a mid-session bootstrap refresh from replacing the
      // organization selected (or route-resolved) in this tab
      if (bootstrapOrg && !currentOrganization.value) {
        // Convert bootstrap org format to Organization type
        // Bootstrap provides minimal fields (objid, extid, display_name,
        // is_default, planid, current_user_role, entitlements, limits)
        // Full data comes from fetchOrganization
        currentOrganization.value = {
          objid: bootstrapOrg.objid,
          extid: bootstrapOrg.extid,
          display_name: bootstrapOrg.display_name,
          description: null,
          owner_id: '',
          contact_email: null,
          is_default: bootstrapOrg.is_default,
          planid: bootstrapOrg.planid ?? 'free_v1',
          current_user_role: bootstrapOrg.current_user_role ?? null,
          entitlements: bootstrapOrg.entitlements ?? null,
          limits: bootstrapOrg.limits ?? null,
          // These fields will be populated when full org is fetched
          created: new Date(),
          updated: new Date(),
        } as Organization;

        loggingService.debug('[organizationStore] Initialized from bootstrap', { objid: bootstrapOrg.objid });
      }
    },
    { immediate: true }
  );

  return {
    // State
    organizations,
    currentOrganization,
    invitations,
    loading,
    _initialized,

    // Getters
    hasOrganizations,
    hasNonDefaultOrganizations,
    getOrganizationById,
    getOrganizationByExtid,
    defaultOrganization,
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
    selectOrganization,
    fetchInvitations,
    createInvitation,
    resendInvitation,
    revokeInvitation,
    abort,
    $reset,
  };
});
