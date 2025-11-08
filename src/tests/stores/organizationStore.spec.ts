// src/tests/stores/organizationStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

import { useOrganizationStore } from '@/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type AxiosMockAdapter from 'axios-mock-adapter';

describe('Organization Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let store: ReturnType<typeof useOrganizationStore>;

  const mockOrganization: Organization = {
    id: 'org-123',
    display_name: 'Test Organization',
    description: 'A test organization',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  };

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;

    vi.stubGlobal('window', setupWindowState());
    store = useOrganizationStore();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock?.reset();
  });

  describe('Initialization', () => {
    it('initializes with empty state', () => {
      store.init();

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
      expect(store.isInitialized).toBe(true);
    });

    it('prevents double initialization', () => {
      const result1 = store.init();
      const result2 = store.init();

      expect(result1).toStrictEqual(result2);
      expect(store.isInitialized).toBe(true);
    });
  });

  describe('Fetching organizations', () => {
    it('fetches all organizations successfully', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, {
        records: [mockOrganization],
        count: 1,
      });

      await store.fetchOrganizations();

      expect(store.organizations).toHaveLength(1);
      expect(store.organizations[0]).toEqual(mockOrganization);
      expect(store.hasOrganizations).toBe(true);
    });

    it('handles empty organizations response', async () => {
      axiosMock?.onGet('/api/organizations').reply(200, {
        records: [],
        count: 0,
      });

      await store.fetchOrganizations();

      expect(store.organizations).toEqual([]);
      expect(store.hasOrganizations).toBe(false);
    });

    it('fetches a single organization by ID', async () => {
      axiosMock?.onGet('/api/organizations/org-123').reply(200, {
        record: mockOrganization,
      });

      const org = await store.fetchOrganization('org-123');

      expect(org).toEqual(mockOrganization);
      expect(store.currentOrganization).toEqual(mockOrganization);
    });
  });

  describe('Creating organizations', () => {
    it('creates a new organization successfully', async () => {
      const newOrgPayload = {
        display_name: 'New Organization',
        description: 'A new test organization',
      };

      axiosMock?.onPost('/api/organizations').reply(200, {
        record: mockOrganization,
      });

      const org = await store.createOrganization(newOrgPayload);

      expect(org).toEqual(mockOrganization);
      expect(store.organizations).toContainEqual(mockOrganization);
      expect(store.currentOrganization).toEqual(mockOrganization);
    });
  });

  describe('Updating organizations', () => {
    beforeEach(async () => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;
    });

    it('updates an organization successfully', async () => {
      const updates = {
        display_name: 'Updated Organization Name',
      };

      const updatedOrg = { ...mockOrganization, ...updates };

      axiosMock?.onPatch('/api/organizations/org-123').reply(200, {
        record: updatedOrg,
      });

      const result = await store.updateOrganization('org-123', updates);

      expect(result.display_name).toBe('Updated Organization Name');
      expect(store.organizations[0].display_name).toBe('Updated Organization Name');
      expect(store.currentOrganization?.display_name).toBe('Updated Organization Name');
    });
  });

  describe('Deleting organizations', () => {
    beforeEach(() => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;
    });

    it('deletes an organization successfully', async () => {
      axiosMock?.onDelete('/api/organizations/org-123').reply(200);

      await store.deleteOrganization('org-123');

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
    });
  });

  describe('Getters', () => {
    it('computes hasOrganizations correctly', () => {
      expect(store.hasOrganizations).toBe(false);

      store.organizations = [mockOrganization];
      expect(store.hasOrganizations).toBe(true);
    });

    it('finds organization by ID', () => {
      store.organizations = [mockOrganization];

      const found = store.getOrganizationById('org-123');
      expect(found).toEqual(mockOrganization);

      const notFound = store.getOrganizationById('nonexistent');
      expect(notFound).toBeUndefined();
    });
  });

  describe('Reset functionality', () => {
    it('resets store to initial state', () => {
      store.organizations = [mockOrganization];
      store.currentOrganization = mockOrganization;

      store.$reset();

      expect(store.organizations).toEqual([]);
      expect(store.currentOrganization).toBeNull();
      expect(store._initialized).toBe(false);
    });
  });
});
