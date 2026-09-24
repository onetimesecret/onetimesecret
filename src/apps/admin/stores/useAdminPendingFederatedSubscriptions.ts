// src/apps/admin/stores/useAdminPendingFederatedSubscriptions.ts

import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
import {
  colonelPendingFederatedSubscriptionsResponseSchema,
  type ColonelPendingFederatedSubscription,
  type ColonelPendingFederatedSubscriptionsResponse,
} from '@/schemas/api/internal/responses/colonel-billing';
import { defineStore } from 'pinia';
import { ref } from 'vue';

/** Read-only, paginated inventory of subscriptions awaiting a federated claim. */
export const PENDING_FEDERATED_SUBSCRIPTIONS_URL =
  '/api/colonel/billing/pending-federated-subscriptions';

export const useAdminPendingFederatedSubscriptions = defineStore(
  'adminPendingFederatedSubscriptions',
  () => {
    const subscriptions = ref<ColonelPendingFederatedSubscription[]>([]);
    const pagination = ref<PageMeta | null>(null);
    const capped = ref(false);
    /** Index entries on the current page whose pending record no longer loads. */
    const staleCount = ref(0);

    const pager = usePaginatedFetch<
      ColonelPendingFederatedSubscriptionsResponse,
      ColonelPendingFederatedSubscription
    >({
      url: PENDING_FEDERATED_SUBSCRIPTIONS_URL,
      schema: colonelPendingFederatedSubscriptionsResponseSchema,
      context: 'ColonelPendingFederatedSubscriptionsResponse',
      select: (data) => {
        const meta = data.details?.pagination ?? null;
        capped.value = meta?.capped === true || data.details?.capped === true;
        staleCount.value = meta?.stale_count ?? data.details?.stale_count ?? 0;
        return { items: data.details?.subscriptions ?? [], pagination: meta };
      },
    });

    async function fetchPage(targetPage: number = pager.page.value): Promise<{
      items: ColonelPendingFederatedSubscription[];
      pagination: PageMeta | null;
    } | null> {
      try {
        const result = await pager.fetchPage(targetPage);
        subscriptions.value = result?.items ?? [];
        pagination.value = result?.pagination ?? null;
        if (!result) {
          capped.value = false;
          staleCount.value = 0;
        }
        return result;
      } catch (error) {
        subscriptions.value = [];
        pagination.value = null;
        capped.value = false;
        staleCount.value = 0;
        throw error;
      }
    }

    function $reset(): void {
      subscriptions.value = [];
      pagination.value = null;
      capped.value = false;
      staleCount.value = 0;
      pager.reset();
    }

    return {
      subscriptions,
      pagination,
      capped,
      staleCount,
      loading: pager.loading,
      error: pager.error,
      validationError: pager.validationError,
      page: pager.page,
      perPage: pager.perPage,
      fetchPage,
      $reset,
    };
  }
);
