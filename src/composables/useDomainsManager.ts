import { useConfirmDialog } from '@/composables/useConfirmDialog';
import { useDomainsStore, useNotificationsStore } from '@/stores';
import { storeToRefs } from 'pinia';

/**
 *
 * useDomainsManager's role should be:
 * - Managing UI-specific state (loading states, toggling states)
 * - Coordinating between stores and UI components
 * - Handling user interactions and confirmations
 * - Providing a simplified interface for common domain operations
 */
export function useDomainsManager() {
  const store = useDomainsStore();
  const notifications = useNotificationsStore();
  const { domains, isLoading, error } = storeToRefs(store);

  const showConfirmDialog = useConfirmDialog();

  const handleAddDomain = async (domain: string) => {
    try {
      const result = await store.addDomain(domain);
      notifications.show('Domain added successfully', 'success');
      return result;
    } catch {
      notifications.show('Failed to add domain', 'error');
      return null;
    }
  };

  const deleteDomain = async (domainId: string) => {
    if (!(await confirmDelete(domainId))) return;

    try {
      await store.deleteDomain(domainId);
      notifications.show('Domain removed successfully', 'success');
    } catch (error) {
      notifications.show(
        error instanceof Error ? error.message : 'Failed to remove domain',
        'error'
      );
    }
  };

  const confirmDelete = async (domainId: string): Promise<string | null> => {
    console.debug('[useDomainsManager] Confirming delete for domain:', domainId);

    try {
      const confirmed = await showConfirmDialog({
        title: 'Remove Domain',
        message: `Are you sure you want to remove this domain? This action cannot be undone.`,
        confirmText: 'Remove Domain',
        cancelText: 'Cancel',
        type: 'danger',
      });

      if (!confirmed) {
        console.debug('[useDomainsManager] Confirmation cancelled');
        return null;
      }
      return domainId;
    } catch (error) {
      console.error('[useDomainsManager] Error in confirm dialog:', error);
      return null;
    }
  };

  return {
    domains,
    isLoading,
    error,
    handleAddDomain,
    deleteDomain,
    confirmDelete,
  };
}
