// src/shared/stores/organizationStore.ts

import {
  organizationResponseSchema,
  organizationsResponseSchema,
} from '@/schemas/api/organizations';
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
import { computed, inject, ref } from 'vue';

/* eslint-disable max-lines-per-function */
export const useOrganizationStore = defineStore('organization', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const organizations = ref<Organization[]>([]);
  const currentOrganization = ref<Organization | null>(null);
  const invitations = ref<OrganizationInvitation[]>([]);
  const _initialized = ref(false);
  const loading = ref(false);
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
   * Abort ongoing requests
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
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get('/api/organizations', {
        signal: abortController.value.signal,
      });

      const validated = organizationsResponseSchema.parse(response.data);
      organizations.value = validated.records;
      return organizations.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Fetch a single organization by ID
   */
  async function fetchOrganization(orgId: string): Promise<Organization> {
    abort();
    abortController.value = new AbortController();
    loading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${orgId}`, {
        signal: abortController.value.signal,
      });

      const validated = organizationResponseSchema.parse(response.data);
      currentOrganization.value = validated.record;

      // Update in organizations array if exists
      const index = organizations.value.findIndex((o) => o.id === orgId);
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
   */
  async function updateOrganization(
    orgId: string,
    payload: UpdateOrganizationPayload
  ): Promise<Organization> {
    loading.value = true;

    try {
      const validated = updateOrganizationPayloadSchema.parse(payload);

      const response = await $api.put(`/api/organizations/${orgId}`, validated);

      const orgData = organizationResponseSchema.parse(response.data);

      // Update in organizations array
      const index = organizations.value.findIndex((o) => o.id === orgId);
      if (index !== -1) {
        organizations.value[index] = orgData.record;
      }

      // Update currentOrganization if it's the same organization
      if (currentOrganization.value?.id === orgId) {
        currentOrganization.value = orgData.record;
      }

      return orgData.record;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Delete an organization
   */
  async function deleteOrganization(orgId: string): Promise<void> {
    loading.value = true;

    try {
      await $api.delete(`/api/organizations/${orgId}`);

      // Remove from organizations array
      organizations.value = organizations.value.filter((o) => o.id !== orgId);

      // Clear currentOrganization if it's the deleted organization
      if (currentOrganization.value?.id === orgId) {
        currentOrganization.value = null;
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
   */
  async function fetchEntitlements(orgId: string): Promise<void> {
    try {
      const response = await $api.get(`/api/billing/entitlements/${orgId}`);

      // Update the organization with entitlements
      const index = organizations.value.findIndex((o) => o.id === orgId);
      if (index !== -1) {
        organizations.value[index] = {
          ...organizations.value[index],
          planid: response.data.planid,
          entitlements: response.data.entitlements,
          limits: response.data.limits,
        };
      }

      // Update current organization if it matches
      if (currentOrganization.value?.id === orgId) {
        currentOrganization.value = {
          ...currentOrganization.value,
          planid: response.data.planid,
          entitlements: response.data.entitlements,
          limits: response.data.limits,
        };
      }
    } catch (err) {
      console.error('[OrganizationStore] Error fetching entitlements:', err);
      // Don't throw - entitlements are optional enhancements
    }
  }

  /**
   * Fetch pending invitations for an organization
   */
  async function fetchInvitations(orgId: string): Promise<OrganizationInvitation[]> {
    loading.value = true;

    try {
      const response = await $api.get(`/api/organizations/${orgId}/invitations`);

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
   */
  async function createInvitation(
    orgId: string,
    payload: CreateInvitationPayload
  ): Promise<OrganizationInvitation> {
    loading.value = true;

    try {
      const validated = createInvitationPayloadSchema.parse(payload);

      const response = await $api.post(`/api/organizations/${orgId}/invitations`, validated);

      const invitation = organizationInvitationSchema.parse(response.data.record);
      invitations.value.push(invitation);

      return invitation;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Resend an invitation
   */
  async function resendInvitation(orgId: string, token: string): Promise<void> {
    loading.value = true;

    try {
      await $api.post(`/api/organizations/${orgId}/invitations/${token}/resend`);

      // Refresh invitations to get updated resend count
      await fetchInvitations(orgId);
    } finally {
      loading.value = false;
    }
  }

  /**
   * Revoke an invitation
   */
  async function revokeInvitation(orgId: string, token: string): Promise<void> {
    loading.value = true;

    try {
      await $api.delete(`/api/organizations/${orgId}/invitations/${token}`);

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
    loading.value = false;
  }

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
    isInitialized,

    // Actions
    init,
    fetchOrganizations,
    fetchOrganization,
    createOrganization,
    updateOrganization,
    deleteOrganization,
    setCurrentOrganization,
    fetchEntitlements,
    fetchInvitations,
    createInvitation,
    resendInvitation,
    revokeInvitation,
    abort,
    $reset,
  };
});
