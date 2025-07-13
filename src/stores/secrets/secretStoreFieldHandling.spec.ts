// tests/unit/vue/stores/secrets/secretStoreFieldHandling.spec.ts

// tests/unit/vue/stores/secretStore.spec.ts
import { useSecretStore } from '@/stores/secretStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
    mockSecretRecord,
    mockSecretResponse,
    mockSecretRevealed,
} from '../../fixtures/metadata.fixture';

describe('secretStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useSecretStore>;

  beforeEach(() => {
    setActivePinia(createPinia());
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);
    // Inject mocked axios instance into the store's API
    store = useSecretStore();
 });

  afterEach(() => {
    axiosMock.reset();
  });

  describe('secretStore field handling', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useSecretStore>;

    beforeEach(() => {
      setActivePinia(createPinia());
      const axiosInstance = axios.create();
      axiosMock = new AxiosMockAdapter(axiosInstance);
      store = useSecretStore();
      store.init();
    });

    afterEach(() => {
      axiosMock.reset();
      store.$reset();
    });

    describe('is_owner field', () => {
      it('preserves true value from API', async () => {
        const response = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: true },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(true);
      });

      it('preserves false value from API', async () => {
        const response = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: false },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

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
        axiosMock
          .onGet(`/api/v2/secret/${testKey}`)
          .reply(200, mockResponseWithoutLifespan);

        await store.fetch(testKey);

        expect(store.record?.lifespan).toBeNull();
      });

      it('maintains is_owner state after reveal operation', async () => {
        // First set initial state with is_owner: true
        const initialResponse = {
          ...mockSecretResponse,
          details: { ...mockSecretResponse.details, is_owner: true },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');

        // Then reveal the secret
        const revealResponse = {
          ...mockSecretRevealed,
          details: { ...mockSecretRevealed.details, is_owner: true },
        };
        axiosMock.onPost('/api/v2/secret/abc123/reveal').reply(200, revealResponse);

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
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

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
            lifespan: '24 hours',
            secret_ttl: 86400, // 24 hours in seconds
          },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBe('24 hours'); // Test exact match
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
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

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
            lifespan: '24 hours',
            secret_ttl: 86400,
          },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');
        const initialLifespan = store.record?.lifespan;

        // Then reveal
        const revealResponse = {
          ...mockSecretRevealed,
          record: {
            ...mockSecretRevealed.record,
            lifespan: '24 hours',
            secret_ttl: 86400,
          },
        };
        axiosMock.onPost('/api/v2/secret/abc123/reveal').reply(200, revealResponse);

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
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBeNull();
      });

      it('calculates TTL duration in seconds', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: 3600, // 1 hour
            lifespan: '1 hour',
          },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, response);

        await store.fetch('abc123');
        expect(store.record?.lifespan).toBe('1 hour');
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
            lifespan: '24 hours',
            secret_ttl: 86400,
          },
          details: {
            ...mockSecretResponse.details,
            is_owner: true,
          },
        };
        axiosMock.onGet('/api/v2/secret/abc123').reply(200, initialResponse);
        await store.fetch('abc123');

        // Verify both fields
        expect(store.details?.is_owner).toBe(true);
        expect(store.record?.lifespan).toMatch(/24 hours/);
        expect(store.record?.secret_ttl).toBe(86400);

        // Clear and verify reset
        store.clear();
        expect(store.details?.is_owner).toBeUndefined();
        expect(store.record?.lifespan).toBeUndefined();

        // Fetch again and verify restoration
        await store.fetch('abc123');
        expect(store.details?.is_owner).toBe(true);
        expect(store.record?.lifespan).toMatch(/24 hours/);
      });
    });
  });
});
