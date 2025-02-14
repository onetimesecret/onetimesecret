import { useCsrfStore } from '@/stores/csrfStore';
import { createApi } from '@/api';
import { createTestingPinia } from '@pinia/testing';
import AxiosMockAdapter from 'axios-mock-adapter';
import { setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';

describe('CSRF Store', () => {
  let axiosMock: AxiosMockAdapter;
  let axiosInstance: ReturnType<typeof createApi>;
  let store: ReturnType<typeof useCsrfStore>;

  describe('CSRF Store initialization', () => {
    beforeEach(() => {
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      setActivePinia(pinia);

      axiosInstance = createApi();
      axiosMock = new AxiosMockAdapter(axiosInstance);
    });

    afterEach(() => {
      vi.unstubAllGlobals();
    });

    it('initializes with empty shrimp when window.shrimp is not available', () => {
      // Explicitly ensure window.shrimp is undefined
      vi.stubGlobal('window', { shrimp: undefined });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('');
    });

    it('initializes with window.shrimp when available', () => {
      // Set window.shrimp before store creation
      vi.stubGlobal('window', { shrimp: 'yum' });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('yum');
    });

    it('preserves window.shrimp through store reset', () => {
      // Set initial value
      vi.stubGlobal('window', { shrimp: 'initial' });

      const store = useCsrfStore();
      store.init();
      expect(store.shrimp).toBe('initial');

      // Update store value
      store.updateShrimp('updated');
      expect(store.shrimp).toBe('updated');

      // Reset should revert to window.shrimp
      store.$reset();
      expect(store.shrimp).toBe('initial');
    });

    it('handles falsy but valid window.shrimp values', () => {
      // Edge case: empty string is a valid value
      vi.stubGlobal('window', { shrimp: '' });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('');
    });
  });

  describe('Original tests', () => {
    beforeEach(() => {
      const app = createApp({});
      // `createTestingPinia()` creates a testing version of Pinia that mocks all
      // actions by default. Use `createTestingPinia({ stubActions: false })` if
      // you want to test actions. Otherwise they don't actually get called.
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      setActivePinia(pinia);

      // Create a fresh axios instance and mock adapter for testing
      axiosInstance = createApi();
      axiosMock = new AxiosMockAdapter(axiosInstance);

      store = useCsrfStore();
      store.init();

      vi.useFakeTimers();
      vi.spyOn(window, 'setInterval');
      vi.spyOn(window, 'clearInterval');
      vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    afterEach(() => {
      vi.restoreAllMocks();
      vi.useRealTimers();
      axiosMock.restore();
    });

    it('initializes with correct values', () => {
      expect(store.shrimp).toBe('');
      expect(store.isValid).toBe(false);
      expect(store.intervalChecker).toBeNull();
    });

    it('initializes with window.shrimp if available', () => {
      // Set window.shrimp BEFORE creating store
      vi.stubGlobal('window', { shrimp: 'yum' });

      // Create fresh store instance after window.shrimp is set
      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('yum');

      vi.unstubAllGlobals();
    });

    it('updates shrimp value without affecting validity', () => {
      const newShrimp = 'new-shrimp-token';
      const initialValidity = store.isValid; // Store initial validity state

      store.updateShrimp(newShrimp);

      expect(store.shrimp).toBe(newShrimp); // Shrimp should update
      expect(window.shrimp).not.toBe(newShrimp); // Window.shrimp should not change
      expect(store.isValid).toBe(initialValidity); // Validity should not change
    });

    // Add a new test for the full update+validate flow
    it('updates shrimp and validates it through API call', async () => {
      const newShrimp = 'new-shrimp-token';
      store.updateShrimp(newShrimp);

      // Mock successful validation response
      axiosMock.onPost('/api/v2/validate-shrimp').reply(200, {
        isValid: true,
        shrimp: newShrimp,
      });

      await store.checkShrimpValidity();

      expect(store.shrimp).toBe(newShrimp);
      expect(store.isValid).toBe(true);
    });

    it('checks shrimp validity successfully', async () => {
      // Setup initial state
      store.shrimp = 'initial-shrimp';

      // Mock the API response
      axiosMock.onPost('/api/v2/validate-shrimp').reply((config) => {
        // Verify request headers
        expect(config.headers?.['Content-Type']).toBe('application/json');
        expect(config.headers?.['O-Shrimp']).toBe('initial-shrimp');

        // Return successful response
        return [
          200,
          {
            isValid: true,
            shrimp: 'new-shrimp-token',
          },
        ];
      });

      // Perform the action
      await store.checkShrimpValidity();

      // Verify the results
      expect(store.isValid).toBe(true);
      expect(store.shrimp).toBe('new-shrimp-token');

      // Verify request was made
      expect(axiosMock.history.post.length).toBe(1);
      expect(axiosMock.history.post[0].url).toBe('/api/v2/validate-shrimp');
    });

    it('handles shrimp validity check failure', async () => {
      store.shrimp = 'initial-shrimp';

      axiosMock.onPost('/api/v2/validate-shrimp').reply(200, {
        isValid: false,
        shrimp: store.shrimp,
      });

      await store.checkShrimpValidity();

      expect(store.isValid).toBe(false);

      const request = axiosMock.history.post[0];
      expect(request.headers).toMatchObject({
        'Content-Type': 'application/json',
        'O-Shrimp': 'initial-shrimp',
      });
    });

    it('handles network error during shrimp validity check', async () => {
      /**
       * The main thing we care about is that when the network request fails, the CSRF
       * token is marked as invalid and the original token is preserved. The exact
       * error handling implementation details are less important.
       */

      // Setup
      store.shrimp = 'initial-shrimp';
      store.isValid = true;

      // Mock network error
      axiosMock.onPost('/api/v2/validate-shrimp').networkError();

      // Act & Assert
      await expect(store.checkShrimpValidity()).rejects.toThrow();

      // Verify token is invalidated but preserved
      expect(store.isValid).toBe(false);
      expect(store.shrimp).toBe('initial-shrimp');
    });

    it('starts periodic check correctly', async () => {
      // Mock successful validation response ahead of time
      axiosMock.onPost('/api/v2/validate-shrimp').reply(200, {
        isValid: true,
        shrimp: 'test-shrimp',
      });

      // Start periodic check
      store.startPeriodicCheck(30000);

      // Verify interval was set correctly
      expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 30000);
      expect(store.intervalChecker).not.toBeNull();

      // Advance time and wait for next tick to let any promises resolve
      vi.advanceTimersByTime(30000);
      await vi.waitFor(() => {
        // Verify the API call was made
        expect(axiosMock.history.post.length).toBe(1);
        expect(axiosMock.history.post[0].url).toBe('/api/v2/validate-shrimp');
      });

      // Verify store was updated
      expect(store.isValid).toBe(true);
      expect(store.shrimp).toBe('test-shrimp');
    });

    it('stops periodic check correctly', () => {
      store.startPeriodicCheck();
      expect(store.intervalChecker).not.toBeNull();

      store.stopPeriodicCheck();

      expect(window.clearInterval).toHaveBeenCalled();
      expect(store.intervalChecker).toBeNull();
    });

    it('restarts periodic check when called multiple times', () => {
      store.startPeriodicCheck(30000);
      const firstInterval = store.intervalChecker;

      store.startPeriodicCheck(60000);
      const secondInterval = store.intervalChecker;

      expect(firstInterval).not.toBe(secondInterval);
      expect(window.clearInterval).toHaveBeenCalledWith(firstInterval);
      expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 60000);
    });

    it('uses default interval when not specified', () => {
      store.startPeriodicCheck();

      expect(window.setInterval).toHaveBeenCalledWith(expect.any(Function), 60000);
    });
  });
});
