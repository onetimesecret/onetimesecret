// src/apps/admin/stores/useAdminWebhookEvents.ts

import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
import {
  colonelWebhookEventsResponseSchema,
  type ColonelWebhookEvent,
  type ColonelWebhookEventsResponse,
} from '@/schemas/api/internal/responses/colonel-billing';
import { defineStore } from 'pinia';
import { ref } from 'vue';

/** Read-only, paginated local Stripe webhook-event log. */
export const WEBHOOK_EVENTS_URL = '/api/colonel/billing/webhook-events';

export const useAdminWebhookEvents = defineStore('adminWebhookEvents', () => {
  const events = ref<ColonelWebhookEvent[]>([]);
  const pagination = ref<PageMeta | null>(null);
  const capped = ref(false);

  const pager = usePaginatedFetch<ColonelWebhookEventsResponse, ColonelWebhookEvent>({
    url: WEBHOOK_EVENTS_URL,
    schema: colonelWebhookEventsResponseSchema,
    context: 'ColonelWebhookEventsResponse',
    select: (data) => {
      const meta = data.details?.pagination ?? null;
      capped.value = meta?.capped === true || data.details?.capped === true;
      return { items: data.details?.events ?? [], pagination: meta };
    },
  });

  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelWebhookEvent[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      events.value = result?.items ?? [];
      pagination.value = result?.pagination ?? null;
      if (!result) capped.value = false;
      return result;
    } catch (error) {
      events.value = [];
      pagination.value = null;
      capped.value = false;
      throw error;
    }
  }

  function $reset(): void {
    events.value = [];
    pagination.value = null;
    capped.value = false;
    pager.reset();
  }

  return {
    events,
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
});
