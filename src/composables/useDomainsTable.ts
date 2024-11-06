// src/composables/useDomainsTable.ts
import { ref } from 'vue';
import type { CustomDomain } from '@/types/onetime';
import { useToast } from '@/composables/useToast';
import { showConfirmDialog } from '@/composables/useConfirmDialog';
import { createApi } from '@/utils/api';
import { useNotificationsStore } from '@/stores/notifications';
import { useDomains } from '@/composables/useDomains';

const api = createApi();

export function useDomainsTable(initialDomains: CustomDomain[]) {
  const isToggling = ref<string>('');
  const isSubmitting = ref(false);
  const toast = useToast();
  const { updateDomain, removeDomain } = useDomains(initialDomains);

  const toggleHomepageCreation = async (domain: CustomDomain) => {
    if (isToggling.value === domain.identifier) return;

    isToggling.value = domain.identifier;
    const newHomepageStatus = !domain?.brand?.allow_public_homepage;

    try {
      await api.put(`/api/v2/account/domains/${domain.display_domain}/brand`, {
        brand: { allow_public_homepage: newHomepageStatus }
      });

      // Update domain in store
      updateDomain({
        ...domain,
        brand: {
          ...domain.brand,
          allow_public_homepage: newHomepageStatus
        }
      });

      toast.success(
        'Homepage access updated',
        `Homepage access ${newHomepageStatus ? 'enabled' : 'disabled'} for ${domain.display_domain}`
      );

    } catch (error) {
      console.error('Failed to toggle homepage creation:', error);
      toast.error(
        'Update failed',
        `Failed to update homepage access for ${domain.display_domain}`
      );
    } finally {
      isToggling.value = '';
    }
  };

  const confirmDelete = async (domain: CustomDomain): Promise<void> => {
    if (isSubmitting.value) return;
    const notifications = useNotificationsStore();

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

      await api.post(`/api/v2/account/domains/${domain.display_domain}/remove`);

      // Remove domain from store
      removeDomain(domain.display_domain);

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
    isToggling,
    isSubmitting,
    toggleHomepageCreation,
    confirmDelete
  };
}
