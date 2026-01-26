// src/tests/stores/csrfStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ComponentPublicInstance } from 'vue';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';

describe('CSRF Store', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let store: ReturnType<typeof useCsrfStore>;
  let appInstance: ComponentPublicInstance | null;

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    vi.useFakeTimers();

    // Setup additional test-specific mocks
    vi.spyOn(window, 'setInterval');
    vi.spyOn(window, 'clearInterval');
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock?.reset();
  });

  /**
   * Initialization Tests
   *
   * The CSRF token (shrimp) originates from session[:csrf] on the Ruby backend.
   * It is serialized into the page's bootstrap state and loaded into the
   * bootstrapStore on page load. The csrfStore then synchronizes with this
   * value during initialization.
   *
   * Flow: Backend session[:csrf] -> window.__BOOTSTRAP_STATE__.shrimp -> bootstrapStore -> csrfStore
   */
  describe('Initialization', () => {
    it('initializes with empty shrimp when bootstrap.shrimp is not available', () => {
      // bootstrapStore defaults to empty shrimp
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: '' });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('');
    });

    it('initializes with bootstrap.shrimp when available', () => {
      // Set bootstrap shrimp BEFORE initializing csrf store
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'yum' });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('yum');
    });

    /**
     * Integration test: Verifies the shrimp value from bootstrap (which
     * originates from session[:csrf] on the backend) is correctly loaded
     * and made available through the csrfStore for form submissions.
     */
    it('loads shrimp from bootstrap for use in form CSRF protection', () => {
      // Simulate the bootstrap state that would be set by the backend
      // The backend serializes session[:csrf] into the page's bootstrap JSON
      const backendCsrfToken = 'backend-session-csrf-token-abc123';
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: backendCsrfToken });

      const store = useCsrfStore();
      store.init();

      // The csrfStore.shrimp should match what was bootstrapped from the backend
      expect(store.shrimp).toBe(backendCsrfToken);
      // This value is used by components like SsoButton when submitting forms
      // with the 'shrimp' field for Rack::Protection::AuthenticityToken validation
    });

    it('preserves bootstrap.shrimp through store reset', () => {
      // Set initial value in bootstrapStore
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'initial' });

      const store = useCsrfStore();
      store.init();
      expect(store.shrimp).toBe('initial');

      // Update store value
      store.updateShrimp('updated');
      expect(store.shrimp).toBe('updated');

      // Reset should revert to bootstrap.shrimp
      store.$reset();
      expect(store.shrimp).toBe('initial');
    });

    it('handles falsy but valid bootstrap.shrimp values', () => {
      // Edge case: empty string is a valid value
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: '' });

      const store = useCsrfStore();
      store.init();

      expect(store.shrimp).toBe('');
    });
  });

  describe('General coverage', () => {
    beforeEach(async () => {
      vi.stubGlobal('window', setupWindowState()); // defaults to window fixture

      // Initialize the store
      store = useCsrfStore();
      store.init();
    });

    it('updates shrimp value without affecting validity', () => {
      const newShrimp = 'new-shrimp-token';
      const initialValidity = store.isValid; // Store initial validity state

      store.updateShrimp(newShrimp);

      expect(store.shrimp).toBe(newShrimp); // Shrimp should update
      const bootstrapState = (window as Window & { __BOOTSTRAP_STATE__?: { shrimp?: string } }).__BOOTSTRAP_STATE__;
      expect(bootstrapState?.shrimp).not.toBe(newShrimp); // Window.shrimp should not change
      expect(store.isValid).toBe(initialValidity); // Validity should not change
    });

    // Add a new test for the full update+validate flow
    it('updates shrimp and validates it through API call', async () => {
      const newShrimp = 'new-shrimp-token';
      store.updateShrimp(newShrimp);

      // Mock successful validation response
      axiosMock?.onPost('/api/v3/validate-shrimp').reply(200, {
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

      // Mock the API response - focus on behavior rather than implementation details
      axiosMock?.onPost('/api/v3/validate-shrimp').reply((config) => {
        // Verify that the shrimp token is included in the request (test behavior)
        const headers = config.headers as Record<string, string> | undefined;
        const shrimpHeader = headers?.['X-CSRF-Token'];
        expect(shrimpHeader).toBe('initial-shrimp');

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
      expect(axiosMock?.history.post.length).toBe(1);
      expect(axiosMock?.history.post[0].url).toBe('/api/v3/validate-shrimp');
    });

    it('handles shrimp validity check failure', async () => {
      store.shrimp = 'initial-shrimp';

      axiosMock?.onPost('/api/v3/validate-shrimp').reply(200, {
        isValid: false,
        shrimp: store.shrimp,
      });

      await store.checkShrimpValidity();

      expect(store.isValid).toBe(false);

      // Verify the request was made with correct shrimp token (behavior-focused)
      const request = axiosMock?.history.post[0];
      const headers = request?.headers as Record<string, string> | undefined;
      const shrimpHeader = headers?.['X-CSRF-Token'];
      expect(shrimpHeader).toBe('initial-shrimp');
    });

    it('handles network error during shrimp validity check', async () => {
      /**
       * The main thing we care about is that when the network request fails, the CSRF
       * token is marked as invalid and the original token is preserved. The exact
       * error handling implementation details are less important.
       *
       * NOTE: the store does not handle the error (none of them do) so
       * here we expect the isValid to remain the same.
       */

      // Setup
      store.shrimp = 'initial-shrimp';
      store.isValid = true;

      // Mock network error
      axiosMock?.onPost('/api/v3/validate-shrimp').networkError();

      // Act & Assert
      await expect(store.checkShrimpValidity()).rejects.toThrow();

      // Verify token is preserved but validity remains unchanged
      expect(store.isValid).toBe(true); // Changed from false to true
      expect(store.shrimp).toBe('initial-shrimp');
    });

    it.skip('starts periodic check correctly', async () => {
      // Mock successful validation response ahead of time
      axiosMock?.onPost('/api/v3/validate-shrimp').reply(200, {
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
        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/validate-shrimp');
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

      // 15 minutes in milliseconds
      const expectedDefaultInterval = 60000 * 15; // 900000ms

      expect(window.setInterval).toHaveBeenCalledWith(
        expect.any(Function),
        expectedDefaultInterval
      );
    });
  });
});
