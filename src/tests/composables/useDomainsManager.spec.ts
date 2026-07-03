// src/tests/composables/useDomainsManager.spec.ts

import { useDomainsManager } from '@/shared/composables/useDomainsManager';
import { ApplicationError, classifyError } from '@/schemas/errors';
import { AxiosError, AxiosHeaders } from 'axios';
import { mockDomains, newDomainData } from '@/tests/fixtures/domains.fixture';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref, computed, defineComponent } from 'vue';
import { mount } from '@vue/test-utils';

import type { MockDependencies } from '../types.d';

// Capture entitlement-aware onError callback from the second useAsyncHandler call.
// Must be mock-prefixed for vitest hoisting to allow reference in vi.mock factory.
const mockEntitlementCapture: {
  onError: ((err: ApplicationError) => void) | null;
} = { onError: null };

// Mock Setup
const mockDomainsArray = Object.values(mockDomains);
const mockDependencies: MockDependencies = {
  router: {
    back: vi.fn(),
    push: vi.fn(),
  },
  confirmDialog: vi.fn(),
  errorHandler: {
    handleError: vi.fn(),
    wrap: vi.fn(),
    createError: vi.fn((message: string, type: string, severity: string) => ({
      message,
      type,
      severity,
    })),
  },
  domainsStore: {
    init: vi.fn(),
    records: ref(mockDomainsArray),
    details: ref({}),
    count: ref(mockDomainsArray.length),
    domains: computed(() => mockDomainsArray),
    initialized: false,
    recordCount: vi.fn(() => mockDomainsArray.length),
    addDomain: vi.fn(),
    deleteDomain: vi.fn(),
    getDomain: vi.fn(),
    verifyDomain: vi.fn(),
    updateDomain: vi.fn(),
    updateDomainBrand: vi.fn(),
    getBrandSettings: vi.fn(),
    updateBrandSettings: vi.fn(),
    uploadLogo: vi.fn(),
    fetchLogo: vi.fn(),
    removeLogo: vi.fn(),
    putHomepageConfig: vi.fn(),
    fetchList: vi.fn(),
    refreshRecords: vi.fn(),
    $reset: vi.fn(),
    isLoading: ref(false),
    error: ref(null),
  },
  notificationsStore: {
    show: vi.fn(),
  },
};

// Mock for useDomainContext
const mockDomainContext = {
  setContext: vi.fn(),
  currentContext: { value: { domain: '', isCanonical: true, displayName: '', extid: undefined } },
  isContextActive: { value: true },
  hasMultipleContexts: { value: false },
  availableDomains: { value: [] },
  resetContext: vi.fn(),
  refreshDomains: vi.fn(),
  getDomainDisplayName: vi.fn(),
  getExtidByDomain: vi.fn(),
  initialized: Promise.resolve(),
};

// Mock imports
// Track current route params for dynamic mocking
let currentRouteParams: Record<string, string> = { orgid: 'test-org-id' };

vi.mock('vue-router', () => ({
  useRouter: () => mockDependencies.router,
  useRoute: () => ({
    params: currentRouteParams,
  }),
}));

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: () => mockDomainContext,
}));

vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => mockDependencies.domainsStore,
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: (store: any) => ({
      records: store.records,
      details: store.details,
    }),
  };
});

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => mockDependencies.notificationsStore,
}));

vi.mock('@/shared/composables/useConfirmDialog', () => ({
  useConfirmDialog: () => mockDependencies.confirmDialog,
}));

vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: (options?: any) => {
    // When the composable creates the entitlement-aware handler (notify: false),
    // capture its onError so tests can invoke it with classified errors.
    if (options?.notify === false && options?.onError) {
      mockEntitlementCapture.onError = options.onError;
    }
    return mockDependencies.errorHandler;
  },
  createError: (message: string, type: string, severity: string) => ({
    message,
    type,
    severity,
  }),
}));

