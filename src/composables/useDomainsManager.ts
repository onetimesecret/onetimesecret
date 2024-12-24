import { useConfirmDialog } from '@/composables/useConfirmDialog';
import { useDomainsStore, useNotificationsStore } from '@/stores';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';

export function useDomainsManager() {
  const store = useDomainsStore();
  const notifications = useNotificationsStore();
  const { domains, isLoading } = storeToRefs(store);

  const togglingDomains = ref<Set<string>>(new Set());
  const isSubmitting = ref(false);
  const showConfirmDialog = useConfirmDialog();

  const addDomain = async (domain: string) => {
    if (!domain) {
      notifications.show('Domain is required', 'error');
      return null;
    }

    try {
      const result = await store.addDomain(domain);
      notifications.show(`Added domain ${domain}`, 'success');
      return result;
    } catch (error) {
      notifications.show(
        error instanceof Error ? error.message : 'Failed to add domain',
        'error'
      );
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

  const isToggling = (domainId: string): boolean => {
    return togglingDomains.value.has(domainId);
  };

  const setTogglingStatus = (domainId: string, status: boolean) => {
    if (status) {
      togglingDomains.value.add(domainId);
    } else {
      togglingDomains.value.delete(domainId);
    }
  };
  const confirmDelete = async (domainId: string): Promise<string | null> => {
    console.debug('[useDomainsManager] Confirming delete for domain:', domainId);

    if (isSubmitting.value) {
      console.debug('[useDomainsManager] Already submitting, cancelling delete');
      return null;
    }

    try {
      const confirmed = await showConfirmDialog({
        title: 'Remove Domain',
        message: `Are you sure you want to remove this domain? This action cannot be undone.`,
        confirmText: 'Remove Domain',
        cancelText: 'Cancel',
        type: 'danger',
      });

      if (!confirmed) {
        console.debug('[useDomainsManager] Domain deletion not confirmed');
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
    isSubmitting,
    isToggling,
    addDomain,
    deleteDomain,
    setTogglingStatus,
    confirmDelete,
  };
}
