import { useConfirmDialog } from '@/composables/useConfirmDialog';
import { ref } from 'vue';

export function useDomainsManager() {
  const togglingDomains = ref<Set<string>>(new Set());
  const isSubmitting = ref(false);
  const showConfirmDialog = useConfirmDialog();

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
        type: 'danger'
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
    isToggling,
    setTogglingStatus,
    isSubmitting,
    confirmDelete,
  };
}
