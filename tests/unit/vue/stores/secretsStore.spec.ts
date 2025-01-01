// tests/unit/vue/stores/secretsStore.spec.ts
import { useSecretsStore } from '@/stores/secretsStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

// Response fixtures defined before any test logic
const mockSecretResponse = {
  success: true,
  record: {
    key: 'abc123',
    secret_key: 'abc123',
    is_truncated: false,
    original_size: 100,
    verification: '',
    share_domain: 'example.com',
    is_owner: false,
    has_passphrase: true,
  },
  details: {
    continue: false,
    show_secret: false,
    correct_passphrase: false,
    display_lines: 1,
    one_liner: true,
  },
};

const mockSecretRevealed = {
  ...mockSecretResponse,
  record: {
    ...mockSecretResponse.record,
    secret_value: 'revealed secret',
  },
  details: {
    ...mockSecretResponse.details,
    show_secret: true,
    correct_passphrase: true,
  },
};

describe('secretsStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useSecretsStore>;

  beforeEach(() => {
    setActivePinia(createPinia());
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);
    // Inject mocked axios instance into the store's API
    store = useSecretsStore();
    // Note: You'll need to modify the store to accept an API instance
  });

  afterEach(() => {
    axiosMock.reset();
  });

  it('initializes with empty state', () => {
    expect(store.record).toBeNull();
    expect(store.details).toBeNull();
    expect(store.isLoading).toBe(false);
    expect(store.error).toBeNull();
  });

  describe('fetch', () => {
    it('loads initial secret details successfully', async () => {
      axiosMock.onGet('/api/v2/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      expect(store.record).toEqual(mockSecretResponse.record);
      expect(store.details).toEqual(mockSecretResponse.details);
      expect(store.isLoading).toBe(false);
      expect(store.error).toBeNull();
    });

    it('handles validation errors', async () => {
      axiosMock.onGet('/api/v2/secret/abc123').reply(200, { invalid: 'data' });

      await expect(store.fetch('abc123')).rejects.toThrow();
      expect(store.error).toBeTruthy();
    });

    it('handles network errors', async () => {
      axiosMock.onGet('/api/v2/secret/abc123').networkError();

      await expect(store.fetch('abc123')).rejects.toThrow();
      expect(store.isLoading).toBe(false);
    });
  });

  describe('reveal', () => {
    it('reveals secret with passphrase', async () => {
      axiosMock.onPost('/api/v2/secret/abc123/reveal').reply(200, mockSecretRevealed);

      await store.reveal('abc123', 'password');

      expect(store.record?.secret_value).toBe('revealed secret');
      expect(store.details?.show_secret).toBe(true);
      expect(store.isLoading).toBe(false);
      expect(store.error).toBeNull();
    });

    it('preserves state on error', async () => {
      // Setup initial state
      axiosMock.onGet('/api/v2/secret/abc123').reply(200, mockSecretResponse);
      await store.fetch('abc123');
      const initialState = { record: store.record, details: store.details };

      // Force error on reveal
      axiosMock.onPost('/api/v2/secret/abc123/reveal').networkError();

      await expect(store.reveal('abc123', 'wrong')).rejects.toThrow();
      expect(store.record).toEqual(initialState.record);
      expect(store.details).toEqual(initialState.details);
    });
  });

  describe('clearSecret', () => {
    it('resets store state', async () => {
      axiosMock.onGet('/api/v2/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');
      store.clearSecret();

      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
      expect(store.error).toBeNull();
    });
  });
});
