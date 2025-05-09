// src/composables/useDomain.ts

import { ApplicationError } from '@/schemas/errors';
import { useDomainsStore, useNotificationsStore } from '@/stores';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Composable for managing state for a single domain.
 *
 * @param {string} [domainId] - Optional ID of the domain to manage
 * @returns {Object} Domain management methods and reactive state
 *
 * @property {Ref<boolean>} isLoading - Indicates if any async operation is in progress
 * @property {Ref<boolean>} isInitialized - Indicates if the domain data has been loaded
 * @property {Ref<ApplicationError|null>} error - Holds any error that occurred during operations
 * @property {Ref<any>} domain - Contains the domain record data
 * @property {Ref<any>} details - Contains additional domain details
 * @property {ComputedRef<boolean>} canVerify - Indicates if domain verification is possible
 * @property {Function} initialize - Loads the domain data
 * @property {Function} verify - Initiates domain verification
 * @property {Function} remove - Deletes the domain
 *
 * @example
 * const { domain, isLoading, initialize, verify } = useDomain('domain-123');
 * await initialize();
 */
/* eslint-disable max-lines-per-function */
export function useDomain(domainId?: string) {
  const store = useDomainsStore();
  const notifications = useNotificationsStore();
  const router = useRouter();
  const { t } = useI18n();

  const isLoading = ref(false);
  const isInitialized = ref(false);
  const error = ref<ApplicationError | null>(null);
  const domain = ref<any>(null);
  const details = ref<any>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      if (err.code === 404 || err.code === 422 || err.code === 403) {
        return router.push({ name: 'NotFound' });
      }
      error.value = err;
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const canVerify = computed(() => {
    if (!domain.value) return false;
    const currentTime = Math.floor(Date.now() / 1000);
    const lastMonitored = domain.value?.vhost?.last_monitored_unix ?? 0;
    const domainUpdated = Math.floor(domain.value.updated.getTime() / 1000);
    return !lastMonitored || currentTime - domainUpdated >= 10;
  });

  const initialize = () =>
    wrap(async () => {
      if (!domainId) return;
      const data = await store.getDomain(domainId);
      domain.value = data.record;
      details.value = data.details;
      isInitialized.value = true;
    });

  const verify = () =>
    wrap(async () => {
      if (!domainId) return;
      await store.verifyDomain(domainId);
      notifications.show(t('domain-verification-initiated-successfully'), 'success');
      await initialize();
    });

  const remove = () =>
    wrap(async () => {
      if (!domainId) return;
      await store.deleteDomain(domainId);
      notifications.show(t('domain-removed-successfully'), 'success');
      router.push({ name: 'Domains' });
    });

  return {
    isLoading,
    isInitialized,
    error,
    domain,
    details,
    canVerify,
    initialize,
    verify,
    remove,
  };
}
