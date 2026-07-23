// src/tests/stores/csrfStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupBootstrapMock } from '../setup-bootstrap';
import { baseBootstrap } from '@/tests/fixtures/bootstrap.fixture';

import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { beforeEach, describe, expect, it } from 'vitest';
import { nextTick, type ComponentPublicInstance } from 'vue';

describe('CSRF Store', () => {
  let store: ReturnType<typeof useCsrfStore>;
  let _appInstance: ComponentPublicInstance | null;

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    _appInstance = setup.appInstance;
  });

  /**
   * Initialization Tests
   *
   * The CSRF token (shrimp) originates from session[:csrf] on the Ruby backend.
   * It is serialized into the page's bootstrap state and loaded into the
   * bootstrapStore on page load. The csrfStore then synchronizes with this
   * value during initialization.
   *
   * Flow: Backend session[:csrf] -> window.__BOOTSTRAP_ME__.shrimp -> bootstrapStore -> csrfStore
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

  /**
   * Bootstrap Shrimp Watcher Tests
   *
   * When bootstrapStore.refresh() fetches a new bootstrap payload (e.g.,
   * before form submit on anonymous routes), the shrimp ref in bootstrapStore
   * updates. The csrfStore watcher should reactively sync this new value,
   * but only when the store is already initialized and the new value is
   * truthy. This prevents race conditions during initialization and avoids
   * clearing the token with empty values.
   *
   * Flow: bootstrapStore.refresh() -> bootstrapStore.shrimp changes
   *       -> csrfStore watcher fires -> csrfStore.shrimp updated
   */
  describe('Bootstrap shrimp watcher', () => {
    it('syncs shrimp when bootstrapShrimp changes after init', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'initial-token' });

      const store = useCsrfStore();
      store.init();
      expect(store.shrimp).toBe('initial-token');

      // Simulate what bootstrapStore.refresh() does: update shrimp
      bootstrapStore.update({ shrimp: 'refreshed-token' });
      await nextTick();

      expect(store.shrimp).toBe('refreshed-token');
    });

    it('does NOT sync when store is not initialized', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'initial-token' });

      // Create store but do NOT call init()
      const store = useCsrfStore();
      expect(store.shrimp).toBe('');

      // Change bootstrapShrimp — watcher should NOT fire
      bootstrapStore.update({ shrimp: 'new-token' });
      await nextTick();

      // shrimp should remain at default empty value
      expect(store.shrimp).toBe('');
    });

    it('does NOT sync when new bootstrapShrimp is empty', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'initial-token' });

      const store = useCsrfStore();
      store.init();
      expect(store.shrimp).toBe('initial-token');

      // Update bootstrap with empty string — watcher should ignore
      bootstrapStore.update({ shrimp: '' });
      await nextTick();

      // shrimp should keep the previous value
      expect(store.shrimp).toBe('initial-token');
    });

    it('syncs multiple consecutive updates', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'token-1' });

      const store = useCsrfStore();
      store.init();

      bootstrapStore.update({ shrimp: 'token-2' });
      await nextTick();
      expect(store.shrimp).toBe('token-2');

      bootstrapStore.update({ shrimp: 'token-3' });
      await nextTick();
      expect(store.shrimp).toBe('token-3');
    });

    it('resumes syncing after re-init following reset', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.update({ shrimp: 'original' });

      const store = useCsrfStore();
      store.init();
      expect(store.shrimp).toBe('original');

      // Reset clears _initialized
      store.$reset();

      // While not initialized, updates should be ignored
      bootstrapStore.update({ shrimp: 'during-reset' });
      await nextTick();
      expect(store.shrimp).not.toBe('during-reset');

      // Re-init picks up the current bootstrap value
      store.init();
      expect(store.shrimp).toBe('during-reset');

      // After re-init, watcher should work again
      bootstrapStore.update({ shrimp: 'post-reinit' });
      await nextTick();
      expect(store.shrimp).toBe('post-reinit');
    });
  });

  describe('General coverage', () => {
    beforeEach(async () => {
      // Setup bootstrap state with modern fixture (has shrimp: 'test-csrf-token')
      setupBootstrapMock({ initialState: baseBootstrap });

      // Initialize the store
      store = useCsrfStore();
      store.init();
    });

    it('updates shrimp value without mutating bootstrap state', () => {
      const newShrimp = 'new-shrimp-token';

      store.updateShrimp(newShrimp);

      expect(store.shrimp).toBe(newShrimp); // Shrimp should update
      const bootstrapState = (window as Window & { __BOOTSTRAP_ME__?: { shrimp?: string } }).__BOOTSTRAP_ME__;
      expect(bootstrapState?.shrimp).not.toBe(newShrimp); // Window.shrimp should not change
    });
  });
});
