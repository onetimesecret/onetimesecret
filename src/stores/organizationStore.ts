// src/stores/organizationStore.ts

import type {
  CreateOrganizationPayload,
  Organization,
  UpdateOrganizationPayload,
} from '@/types/organization';
import {
  createOrganizationPayloadSchema,
  updateOrganizationPayloadSchema,
} from '@/types/organization';
import {
  organizationResponseSchema,
  organizationsResponseSchema,
} from '@/schemas/api/organizations';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, inject, ref } from 'vue';

/* eslint-disable max-lines-per-function */
export const useOrganizationStore = defineStore('organization', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const organizations = ref<Organization[]>([]);
  const currentOrganization = ref<Organization | null>(null);
  const _initialized = ref(false);
  const loading = ref(false);
  const abortController = ref<AbortController | null>(null);

  // Getters
  const hasOrganizations = computed(() => organizations.value.length > 0);

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

      const response = await $api.patch(`/api/organizations/${orgId}`, validated);

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
   * Reset the store
   */
  function $reset() {
    abort();
    organizations.value = [];
    currentOrganization.value = null;
    _initialized.value = false;
    loading.value = false;
  }

  return {
    // State
    organizations,
    currentOrganization,
    loading,
    _initialized,

    // Getters
    hasOrganizations,
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
    abort,
    $reset,
  };
});
