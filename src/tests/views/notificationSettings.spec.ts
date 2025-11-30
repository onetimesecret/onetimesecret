// src/tests/views/NotificationSettings.spec.ts

import { useAccountStore } from '@/stores/accountStore';
import { setupTestPinia } from '../setup';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type AxiosMockAdapter from 'axios-mock-adapter';

/**
 * Creates a complete account response fixture that matches the Zod schema
 */
function createAccountFixture(overrides: { notify_on_reveal?: boolean } = {}) {
  const now = new Date().toISOString();
  return {
    record: {
      cust: {
        identifier: 'test-cust-id',
        objid: 'cust:test-cust-123',
        extid: 'ext-test-123',
        created: now,
        updated: now,
        role: 'customer',
        email: 'test@example.com',
        verified: 'true',
        active: 'true',
        contributor: 'false',
        secrets_created: '0',
        secrets_burned: '0',
        secrets_shared: '0',
        emails_sent: '0',
        last_login: null,
        locale: 'en',
        notify_on_reveal: overrides.notify_on_reveal ? 'true' : 'false',
      },
      apitoken: 'test-api-token-123',
    },
  };
}

describe('NotificationSettings', () => {
  let axiosMock: AxiosMockAdapter | null;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.restoreAllMocks();
  });

  describe('accountStore.updateNotificationPreference', () => {
    it('sends correct payload to update notification preference', async () => {
      // Mock the update endpoint
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(200, {
        record: { notify_on_reveal: true },
        old_value: false,
      });

      // Mock the account fetch endpoint with complete fixture
      axiosMock!.onGet('/api/account/account').reply(200, createAccountFixture({ notify_on_reveal: true }));

      const store = useAccountStore();

      await store.updateNotificationPreference('notify_on_reveal', true);

      // Verify the update was called with correct payload
      expect(axiosMock!.history.post).toHaveLength(1);
      expect(axiosMock!.history.post[0].url).toBe(
        '/api/account/account/update-notification-preference'
      );
      expect(JSON.parse(axiosMock!.history.post[0].data)).toEqual({
        field: 'notify_on_reveal',
        value: true,
      });
    });

    it('refetches account data after successful update', async () => {
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(200, {
        record: { notify_on_reveal: true },
        old_value: false,
      });

      axiosMock!.onGet('/api/account/account').reply(200, createAccountFixture({ notify_on_reveal: true }));

      const store = useAccountStore();

      await store.updateNotificationPreference('notify_on_reveal', true);

      // Verify fetch was called after update
      expect(axiosMock!.history.get).toHaveLength(1);
      expect(axiosMock!.history.get[0].url).toBe('/api/account/account');
    });

    it('can toggle preference from true to false', async () => {
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(200, {
        record: { notify_on_reveal: false },
        old_value: true,
      });

      axiosMock!.onGet('/api/account/account').reply(200, createAccountFixture({ notify_on_reveal: false }));

      const store = useAccountStore();

      await store.updateNotificationPreference('notify_on_reveal', false);

      expect(JSON.parse(axiosMock!.history.post[0].data)).toEqual({
        field: 'notify_on_reveal',
        value: false,
      });
    });

    it('throws error on server failure', async () => {
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(500, {
        message: 'Internal Server Error',
      });

      const store = useAccountStore();

      await expect(store.updateNotificationPreference('notify_on_reveal', true)).rejects.toThrow();

      // Verify no fetch was attempted after failed update
      expect(axiosMock!.history.get).toHaveLength(0);
    });

    it('throws error on network failure', async () => {
      axiosMock!.onPost('/api/account/account/update-notification-preference').networkError();

      const store = useAccountStore();

      await expect(store.updateNotificationPreference('notify_on_reveal', true)).rejects.toThrow();
    });

    it('handles invalid field gracefully', async () => {
      // Server returns 400 for invalid field
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(400, {
        message: 'Invalid field',
      });

      const store = useAccountStore();

      await expect(
        store.updateNotificationPreference('invalid_field', true)
      ).rejects.toThrow();
    });

    it('handles unauthenticated user', async () => {
      // Server returns 401 for unauthenticated user
      axiosMock!.onPost('/api/account/account/update-notification-preference').reply(401, {
        message: 'Not authenticated',
      });

      const store = useAccountStore();

      await expect(store.updateNotificationPreference('notify_on_reveal', true)).rejects.toThrow();
    });
  });

  describe('notification preference state', () => {
    it('account state reflects notify_on_reveal after fetch', async () => {
      axiosMock!.onGet('/api/account/account').reply(200, createAccountFixture({ notify_on_reveal: true }));

      const store = useAccountStore();
      await store.fetch();

      expect(store.account?.cust?.notify_on_reveal).toBe(true);
    });

    it('account state defaults notify_on_reveal to false when not present', async () => {
      axiosMock!.onGet('/api/account/account').reply(200, createAccountFixture({ notify_on_reveal: false }));

      const store = useAccountStore();
      await store.fetch();

      // The schema transform should default to false
      expect(store.account?.cust?.notify_on_reveal).toBe(false);
    });
  });
});
