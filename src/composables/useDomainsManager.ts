// src/composables/useDomainsManager.ts
import { ref, watch } from 'vue';
import type { CustomDomain } from '@/types/onetime';
import { showConfirmDialog } from '@/composables/useConfirmDialog';
import { useNotificationsStore } from '@/stores/notifications';
import { useDomainsStore } from '@/stores/domainsStore';

export function useDomainsManager(initialDomains: CustomDomain[]) {
  const togglingDomains = ref<Set<string>>(new Set());
  const isSubmitting = ref(false);
  const notifications = useNotificationsStore();
  const domainsStore = useDomainsStore();

  console.debug('[useDomainsManager] Initial domains:', initialDomains);

  // Watch for domain changes
  watch(() => initialDomains, (newDomains) => {
    console.debug('[useDomainsManager] Watching initial domains:', newDomains);
    if (newDomains?.length) {
      console.debug('[useDomainsManager] Setting domains in store:', newDomains);
      domainsStore.setDomains(newDomains);
    }
  }, { immediate: true });

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

      notifications.show(
        `Homepage access ${!domain?.brand?.allow_public_homepage ? 'enabled' : 'disabled'} for ${domain.display_domain}`,
        'success'
      );
    } catch (error) {
      console.error('[useDomainsManager] Failed to toggle homepage access:', error);
      notifications.show(
        `Failed to update homepage access for ${domain.display_domain}`,
        'error'
      );
    } finally {
      togglingDomains.value.delete(domain.identifier);
    }
  };

  const confirmDelete = async (domain: CustomDomain): Promise<void> => {
    console.debug('[useDomainsManager] Confirming delete for domain:', domain);

    if (isSubmitting.value) {
      console.debug('[useDomainsManager] Already submitting, cancelling delete');
      return;
    }

    try {
      const confirmed = await showConfirmDialog({
        title: 'Remove Domain',
        message: `Are you sure you want to remove ${domain.display_domain}? This action cannot be undone.`,
        confirmText: 'Remove Domain',
        cancelText: 'Cancel',
        type: 'danger'
      });

      if (!confirmed) {
        console.debug('[useDomainsManager] Domain deletion not confirmed');
        return;
      }

      isSubmitting.value = true;

      console.debug('[useDomainsManager] Attempting to delete domain:', domain.display_domain);
      await domainsStore.deleteDomain(domain.display_domain);

      notifications.show(
        `${domain.display_domain} has been removed successfully`,
        'success'
      );
    } catch (error) {
      console.error('[useDomainsManager] Failed to remove domain:', error);
      notifications.show(
        `Failed to remove ${domain.display_domain}. Please try again later.`,
        'error'
      );
    } finally {
      isSubmitting.value = false;
    }
  };

  return {
    isToggling: (domainId: string) => togglingDomains.value.has(domainId),
    isSubmitting,
    toggleHomepageCreation,
    confirmDelete
  };
}
