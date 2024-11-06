// src/composables/useDomainsTable.ts
import { ref, watch } from 'vue';
import type { CustomDomain } from '@/types/onetime';
import { showConfirmDialog } from '@/composables/useConfirmDialog';
import { useNotificationsStore } from '@/stores/notifications';
import { useDomainsStore } from '@/stores/domainsStore';

export function useDomainsTable(initialDomains: CustomDomain[]) {
  const togglingDomains = ref<Set<string>>(new Set());
  const isSubmitting = ref(false);
  const notifications = useNotificationsStore();
  const domainsStore = useDomainsStore();

  // Watch for domain changes
  watch(() => initialDomains, (newDomains) => {
    if (newDomains?.length) {
      domainsStore.setDomains(newDomains);
    }
  }, { immediate: true });

  const toggleHomepageCreation = async (domain: CustomDomain) => {
    if (togglingDomains.value.has(domain.identifier)) return;

    togglingDomains.value.add(domain.identifier);

    try {
      await domainsStore.toggleHomepageAccess(domain);

      notifications.show(
        `Homepage access ${!domain?.brand?.allow_public_homepage ? 'enabled' : 'disabled'} for ${domain.display_domain}`,
        'success'
      );
    } catch {
      notifications.show(
        `Failed to update homepage access for ${domain.display_domain}`,
        'error'
      );
    } finally {
      togglingDomains.value.delete(domain.identifier);
    }
  };



  const confirmDelete = async (domain: CustomDomain): Promise<void> => {
    if (isSubmitting.value) return;

    try {
      const confirmed = await showConfirmDialog({
        title: 'Remove Domain',
        message: `Are you sure you want to remove ${domain.display_domain}? This action cannot be undone.`,
        confirmText: 'Remove Domain',
        cancelText: 'Cancel',
        type: 'danger'
      });

      if (!confirmed) return;
      isSubmitting.value = true;

      await domainsStore.deleteDomain(domain.display_domain);

      notifications.show(
        `${domain.display_domain} has been removed successfully`,
        'success'
      );
    } catch (error) {
      console.error('Failed to remove domain:', error);
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
