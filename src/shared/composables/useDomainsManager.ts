// src/shared/composables/useDomainsManager.ts

import { AsyncHandlerOptions, createError, useAsyncHandler } from '@/shared/composables/useAsyncHandler';
import { useDomainContext } from '@/shared/composables/useDomainContext';
import { ApplicationError } from '@/schemas/errors';
import type { CustomDomain } from '@/schemas/models';
import { useDomainsStore, useNotificationsStore } from '@/shared/stores';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

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
  const route = useRoute();
  const goBack = () => router.back();
  const { records, details } = storeToRefs(store);

  // Get org identifier from route params for org-qualified operations
  // Routes use either :orgid (domain routes) or :extid (org settings routes)
  const orgIdentifier = computed(() =>
    (route.params.orgid || route.params.extid) as string | undefined
  );

  // Legacy alias for backward compatibility with navigation code
  const orgid = orgIdentifier;
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
      // 404: resource not found - redirect to NotFound page
      if (err.code === 404) {
        return router.push({ name: 'NotFound' });
      }

      // 422: validation error (e.g., upgrade required) - show the error message
      // 403: permission denied - show the error message
      // These should surface to the user, not redirect to NotFound
      error.value = err;
      if (err.message) {
        notifications.show(err.message, 'error');
      }
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
      notifications.show(t('web.domains.domain_verification_initiated_successfully'), 'success');
      return result;
    });

  const handleDomainExistsError = async (domain: string, errorMessage: string) => {
    if (errorMessage.includes('already registered in your organization')) {
      notifications.show(t('web.domains.domain_already_in_organization'), 'warning');
      await store.fetchList();
      const existingDomain = store.records?.find(d => d.display_domain === domain);
      if (existingDomain && orgid.value) {
        setTimeout(() => {
          router.push({
            name: 'DomainVerify',
            params: { orgid: orgid.value, extid: existingDomain.extid },
          });
        }, 2000);
      }
      return null;
    }
    if (errorMessage.includes('registered to another organization')) {
      notifications.show(t('web.domains.domain_in_other_organization'), 'error');
      return null;
    }
    return undefined; // Signal to re-throw
  };

  /** Update domain context after adding a domain */
  const updateDomainContextAfterAdd = (
    record: CustomDomain,
    details: { domain_context?: string | null } | undefined
  ) => {
    const { setContext } = useDomainContext();
    const contextFromServer = details?.domain_context;
    // Skip backend sync when server already set the context
    if (contextFromServer) {
      setContext(contextFromServer, true);
    } else {
      setContext(record.display_domain);
    }
  };

  const handleAddDomain = async (domain: string) =>
    wrap(async () => {
      try {
        // Pass org_id from route params to ensure correct org context
        const result = await store.addDomain(domain, orgid.value);
        if (!result?.record) {
          error.value = createError(t('web.domains.failed_to_add_domain'), 'human', 'error');
          return null;
        }

        const { record, details } = result;
        const isReclaimed = record.updated.getTime() > record.created.getTime();
        const message = isReclaimed ? 'web.domains.domain_claimed_successfully' : 'web.domains.domain_added_successfully';
        notifications.show(t(message), 'success');

        updateDomainContextAfterAdd(record, details);

        if (orgid.value) {
          router.push({
            name: 'DomainVerify',
            params: { orgid: orgid.value, extid: record.extid },
          });
        }
        setTimeout(() => verifyDomain(record.extid), 2000);
        return record;
      } catch (err: any) {
        const errorMessage = err?.response?.data?.message || err?.message || '';
        const handled = await handleDomainExistsError(domain, errorMessage);
        if (handled !== undefined) return handled;
        throw err;
      }
    });

  const deleteDomain = async (domainId: string) => {
    await store.deleteDomain(domainId);
    notifications.show(t('web.domains.domain_removed_successfully'), 'success');
  };

  /**
   * Refresh domain records for the current organization context.
   * Uses org identifier from route params (:orgid or :extid) to ensure
   * correct org-scoped fetch, especially after org creation/switch.
   */
  const refreshRecords = async (force = false) => store.refreshRecords({ orgId: orgIdentifier.value, force });

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
