// src/composables/useDomainsManager.spec.ts
import { useDomainsManager } from '@/composables/useDomainsManager';
import { ApplicationError } from '@/schemas/errors';
import { mockDomains, newDomainData } from '@tests/unit/vue/fixtures/domains.fixture';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

import type { MockDependencies } from '../types.d';

// Test constants
const TEST_DOMAIN_ID = 'domain-1';
const TEST_API_ERROR = new Error('API Error');
const TEST_VALIDATION_ERROR = new Error('Invalid domain');

// Mock Setup
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
    domains: ref(mockDomains),
    addDomain: vi.fn(),
    deleteDomain: vi.fn(),
    isLoading: ref(false),
    error: ref(null),
  },
  notificationsStore: {
    show: vi.fn(),
  },
};

// Mock imports
vi.mock('vue-router', () => ({
  useRouter: () => mockDependencies.router,
}));

vi.mock('@/stores/domainsStore', () => ({
  useDomainsStore: () => mockDependencies.domainsStore,
}));

vi.mock('@/stores/notificationsStore', () => ({
  useNotificationsStore: () => mockDependencies.notificationsStore,
}));

vi.mock('@/composables/useConfirmDialog', () => ({
  useConfirmDialog: () => mockDependencies.confirmDialog,
}));

vi.mock('@/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => mockDependencies.errorHandler,
  createError: (message: string, type: string, severity: string) => ({
    message,
    type,
    severity,
  }),
}));

describe('useDomainsManager', () => {
  beforeEach(() => {
    setActivePinia(createPinia());

    vi.clearAllMocks();
    // Reset reactive refs
    mockDependencies.domainsStore.error.value = null;
    mockDependencies.domainsStore.isLoading.value = false;
    mockDependencies.errorHandler.wrap.mockImplementation(async (fn) => await fn());
  });

  describe('domain addition', () => {
    describe('handleAddDomain', () => {
      it('successfully adds a new domain and navigates to verification', async () => {
        mockDependencies.domainsStore.addDomain.mockResolvedValueOnce(newDomainData);

        const { handleAddDomain } = useDomainsManager();
        const result = await handleAddDomain(newDomainData.domainid);

        expect(result).toEqual(newDomainData);
        expect(mockDependencies.domainsStore.addDomain).toHaveBeenCalledWith(
          newDomainData.domainid
        );
        expect(mockDependencies.router.push).toHaveBeenCalledWith({
          name: 'DomainVerify', // name of the route
          params: { domain: newDomainData.domainid },
        });
        expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
          'Domain added successfully',
          'success'
        );
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

          const { handleAddDomain } = useDomainsManager();
          const result = await handleAddDomain(newDomainData.domainid);

          expect(result).toBeNull();
          expect(mockDependencies.errorHandler.handleError).toHaveBeenCalledWith(
            apiError
          );
          expect(mockDependencies.router.push).not.toHaveBeenCalled();
        });

        it('handles validation errors', async () => {
          const validationError = {
            message: 'Invalid domain',
            type: 'human',
            severity: 'error',
          } as ApplicationError;

          mockDependencies.domainsStore.addDomain.mockRejectedValueOnce(validationError);
          const { handleAddDomain } = useDomainsManager();

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
        const { deleteDomain } = useDomainsManager();

        await deleteDomain('domain-1');

        expect(mockDependencies.domainsStore.deleteDomain).toHaveBeenCalledWith(
          'domain-1'
        );
        expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
          'Domain removed successfully',
          'success'
        );
      });

      it('aborts deletion when confirmation is cancelled', async () => {
        mockDependencies.confirmDialog.mockResolvedValueOnce(false);
        const { deleteDomain } = useDomainsManager();

        await deleteDomain('domain-1');

        expect(mockDependencies.domainsStore.deleteDomain).not.toHaveBeenCalled();
        expect(mockDependencies.notificationsStore.show).not.toHaveBeenCalled();
      });

      describe('error handling', () => {
        it('handles API errors during deletion', async () => {
          mockDependencies.confirmDialog.mockResolvedValueOnce(true);
          const error = new Error('Failed to remove domain');
          mockDependencies.domainsStore.deleteDomain.mockRejectedValueOnce(error);
          const { deleteDomain } = useDomainsManager();

          await deleteDomain('domain-1');

          expect(mockDependencies.notificationsStore.show).toHaveBeenCalledWith(
            'Failed to remove domain',
            'error'
          );
        });

        it('handles confirmation dialog errors', async () => {
          mockDependencies.confirmDialog.mockRejectedValueOnce(new Error('Dialog error'));
          const { deleteDomain } = useDomainsManager();

          await deleteDomain('domain-1');

          expect(mockDependencies.domainsStore.deleteDomain).not.toHaveBeenCalled();
        });
      });
    });

    describe('confirmDelete', () => {
      it('returns domain ID when confirmed', async () => {
        mockDependencies.confirmDialog.mockResolvedValueOnce(true);
        const { confirmDelete } = useDomainsManager();

        const result = await confirmDelete('domain-1');

        expect(result).toBe('domain-1');
      });

      it('returns null when cancelled', async () => {
        mockDependencies.confirmDialog.mockResolvedValueOnce(false);
        const { confirmDelete } = useDomainsManager();

        const result = await confirmDelete('domain-1');

        expect(result).toBeNull();
      });

      it('handles dialog errors gracefully', async () => {
        mockDependencies.confirmDialog.mockRejectedValueOnce(new Error('Dialog error'));
        const { confirmDelete } = useDomainsManager();

        const result = await confirmDelete('domain-1');

        expect(result).toBeNull();
      });
    });
  });

  describe('reactive state', () => {
    it('exposes store reactive properties', () => {
      const { domains, isLoading } = useDomainsManager();

      expect(domains.value).toEqual(mockDomains);
      expect(isLoading.value).toBe(false);
    });

    it('reflects loading state changes', async () => {
      mockDependencies.domainsStore.isLoading.value = true;
      const { isLoading } = useDomainsManager();

      expect(isLoading.value).toBe(true);
    });
  });
  describe('error handling', () => {
    it('sets human-readable error when domain addition fails', async () => {
      mockDependencies.domainsStore.addDomain.mockResolvedValueOnce(null);
      mockDependencies.errorHandler.createError.mockImplementation(
        (message, type, severity) => ({
          message,
          type,
          severity,
          name: 'Error',
        })
      );
      const { handleAddDomain, error } = useDomainsManager();

      await handleAddDomain('test-domain.com');

      expect(error.value).toMatchObject({
        message: 'Failed to add domain',
        type: 'human',
        severity: 'error',
      });
    });

    it('clears error state on successful domain addition', async () => {
      mockDependencies.domainsStore.addDomain.mockResolvedValueOnce(newDomainData);
      const { handleAddDomain, error } = useDomainsManager();

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
          const classifiedError = {
            message: err.message,
            type: err.status === 404 ? 'human' : 'technical',
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
      const { handleAddDomain, error } = useDomainsManager();

      try {
        await handleAddDomain('test-domain.com');
      } catch (err) {
        expect(err).toMatchObject({
          message: 'API Error',
          type: 'human',
          severity: 'error',
        });
      }
    });
  });
});
