// src/composables/useDomainsManager.ts

import { AsyncHandlerOptions, createError, useAsyncHandler } from '@/shared/composables/useAsyncHandler';
import { ApplicationError } from '@/schemas/errors';
import { useDomainsStore, useNotificationsStore } from '@/shared/stores';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
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
  const { t } = useI18n();

  const recordCount = computed(() => store.recordCount());

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null); // Add local error state

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      notifications.show(message, severity);
    },
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      if (err.code === 404 || err.code === 422 || err.code === 403) {
        return router.push({ name: 'NotFound' });
      }

      error.value = err;
    },
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Fetch domains list
   * @param force - Force refresh even if already initialized
   */
  const fetch = async () => wrap(async () => await store.fetchList());

  const getDomain = async (extid: string) =>
    wrap(async () => {
      const domainData = await store.getDomain(extid);
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
        cluster: (domainData?.details as any)?.cluster,
        canVerify,
      };
    });

  const verifyDomain = async (extid: string) =>
    wrap(async () => {
      const result = await store.verifyDomain(extid);
      notifications.show(t('domain-verification-initiated-successfully'), 'success');
      return result;
    });

  const handleDomainExistsError = async (domain: string, errorMessage: string) => {
    if (errorMessage.includes('already registered in your organization')) {
      notifications.show(t('web.domains.domain-already-in-organization'), 'warning');
      await store.fetchList();
      const existingDomain = store.records?.find(d => d.display_domain === domain);
      if (existingDomain) {
        setTimeout(() => {
          router.push({ name: 'DomainVerify', params: { extid: existingDomain.extid } });
        }, 2000);
      }
      return null;
    }
    if (errorMessage.includes('registered to another organization')) {
      notifications.show(t('web.domains.domain-in-other-organization'), 'error');
      return null;
    }
    return undefined; // Signal to re-throw
  };

  const handleAddDomain = async (domain: string) =>
    wrap(async () => {
      try {
        const result = await store.addDomain(domain);
        if (!result) {
          error.value = createError(t('failed-to-add-domain'), 'human', 'error');
          return null;
        }

        const isReclaimed = result.updated.getTime() > result.created.getTime();
        const message = isReclaimed ? 'web.domains.domain-claimed-successfully' : 'domain-added-successfully';
        notifications.show(t(message), 'success');

        router.push({ name: 'DomainVerify', params: { extid: result.extid } });
        setTimeout(() => verifyDomain(result.extid), 2000);
        return result;
      } catch (err: any) {
        const errorMessage = err?.response?.data?.message || err?.message || '';
        const handled = await handleDomainExistsError(domain, errorMessage);
        if (handled !== undefined) return handled;
        throw err;
      }
    });

  const deleteDomain = async (domainId: string) => {
    await store.deleteDomain(domainId);
    notifications.show(t('domain-removed-successfully'), 'success');
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
