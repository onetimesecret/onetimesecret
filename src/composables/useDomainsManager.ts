// src/composables/useDomainsManager.ts
import { showConfirmDialog } from '@/composables/useConfirmDialog';
import { useDomainsStore } from '@/stores/domainsStore';
import type { CustomDomain } from '@/types/onetime';
import { ref } from 'vue';

export function useDomainsManager() {
  const togglingDomains = ref<Set<string>>(new Set());
  const isSubmitting = ref(false);
  const domainsStore = useDomainsStore();

  const toggleHomepageCreation = async (domain: CustomDomain) => {
    console.debug('[useDomainsManager] Toggling homepage creation for domain:', domain);

    if (togglingDomains.value.has(domain.identifier)) {
      console.debug('[useDomainsManager] Domain already being toggled:', domain.identifier);
      return;
    }

    togglingDomains.value.add(domain.identifier);

    try {
      console.debug('[useDomainsManager] Attempting to toggle homepage access');
      await domainsStore.toggleHomepageAccess(domain);

    } catch (error) {
      console.error('[useDomainsManager] Failed to toggle homepage access:', error);

    } finally {
      togglingDomains.value.delete(domain.identifier);
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
    isToggling: (domainId: string) => togglingDomains.value.has(domainId),
    isSubmitting,
    toggleHomepageCreation,
    confirmDelete
  };
}
