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
        if (!result) capped.value = false;
        return result;
      } catch (error) {
        subscriptions.value = [];
        pagination.value = null;
        capped.value = false;
        throw error;
      }
    }

    function $reset(): void {
      subscriptions.value = [];
      pagination.value = null;
      capped.value = false;
      pager.reset();
    }

    return {
      subscriptions,
      pagination,
      capped,
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
