import { createError, useAsyncHandler } from '@/composables/useAsyncHandler';
import { useConfirmDialog } from '@/composables/useConfirmDialog';
import { ApplicationError } from '@/schemas/errors';
import { useDomainsStore, useNotificationsStore } from '@/stores';
import type { DomainsStore } from '@/stores/domainsStore'; // Add type import
import { storeToRefs, type StoreGeneric } from 'pinia';
import { ref } from 'vue';
import { useRouter } from 'vue-router';

/**
 * Composable for managing custom domains and their brand settings
 *
 * useDomainsManager's role should be:
 * - Managing UI-specific state (loading states, toggling states)
 * - Coordinating between stores and UI components
 * - Handling user interactions and confirmations
 * - Providing a simplified interface for common domain operations
 */
/* eslint-disable max-lines-per-function */
export function useDomainsManager() {
  const store = useDomainsStore() as DomainsStore;
  const notifications = useNotificationsStore();
  const router = useRouter();
  const goBack = () => router.back();
  const { domains, isLoading } = storeToRefs(store as StoreGeneric);
  const error = ref<ApplicationError | null>(null); // Add local error state
  const { wrap } = useAsyncHandler({
    onError: (e) => {
      error.value = e;
    },
    notify: (message) => {
      notifications.show(message, 'error');
      // There's a second var here available for severity
    },
  });

  const showConfirmDialog = useConfirmDialog();

  const handleAddDomain = async (domain: string) =>
    wrap(async () => {
      const result = await store.addDomain(domain);
      if (result) {
        router.push({ name: 'AccountDomainVerify', params: { domain } });
        notifications.show('Domain added successfully', 'success');
        return result;
      }
      error.value = createError('Failed to add domain', 'human', 'error');
      return null;
    });

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
    handleAddDomain,
    deleteDomain,
    confirmDelete,
    goBack,
    error,
  };
}