// ADR-014 pass-through i18n: keys render AS-IS (raw key strings), no translations.
// This composable test mocks vue-i18n wholesale (it does not install an i18n plugin),
// so the shared createTestI18n() helper does not apply here. The equivalent
// pass-through is an identity t() — mirroring the helper's `missing: (_, key) => key`.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
  createI18n: vi.fn(() => ({
    global: {
      t: vi.fn((key: string) => key),
    },
  })),
}));

// Helper function to test composables within Vue composition context
function mountComposable<T>(composableFn: () => T): T {
  let result: T;
  const TestComponent = defineComponent({
    setup() {
      result = composableFn();
      return () => null;
    },
  });
  mount(TestComponent, { global: { plugins: [createPinia()] } });
  return result!;
}

describe('useDomainsManager', () => {
  beforeEach(() => {
    setActivePinia(createPinia());

    vi.clearAllMocks();
    // Reset reactive refs
    mockDependencies.domainsStore.records.value = mockDomainsArray;
    mockDependencies.errorHandler.wrap.mockImplementation(async (fn) => await fn());
    // Reset domain context mock
    mockDomainContext.setContext.mockClear();
    // Reset route params to default
    currentRouteParams = { orgid: 'test-org-id' };
    // Reset entitlement capture
    mockEntitlementCapture.onError = null;
  });

  describe('domain addition', () => {
    describe('handleAddDomain', () => {
      it('successfully adds a new domain and navigates to verification', async () => {
        // Store's addDomain now returns { record, details }
        mockDependencies.domainsStore.addDomain.mockResolvedValueOnce({
          record: newDomainData,
          details: { domain_context: newDomainData.display_domain },
        });

        const { handleAddDomain } = mountComposable(() => useDomainsManager());
        const result = await handleAddDomain(newDomainData.domainid);

        // handleAddDomain returns just the record
        expect(result).toEqual(newDomainData);
        expect(mockDependencies.domainsStore.addDomain).toHaveBeenCalledWith(
          newDomainData.domainid,
          'test-org-id'  // orgid from route params
        );
        expect(mockDependencies.router.push).toHaveBeenCalledWith({
          name: 'DomainVerify',
          params: { orgid: 'test-org-id', extid: newDomainData.extid },
        });
        expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
          'web.domains.domain_added_successfully',
          'success',
          'top'
        );
      });

      it('auto-switches domain context to newly added domain using server-provided context', async () => {
        // Store's addDomain now returns { record, details }
        mockDependencies.domainsStore.addDomain.mockResolvedValueOnce({
          record: newDomainData,
          details: { domain_context: newDomainData.display_domain },
        });

        const { handleAddDomain } = mountComposable(() => useDomainsManager());
        await handleAddDomain(newDomainData.domainid);

        // Verify setContext was called with domain_context from server and skipBackendSync=true
        expect(mockDomainContext.setContext).toHaveBeenCalledWith(
          newDomainData.display_domain, true,
        );
        expect(mockDomainContext.setContext).toHaveBeenCalledTimes(1);
      });

      it('falls back to display_domain when domain_context not in response', async () => {
        // Store's addDomain returns { record, details } without domain_context
        mockDependencies.domainsStore.addDomain.mockResolvedValueOnce({
          record: newDomainData,
          details: {},
        });

        const { handleAddDomain } = mountComposable(() => useDomainsManager());
        await handleAddDomain(newDomainData.domainid);

        // Verify setContext was called with display_domain and without skipBackendSync
        expect(mockDomainContext.setContext).toHaveBeenCalledWith(newDomainData.display_domain);
        expect(mockDomainContext.setContext).toHaveBeenCalledTimes(1);
      });

      it('does not switch domain context when domain addition fails', async () => {
        // Store returns null (no record)
        mockDependencies.domainsStore.addDomain
          .mockResolvedValueOnce({ record: null, details: {} });
        mockDependencies.errorHandler.createError.mockImplementation((message, type, severity) => ({
          message,
          type,
          severity,
          name: 'Error',
        }));

        const { handleAddDomain } = mountComposable(() => useDomainsManager());
        await handleAddDomain('failing-domain.com');

        // Verify setContext was NOT called when domain addition fails
        expect(mockDomainContext.setContext).not.toHaveBeenCalled();
      });

      describe('error handling', () => {
        it('handles API errors', async () => {
          const apiError = new Error('API Error');
          // Setup wrap to return null on error
          mockDependencies.errorHandler.wrap.mockImplementation(async (fn) => {
            try {
              return await fn();
            } catch (error) {
              mockDependencies.errorHandler.handleError(error);
              return null;
            }
          });
          mockDependencies.domainsStore.addDomain.mockRejectedValueOnce(apiError);

          const { handleAddDomain } = mountComposable(() => useDomainsManager());
          const result = await handleAddDomain(newDomainData.domainid);

          expect(result).toBeNull();
          expect(mockDependencies.errorHandler.handleError).toHaveBeenCalledWith(apiError);
          expect(mockDependencies.router.push).not.toHaveBeenCalled();
        });

        it('handles validation errors', async () => {
          const validationError = {
            message: 'Invalid domain',
            type: 'human',
            severity: 'error',
          } as ApplicationError;

          mockDependencies.domainsStore.addDomain.mockRejectedValueOnce(validationError);
          const { handleAddDomain } = mountComposable(() => useDomainsManager());

          // Expect the operation to throw
          await expect(handleAddDomain(newDomainData.domainid)).rejects.toMatchObject({
            message: 'Invalid domain',
            type: 'human',
            severity: 'error',
          });
        });
      });
    });
  });

  describe('domain deletion', () => {
    describe('deleteDomain', () => {
      it('successfully deletes a domain after confirmation', async () => {
        mockDependencies.confirmDialog.mockResolvedValueOnce(true);
        const { deleteDomain } = mountComposable(() => useDomainsManager());

        await deleteDomain('domain-1');

        expect(mockDependencies.domainsStore.deleteDomain).toHaveBeenCalledWith('domain-1');
        expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
          'web.domains.domain_removed_successfully',
          'success',
          'top'
        );
      });

      it.skip('aborts deletion when confirmation is cancelled', async () => {
        // Implementation doesn't use confirmation dialogs
      });

      describe('error handling', () => {
        it.skip('handles API errors during deletion', async () => {
          // Implementation doesn't handle errors this way
        });

        it.skip('handles confirmation dialog errors', async () => {
          // Implementation doesn't use confirmation dialogs
        });
      });
    });

    describe.skip('confirmDelete', () => {
      it.skip('returns domain ID when confirmed', async () => {
        // Function does not exist in actual composable
      });

      it.skip('returns null when cancelled', async () => {
        // Function does not exist in actual composable
      });

      it.skip('handles dialog errors gracefully', async () => {
        // Function does not exist in actual composable
      });
    });
  });

  describe('reactive state', () => {
    it('exposes store reactive properties', () => {
      const { records, isLoading } = mountComposable(() => useDomainsManager());

      expect(records.value).toEqual(mockDomainsArray);
      expect(isLoading.value).toBe(false);
    });

    it.skip('reflects loading state changes', async () => {
      // Composable uses its own local isLoading ref, not store's loading state
    });
  });
  describe('refreshRecords org-scoped behavior', () => {
    it('passes orgIdentifier from route.params.orgid to store.refreshRecords', async () => {
      currentRouteParams = { orgid: 'org-from-route-123' };

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords();

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: 'org-from-route-123',
        force: false,
      });
    });

    it('passes orgIdentifier from route.params.extid when orgid is not present', async () => {
      currentRouteParams = { extid: 'ext-from-route-456' };

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords();

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: 'ext-from-route-456',
        force: false,
      });
    });

    it('prefers orgid over extid when both are present in route params', async () => {
      currentRouteParams = { orgid: 'primary-org', extid: 'secondary-ext' };

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords();

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: 'primary-org',
        force: false,
      });
    });

    it('passes undefined orgId when no org params in route', async () => {
      currentRouteParams = {};

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords();

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: undefined,
        force: false,
      });
    });

    it('passes force: true when called with force argument', async () => {
      currentRouteParams = { orgid: 'org-force-test' };

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords(true);

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: 'org-force-test',
        force: true,
      });
    });

    it('passes force: false by default', async () => {
      currentRouteParams = { orgid: 'org-default-force' };

      const { refreshRecords } = mountComposable(() => useDomainsManager());
      await refreshRecords();

      expect(mockDependencies.domainsStore.refreshRecords).toHaveBeenCalledWith({
        orgId: 'org-default-force',
        force: false,
      });
    });
  });

  describe('error handling', () => {
    it('sets human-readable error when domain addition fails', async () => {
      // Store returns { record: null } to simulate failure
      mockDependencies.domainsStore.addDomain.mockResolvedValueOnce({ record: null, details: {} });
      mockDependencies.errorHandler.createError.mockImplementation((message, type, severity) => ({
        message,
        type,
        severity,
        name: 'Error',
      }));
      const { handleAddDomain, error } = mountComposable(() => useDomainsManager());

      await handleAddDomain('test-domain.com');

      expect(error.value).toMatchObject({
        message: 'web.domains.failed_to_add_domain',
        type: 'human',
        severity: 'error',
      });
    });

    it('clears error state on successful domain addition', async () => {
      // Store returns { record, details } on success
      mockDependencies.domainsStore.addDomain.mockResolvedValueOnce({
        record: newDomainData,
        details: { domain_context: newDomainData.display_domain },
      });
      const { handleAddDomain, error } = mountComposable(() => useDomainsManager());

      await handleAddDomain('test-domain.com');

      expect(error.value).toBeNull();
    });

    // Gnarly test
    it('handles API errors appropriately', async () => {
      mockDependencies.errorHandler.wrap.mockImplementation(async (fn) => {
        try {
          return await fn();
        } catch (err) {
          // Properly classify the error and call onError callback
          const error = err as any;
          const classifiedError = {
            message: error.message,
            type: error.status === 404 ? 'human' : 'technical',
            severity: 'error',
          };
          mockDependencies.errorHandler.handleError(classifiedError);
          throw classifiedError; // Important: still throw the classified error
        }
      });

      // Create a proper API error object
      const apiError = {
        message: 'API Error',
        status: 404,
      };
      mockDependencies.domainsStore.addDomain.mockRejectedValueOnce(apiError);
      const { handleAddDomain } = mountComposable(() => useDomainsManager());

      try {
        await handleAddDomain('test-domain.com');
      } catch (err) {
        expect(err as any).toMatchObject({
          message: 'API Error',
          type: 'human',
          severity: 'error',
        });
      }
    });
  });

  describe('toggleHomepageConfig', () => {
    /**
     * Helper: create an AxiosError whose response.data carries the given fields.
     * classifyHttp reads error.response.data to build ApplicationError.details.
     */
    function makeAxiosError(
      status: number,
      data: Record<string, unknown>,
      message = 'Request failed'
    ): AxiosError {
      const err = new AxiosError(message, 'ERR_BAD_REQUEST', undefined, undefined, {
        status,
        data,
        headers: {},
        statusText: 'Forbidden',
        config: { headers: new AxiosHeaders() },
      });
      return err;
    }

    /**
     * Override wrap so it mirrors real useAsyncHandler.wrap behavior:
     * catch → classifyError → onError callback → return undefined.
     * Must be called AFTER mountComposable (so the capture has fired).
     */
    function setupEntitlementWrap() {
      mockDependencies.errorHandler.wrap.mockImplementation(async (fn: () => Promise<unknown>) => {
        try {
          return await fn();
        } catch (err) {
          const classified = classifyError(err);
          mockEntitlementCapture.onError?.(classified);
          return undefined;
        }
      });
    }

    it('returns the result when putHomepageConfig succeeds', async () => {
      const apiResult = { homepage: true };
      mockDependencies.domainsStore.putHomepageConfig.mockResolvedValueOnce(apiResult);

      const { toggleHomepageConfig } = mountComposable(() => useDomainsManager());
      const result = await toggleHomepageConfig('domain-ext-1', true, 'owner');

      // toggle delegates to updateHomepageConfig with enabled only — merge
      // semantics leave the stored secrets_mode unchanged.
      expect(mockDependencies.domainsStore.putHomepageConfig).toHaveBeenCalledWith('domain-ext-1', {
        enabled: true,
      });
      expect(result).toEqual(apiResult);
    });

    it('sends secrets_mode when updateHomepageConfig selects an experience', async () => {
      const apiResult = { homepage: true };
      mockDependencies.domainsStore.putHomepageConfig.mockResolvedValueOnce(apiResult);

      const { updateHomepageConfig } = mountComposable(() => useDomainsManager());
      const result = await updateHomepageConfig(
        'domain-ext-1',
        { enabled: true, secrets_mode: 'incoming' },
        'owner'
      );

      expect(mockDependencies.domainsStore.putHomepageConfig).toHaveBeenCalledWith('domain-ext-1', {
        enabled: true,
        secrets_mode: 'incoming',
      });
      expect(result).toEqual(apiResult);
    });

    it('shows owner notification for EntitlementRequired error when orgRole is owner', async () => {
      const { toggleHomepageConfig, error } = mountComposable(() => useDomainsManager());
      setupEntitlementWrap();

      mockDependencies.domainsStore.putHomepageConfig.mockRejectedValueOnce(
        makeAxiosError(403, { error: 'Upgrade required', error_type: 'EntitlementRequired' })
      );

      const result = await toggleHomepageConfig('domain-ext-1', true, 'owner');

      expect(result).toBeUndefined();
      expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
        'web.domains.entitlement_required_owner',
        'error',
        'top'
      );
      expect(error.value).toMatchObject({ type: 'human', severity: 'error' });
    });

    it('shows member notification for EntitlementRequired error when orgRole is member', async () => {
      const { toggleHomepageConfig } = mountComposable(() => useDomainsManager());
      setupEntitlementWrap();

      mockDependencies.domainsStore.putHomepageConfig.mockRejectedValueOnce(
        makeAxiosError(403, { error: 'Upgrade required', error_type: 'EntitlementRequired' })
      );

      const result = await toggleHomepageConfig('domain-ext-1', false, 'member');

      expect(result).toBeUndefined();
      expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
        'web.domains.entitlement_required_member',
        'error',
        'top'
      );
    });

    it('defaults to member notification when orgRole is null', async () => {
      const { toggleHomepageConfig } = mountComposable(() => useDomainsManager());
      setupEntitlementWrap();

      mockDependencies.domainsStore.putHomepageConfig.mockRejectedValueOnce(
        makeAxiosError(403, { error: 'Upgrade required', error_type: 'EntitlementRequired' })
      );

      const result = await toggleHomepageConfig('domain-ext-1', true);

      expect(result).toBeUndefined();
      expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
        'web.domains.entitlement_required_member',
        'error',
        'top'
      );
    });

    it('shows error message and sets error.value for non-entitlement errors', async () => {
      const { toggleHomepageConfig, error } = mountComposable(() => useDomainsManager());
      setupEntitlementWrap();

      mockDependencies.domainsStore.putHomepageConfig.mockRejectedValueOnce(
        makeAxiosError(500, { error: 'Internal server error' }, 'Internal server error')
      );

      const result = await toggleHomepageConfig('domain-ext-1', true, 'owner');

      expect(result).toBeUndefined();
      // Non-entitlement: onError shows err.message via notifications and sets error.value
      expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
        'Internal server error',
        'error',
        'top'
      );
      expect(error.value).not.toBeNull();
    });
  });
});
