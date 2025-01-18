import {
  AsyncHandlerOptions,
  createError,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import { useConfirmDialog } from '@/composables/useConfirmDialog';
import { ApplicationError } from '@/schemas/errors';
import { useDomainsStore, useNotificationsStore } from '@/stores';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
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
  const store = useDomainsStore();
  const notifications = useNotificationsStore();
  const router = useRouter();
  const goBack = () => router.back();
  const { records, details } = storeToRefs(store);

  const { refreshRecords } = store;

  const recordCount = computed(() => store.recordCount());

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null); // Add local error state

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      notifications.show(message, severity);
    },
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const showConfirmDialog = useConfirmDialog();

  /**
   * Fetch domains list
   * @param force - Force refresh even if already initialized
   */
  const fetch = async () => wrap(async () => await store.fetchList());

  const getDomain = async (domainName: string) =>
    wrap(async () => {
      const domainData = await store.getDomain(domainName);
      const domain = domainData.record;
      const currentTime = Math.floor(Date.now() / 1000);
      const lastMonitored = domain?.vhost?.last_monitored_unix ?? 0;
      const domainUpdated = Math.floor(domain.updated.getTime() / 1000);
      const lastUpdatedDistance = currentTime - domainUpdated;
      // Approximated hasn't checked this domain yet or it's been more than N
      // seconds since this domain record was updated. Typically this will be
      // the amount of time since last clicking the "refresh" button.
      const canVerify = !lastMonitored || lastUpdatedDistance >= 10;

      return {
        domain,
        cluster: domainData?.details?.cluster,
        canVerify,
      };
    });

  const verifyDomain = async (domainName: string) =>
    wrap(async () => {
      const result = await store.verifyDomain(domainName);
      notifications.show(
        'Domain verification initiated successfully',
        'success'
      );
      return result;
    });

  const handleAddDomain = async (domain: string) =>
    wrap(async () => {
      const result = await store.addDomain(domain);
      if (result) {
        router.push({ name: 'DomainVerify', params: { domain } });
        notifications.show('Domain added successfully', 'success');
        setTimeout(() => {
          verifyDomain(domain);
        }, 2000);
        return result;
      }
      error.value = createError('Failed to add domain', 'human', 'error');
      return null;
    });

  const deleteDomain = async (domainId: string) =>
    wrap(async () => {
      const confirmed = await confirmDelete(domainId);
      if (!confirmed) return;

      await store.deleteDomain(domainId);
      notifications.show('Domain removed successfully', 'success');
    });

  const confirmDelete = async (domainId: string): Promise<string | null> => {
    console.debug(
      '[useDomainsManager] Confirming delete for domain:',
      domainId
    );

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
    // State
    records,
    details,
    isLoading,
    error,

    // Getters
    recordCount,

    // Actions
    fetch,
    getDomain,
    verifyDomain,
    handleAddDomain,
    refreshRecords,
    deleteDomain,
    goBack,
  };
}
