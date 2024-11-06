import { ref } from 'vue';
import type { CustomDomain } from '@/types/onetime';
import { useToast } from '@/composables/useToast';
import { useCsrfStore } from '@/stores/csrfStore';
import { showConfirmDialog } from '@/composables/useConfirmDialog'; // Add this import
import { createApi } from '@/utils/api';
import { useNotificationsStore } from '@/stores/notifications';
import { useDomains } from '@/composables/useDomains';


export function useDomainsTable() {
  const isToggling = ref<string>(''); // Stores the domain currently being toggled
  const isSubmitting = ref(false);
  const toast = useToast();
  const csrfStore = useCsrfStore();

  const toggleHomepageCreation = async (domain: CustomDomain) => {
    // Prevent multiple simultaneous toggles
    if (isToggling.value === domain.identifier) return;

    isToggling.value = domain.identifier;

    try {
      const response = await fetch(`/api/v2/account/domains/${domain.display_domain}/brand`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfStore.shrimp
        },
        body: JSON.stringify({
          enabled: !domain?.brand?.allow_public_homepage
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      // Update the domain state
      if (domain.brand) {
        domain.brand.allow_public_homepage = !domain.brand.allow_public_homepage;
      }

      toast.success(
        'Homepage access updated',
        `Homepage access ${domain.brand?.allow_public_homepage ? 'enabled' : 'disabled'} for ${domain.display_domain}`
      );

    } catch (error) {
      console.error('Failed to toggle homepage creation:', error);
      toast.error(
        'Update failed',
        `Failed to update homepage access for ${domain.display_domain}`
      );

      // Revert the optimistic update if it failed
      if (domain.brand) {
        domain.brand.allow_public_homepage = !domain.brand.allow_public_homepage;
      }
    } finally {
      isToggling.value = '';
    }
  };

  const api = createApi();

  const confirmDelete = async (domain: CustomDomain): Promise<void> => {
    if (isSubmitting.value) return;
    const notifications = useNotificationsStore();
    const { removeDomain } = useDomains();

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

      // Remove domain using the composable (which now uses Pinia store)
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
