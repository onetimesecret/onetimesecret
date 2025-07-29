// src/tests/stores/secrets/secretStoreFieldHandling.spec.ts

// IMPORTANT: This test uses centralized test setup pattern
// DO NOT revert to individual axios.create() - use setupTestPinia() instead
import { useSecretStore } from '@/stores/secretStore';
import { setupTestPinia } from '../../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';
import type { ComponentPublicInstance } from 'vue';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  mockSecretRecord,
  mockSecretResponse,
  mockSecretRevealed,
} from '../../fixtures/metadata.fixture';

describe('secretStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let store: ReturnType<typeof useSecretStore>;
  let appInstance: ComponentPublicInstance | null;

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    // Initialize the store
    store = useSecretStore();
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('secretStore field handling', () => {
    describe('is_owner field', () => {
      it('preserves true value from API', async () => {
        const response = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: true },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(true);
      });

      it('preserves false value from API', async () => {
        const response = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: false },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(false);
      });

      // This highlights an important lesson: when tests fail with 404s, always
      // verify your mock endpoints match what the code actually calls.
      it('handles missing lifespan field from API', async () => {
        const testKey = 'abc123';

        const mockResponseWithoutLifespan = {
          success: true, // Add this to match mockSecretResponse structure
          record: {
            ...mockSecretRecord,
            lifespan: null, // Explicitly null per schema
          },
          details: {
            continue: false,
            is_owner: false,
            show_secret: false,
            correct_passphrase: false,
            display_lines: 1,
            one_liner: true,
          },
        };

        // Use consistent API endpoint
        axiosMock?.onGet(`/api/v2/secret/${testKey}`).reply(200, mockResponseWithoutLifespan);

        await store.fetch(testKey);

        expect(store.record?.lifespan).toBeNull();
      });

      it('maintains is_owner state after reveal operation', async () => {
        // First set initial state with is_owner: true
        const initialResponse = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: true },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');

        // Then reveal the secret
        const revealResponse = {
          ...mockSecretRevealed,
          details: { ...mockSecretRevealed.details, is_owner: true },
        };
        axiosMock?.onPost('/api/v2/secret/abc123/reveal').reply(200, revealResponse);

        await store.reveal('abc123', 'password');
        expect(store.details?.is_owner).toBe(true);
      });

      it('handles missing is_owner field by defaulting to false', async () => {
        const response = {
          ...mockSecretResponse,
          details: {
            ...mockSecretResponse.details,
            // @ts-expect-error - intentionally omitting is_owner
            is_owner: undefined,
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(false);
      });
    });

    describe('lifespan field', () => {
      it('preserves static duration from API', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: 86400, // Schema expects number (seconds), not string
            secret_ttl: 86400, // 24 hours in seconds
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBe(86400); // Test exact numeric match
        expect(store.record?.secret_ttl).toBe(86400); // Verify TTL is preserved
      });

      it('handles null lifespan value', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: null,
            secret_ttl: null,
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBeNull();
        expect(store.record?.secret_ttl).toBeNull();
      });

      it('maintains consistent lifespan after reveal', async () => {
        // First fetch
        const initialResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: 86400, // Schema expects number (seconds)
            secret_ttl: 86400,
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');
        const initialLifespan = store.record?.lifespan;

        // Then reveal
        const revealResponse = {
          ...mockSecretRevealed,
          record: {
            ...mockSecretRevealed.record,
            lifespan: 86400, // Schema expects number (seconds)
            secret_ttl: 86400,
          },
        };
        axiosMock?.onPost('/api/v2/secret/abc123/reveal').reply(200, revealResponse);

        await store.reveal('abc123', 'password');
        expect(store.record?.lifespan).toBe(initialLifespan);
      });

      it('handles null lifespan value', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: null,
            secret_ttl: null,
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBeNull();
      });

      it('calculates TTL duration in seconds', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: 3600, // 1 hour
            lifespan: 3600, // Schema expects number (seconds), not string
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBe(3600); // Test exact numeric match
        expect(store.record?.secret_ttl).toBe(3600);
      });
    });

    describe('field interaction', () => {
      it('preserves both fields through store operations', async () => {
        // Setup initial state
        const initialResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: 86400, // Schema expects number (seconds)
            secret_ttl: 86400,
          },
          details: {
            ...mockSecretResponse.details,
            is_owner: true,
          },
        };
        axiosMock?.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');

        // Verify both fields
        expect(store.details?.is_owner).toBe(true);
        expect(store.record?.lifespan).toBe(86400); // Schema expects number, not string
        expect(store.record?.secret_ttl).toBe(86400);

        // Clear and verify reset
        store.clear();
        expect(store.details?.is_owner).toBeUndefined();
        expect(store.record?.lifespan).toBeUndefined();

        // Fetch again and verify restoration
        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(true);
        expect(store.record?.lifespan).toBe(86400); // Schema expects number, not string
      });
    });
  });
});
