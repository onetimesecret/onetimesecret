// tests/unit/vue/composables/useDomainsManager.spec.ts
import { mockDomains, newDomainData } from '@/../tests/unit/vue/fixtures/domains';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

// Mock all external dependencies
const mockRouter = {
  back: vi.fn(),
  push: vi.fn(),
};

const mockConfirmDialog = vi.fn();

const mockErrorHandler = {
  handleError: vi.fn(),
};

const mockDomainsStore = {
  domains: ref(mockDomains),
  addDomain: vi.fn(),
  deleteDomain: vi.fn(),
  isLoading: ref(false),
  error: ref(null),
};

const mockNotificationsStore = {
  show: vi.fn(),
};

// Setup mocks
vi.mock('vue-router', () => ({
  useRouter: () => mockRouter,
}));

vi.mock('@/stores/domainsStore', () => ({
  useDomainsStore: () => mockDomainsStore,
}));

vi.mock('@/stores/notificationsStore', () => ({
  useNotificationsStore: () => mockNotificationsStore,
}));

vi.mock('@/composables/useConfirmDialog', () => ({
  useConfirmDialog: () => mockConfirmDialog,
}));

vi.mock('@/composables/useErrorHandler', () => ({
  useErrorHandler: () => mockErrorHandler,
}));

describe('useDomainsManager', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('handleAddDomain', () => {
    it('successfully adds a new domain', async () => {
      mockDomainsStore.addDomain.mockResolvedValueOnce(newDomainData);
      const { handleAddDomain } = useDomainsManager();

      const result = await handleAddDomain(newDomainData.name);

      expect(result).toEqual(newDomainData);
      expect(mockDomainsStore.addDomain).toHaveBeenCalledWith(newDomainData.name);
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'AccountDomainVerify',
        params: { domain: newDomainData.name },
      });
      expect(mockNotificationsStore.show).toHaveBeenCalledWith(
        'Domain added successfully',
        'success'
      );
    });

    it('handles errors when adding domain fails', async () => {
      const error = new Error('Failed to add domain');
      mockDomainsStore.addDomain.mockRejectedValueOnce(error);
      const { handleAddDomain } = useDomainsManager();

      const result = await handleAddDomain(newDomainData.name);

      expect(result).toBeNull();
      expect(mockErrorHandler.handleError).toHaveBeenCalledWith(error);
    });
  });

  describe('deleteDomain', () => {
    it('successfully deletes a domain after confirmation', async () => {
      mockConfirmDialog.mockResolvedValueOnce(true);
      const { deleteDomain } = useDomainsManager();

      await deleteDomain('domain-1');

      expect(mockDomainsStore.deleteDomain).toHaveBeenCalledWith('domain-1');
      expect(mockNotificationsStore.show).toHaveBeenCalledWith(
        'Domain removed successfully',
        'success'
      );
    });

    it('does not delete domain when confirmation is cancelled', async () => {
      mockConfirmDialog.mockResolvedValueOnce(false);
      const { deleteDomain } = useDomainsManager();

      await deleteDomain('domain-1');

      expect(mockDomainsStore.deleteDomain).not.toHaveBeenCalled();
    });

    it('handles errors during domain deletion', async () => {
      mockConfirmDialog.mockResolvedValueOnce(true);
      const error = new Error('Failed to remove domain');
      mockDomainsStore.deleteDomain.mockRejectedValueOnce(error);
      const { deleteDomain } = useDomainsManager();

      await deleteDomain('domain-1');

      expect(mockNotificationsStore.show).toHaveBeenCalledWith(
        'Failed to remove domain',
        'error'
      );
    });
  });

  describe('confirmDelete', () => {
    it('returns domain ID when confirmed', async () => {
      mockConfirmDialog.mockResolvedValueOnce(true);
      const { confirmDelete } = useDomainsManager();

      const result = await confirmDelete('domain-1');

      expect(result).toBe('domain-1');
    });

    it('returns null when cancelled', async () => {
      mockConfirmDialog.mockResolvedValueOnce(false);
      const { confirmDelete } = useDomainsManager();

      const result = await confirmDelete('domain-1');

      expect(result).toBeNull();
    });

    it('handles confirmation dialog errors', async () => {
      mockConfirmDialog.mockRejectedValueOnce(new Error('Dialog error'));
      const { confirmDelete } = useDomainsManager();

      const result = await confirmDelete('domain-1');

      expect(result).toBeNull();
    });
  });

  describe('reactive properties', () => {
    it('exposes store reactive properties', () => {
      const { domains, isLoading, error } = useDomainsManager();

      expect(domains.value).toEqual(mockDomains);
      expect(isLoading.value).toBe(false);
      expect(error.value).toBeNull();
    });
  });
});
