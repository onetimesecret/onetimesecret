// src/composables/useDomainsTable.ts
import { ref } from 'vue';
import type { CustomDomain } from '@/types/onetime';
import { useToast } from '@/composables/useToast';
import { showConfirmDialog } from '@/composables/useConfirmDialog';
import { useNotificationsStore } from '@/stores/notifications';
import { useDomainsStore } from '@/stores/domainsStore';

export function useDomainsTable(initialDomains: CustomDomain[]) {
  const isToggling = ref<string>('');
  const isSubmitting = ref(false);
  const toast = useToast();
  const domainsStore = useDomainsStore();

  if (!domainsStore.domains.length && initialDomains) {
    domainsStore.setDomains(initialDomains);
  }

  const toggleHomepageCreation = async (domain: CustomDomain) => {
    if (isToggling.value === domain.identifier) return;
    isToggling.value = domain.identifier;

    try {
      const newStatus = await domainsStore.toggleHomepageAccess(domain);

      toast.success(
        'Homepage access updated',
        `Homepage access ${newStatus ? 'enabled' : 'disabled'} for ${domain.display_domain}`
      );
    } catch {
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
      domainsStore.removeDomain(domain.display_domain);

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
