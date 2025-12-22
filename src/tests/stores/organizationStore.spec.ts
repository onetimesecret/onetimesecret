// src/tests/stores/organizationStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type AxiosMockAdapter from 'axios-mock-adapter';

describe('Organization Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let store: ReturnType<typeof useOrganizationStore>;

  // Raw API response format (Unix timestamps)
  const mockOrganizationRaw = {
    id: 'org-123',
    display_name: 'Test Organization',
    description: 'A test organization',
    is_default: false,
    created_at: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
    updated_at: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
  };

  // Transformed format (Date objects) for expectations
  const mockOrganization: Organization = {
    id: 'org-123',
    display_name: 'Test Organization',
    description: 'A test organization',
    is_default: false,
    created_at: new Date('2024-01-01T00:00:00Z'),
    updated_at: new Date('2024-01-01T00:00:00Z'),
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
        records: [mockOrganizationRaw],
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
        record: mockOrganizationRaw,
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
        record: mockOrganizationRaw,
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

      const updatedOrgRaw = { ...mockOrganizationRaw, ...updates };

      axiosMock?.onPut('/api/organizations/org-123').reply(200, {
        record: updatedOrgRaw,
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

  describe('Organization Invitations', () => {
    // Mock invitation data
    const mockInvitationRaw = {
      id: 'inv-123',
      organization_id: 'org-123',
      email: 'invitee@example.com',
      role: 'member' as const,
      status: 'pending' as const,
      invited_by: 'owner@example.com',
      invited_at: Math.floor(new Date('2024-01-01T00:00:00Z').getTime() / 1000),
      expires_at: Math.floor(new Date('2024-01-08T00:00:00Z').getTime() / 1000),
      resend_count: 0,
      token: 'secure-token-abc123',
    };

    const mockInvitationRaw2 = {
      id: 'inv-456',
      organization_id: 'org-123',
      email: 'another@example.com',
      role: 'admin' as const,
      status: 'pending' as const,
      invited_by: 'owner@example.com',
      invited_at: Math.floor(new Date('2024-01-02T00:00:00Z').getTime() / 1000),
      expires_at: Math.floor(new Date('2024-01-09T00:00:00Z').getTime() / 1000),
      resend_count: 1,
      token: 'secure-token-def456',
    };

    describe('fetchInvitations', () => {
      it('fetches invitations for an organization successfully', async () => {
        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(200, {
          records: [mockInvitationRaw, mockInvitationRaw2],
        });

        const invitations = await store.fetchInvitations('org-123');

        expect(invitations).toHaveLength(2);
        expect(store.invitations).toHaveLength(2);
        expect(invitations[0].email).toBe('invitee@example.com');
        expect(invitations[0].role).toBe('member');
        expect(invitations[1].email).toBe('another@example.com');
        expect(invitations[1].role).toBe('admin');
      });

      it('handles empty invitations response', async () => {
        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(200, {
          records: [],
        });

        const invitations = await store.fetchInvitations('org-123');

        expect(invitations).toEqual([]);
        expect(store.invitations).toEqual([]);
      });

      it('validates invitation data with schema', async () => {
        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(200, {
          records: [mockInvitationRaw],
        });

        const invitations = await store.fetchInvitations('org-123');

        expect(invitations[0]).toMatchObject({
          id: 'inv-123',
          organization_id: 'org-123',
          email: 'invitee@example.com',
          role: 'member',
          status: 'pending',
          invited_by: 'owner@example.com',
          resend_count: 0,
          token: 'secure-token-abc123',
        });
      });

      it('sets loading state during fetch', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(async () => {
          await requestPromise;
          return [200, { records: [mockInvitationRaw] }];
        });

        const fetchPromise = store.fetchInvitations('org-123');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await fetchPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('createInvitation', () => {
      it('creates an invitation successfully', async () => {
        const payload = {
          email: 'newmember@example.com',
          role: 'member' as const,
        };

        const createdInvitationRaw = {
          ...mockInvitationRaw,
          id: 'inv-new',
          email: 'newmember@example.com',
        };

        axiosMock?.onPost('/api/organizations/org-123/invitations').reply(200, {
          record: createdInvitationRaw,
        });

        const invitation = await store.createInvitation('org-123', payload);

        expect(invitation.email).toBe('newmember@example.com');
        expect(invitation.role).toBe('member');
        expect(store.invitations).toContainEqual(
          expect.objectContaining({ email: 'newmember@example.com' })
        );
      });

      it('creates an admin invitation', async () => {
        const payload = {
          email: 'newadmin@example.com',
          role: 'admin' as const,
        };

        const createdInvitationRaw = {
          ...mockInvitationRaw,
          id: 'inv-admin',
          email: 'newadmin@example.com',
          role: 'admin' as const,
        };

        axiosMock?.onPost('/api/organizations/org-123/invitations').reply(200, {
          record: createdInvitationRaw,
        });

        const invitation = await store.createInvitation('org-123', payload);

        expect(invitation.email).toBe('newadmin@example.com');
        expect(invitation.role).toBe('admin');
      });

      it('adds created invitation to store invitations array', async () => {
        // Pre-populate with existing invitation
        store.invitations = [
          {
            id: 'inv-existing',
            organization_id: 'org-123',
            email: 'existing@example.com',
            role: 'member',
            status: 'pending',
            invited_by: 'owner@example.com',
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
          },
        ];

        const payload = {
          email: 'new@example.com',
          role: 'member' as const,
        };

        axiosMock?.onPost('/api/organizations/org-123/invitations').reply(200, {
          record: { ...mockInvitationRaw, email: 'new@example.com' },
        });

        await store.createInvitation('org-123', payload);

        expect(store.invitations).toHaveLength(2);
      });

      it('validates payload before sending', async () => {
        const invalidPayload = {
          email: 'invalid-email',
          role: 'member' as const,
        };

        await expect(store.createInvitation('org-123', invalidPayload)).rejects.toThrow();
      });

      it('sets loading state during creation', async () => {
        const payload = {
          email: 'test@example.com',
          role: 'member' as const,
        };

        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock?.onPost('/api/organizations/org-123/invitations').reply(async () => {
          await requestPromise;
          return [200, { record: mockInvitationRaw }];
        });

        const createPromise = store.createInvitation('org-123', payload);
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await createPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('resendInvitation', () => {
      beforeEach(() => {
        // Pre-populate with invitation
        store.invitations = [
          {
            id: 'inv-123',
            organization_id: 'org-123',
            email: 'invitee@example.com',
            role: 'member',
            status: 'pending',
            invited_by: 'owner@example.com',
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'secure-token-abc123',
          },
        ];
      });

      it('resends an invitation successfully', async () => {
        // Mock the resend endpoint
        axiosMock
          ?.onPost('/api/organizations/org-123/invitations/secure-token-abc123/resend')
          .reply(200, {});

        // Mock the refresh fetch with updated resend count
        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(200, {
          records: [{ ...mockInvitationRaw, resend_count: 1 }],
        });

        await store.resendInvitation('org-123', 'secure-token-abc123');

        // Should have refreshed invitations
        expect(store.invitations[0].resend_count).toBe(1);
      });

      it('sets loading state during resend', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock
          ?.onPost('/api/organizations/org-123/invitations/secure-token-abc123/resend')
          .reply(async () => {
            await requestPromise;
            return [200, {}];
          });

        axiosMock?.onGet('/api/organizations/org-123/invitations').reply(200, {
          records: [mockInvitationRaw],
        });

        const resendPromise = store.resendInvitation('org-123', 'secure-token-abc123');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await resendPromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('revokeInvitation', () => {
      beforeEach(() => {
        // Pre-populate with invitations
        store.invitations = [
          {
            id: 'inv-123',
            organization_id: 'org-123',
            email: 'invitee@example.com',
            role: 'member',
            status: 'pending',
            invited_by: 'owner@example.com',
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'token-to-revoke',
          },
          {
            id: 'inv-456',
            organization_id: 'org-123',
            email: 'another@example.com',
            role: 'admin',
            status: 'pending',
            invited_by: 'owner@example.com',
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
            token: 'token-to-keep',
          },
        ];
      });

      it('revokes an invitation successfully', async () => {
        axiosMock
          ?.onDelete('/api/organizations/org-123/invitations/token-to-revoke')
          .reply(200, {});

        await store.revokeInvitation('org-123', 'token-to-revoke');

        expect(store.invitations).toHaveLength(1);
        expect(store.invitations[0].token).toBe('token-to-keep');
      });

      it('removes revoked invitation from store', async () => {
        axiosMock
          ?.onDelete('/api/organizations/org-123/invitations/token-to-revoke')
          .reply(200, {});

        const initialCount = store.invitations.length;
        await store.revokeInvitation('org-123', 'token-to-revoke');

        expect(store.invitations).toHaveLength(initialCount - 1);
        expect(
          store.invitations.find((inv) => inv.token === 'token-to-revoke')
        ).toBeUndefined();
      });

      it('sets loading state during revoke', async () => {
        let resolveRequest: (value: unknown) => void;
        const requestPromise = new Promise((resolve) => {
          resolveRequest = resolve;
        });

        axiosMock
          ?.onDelete('/api/organizations/org-123/invitations/token-to-revoke')
          .reply(async () => {
            await requestPromise;
            return [200, {}];
          });

        const revokePromise = store.revokeInvitation('org-123', 'token-to-revoke');
        expect(store.loading).toBe(true);

        resolveRequest!(undefined);
        await revokePromise;

        expect(store.loading).toBe(false);
      });
    });

    describe('Invitation state management', () => {
      it('clears invitations on store reset', () => {
        store.invitations = [
          {
            id: 'inv-123',
            organization_id: 'org-123',
            email: 'test@example.com',
            role: 'member',
            status: 'pending',
            invited_by: 'owner@example.com',
            invited_at: Date.now() / 1000,
            expires_at: Date.now() / 1000 + 604800,
            resend_count: 0,
          },
        ];

        store.$reset();

        expect(store.invitations).toEqual([]);
      });
    });
  });
});
