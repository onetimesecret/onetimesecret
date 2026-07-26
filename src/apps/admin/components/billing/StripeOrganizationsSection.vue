<!-- src/apps/admin/components/billing/StripeOrganizationsSection.vue -->

<script setup lang="ts">
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminBilling } from '@/apps/admin/stores/useAdminBilling';
  import type { ColonelStripeOrganization } from '@/apps/admin/stores/useAdminBilling';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import { storeToRefs } from 'pinia';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Stripe customers roster — the "who is actually billed" half of the billing
   * screen, next to the config-vs-live catalog drift.
   *
   * Backed by the index the Organization model already declares
   * (`organization:stripe_customer_id_index`), so this is a bounded, paged read
   * rather than a scan of every organization: one server page per request via
   * {@link useAdminBilling}, with a debounced server-side `search` over the
   * Stripe customer id.
   *
   * Stripe ids live ONLY on Organization (Customer#stripe_customer_id is a
   * deprecated, unindexed field), so a "customer with a Stripe id" is reached
   * through its org — every row links to /colonel/organizations/:id, which is
   * where the member roster and the investigate/reconcile actions live.
   *
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
   */
  const { t } = useI18n();

  const store = useAdminBilling();
  const { stripeOrganizations, pagination, loading, error, unavailable, capped, staleCount } =
    storeToRefs(store);

  const searchTerm = ref('');
  const activeSearch = ref('');

  const hasActiveFilters = computed(() => searchTerm.value !== '');

  const columns = computed<DataTableColumn<ColonelStripeOrganization>[]>(() => [
    { key: 'organization', label: t('web.admin.billing.stripeOrgs.columns.organization') },
    { key: 'owner', label: t('web.admin.billing.stripeOrgs.columns.owner') },
    { key: 'plan', label: t('web.admin.billing.stripeOrgs.columns.plan') },
    { key: 'subscription', label: t('web.admin.billing.stripeOrgs.columns.subscription') },
    { key: 'stripeCustomer', label: t('web.admin.billing.stripeOrgs.columns.stripeCustomer') },
  ]);

  /** Fetch one server page with the committed search. Errors land in the store. */
  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchStripeOrganizations(targetPage, {
        search: activeSearch.value || undefined,
      });
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it never becomes unhandled.
    }
  }

  // Debounce so we issue one request per pause, not per keystroke. The no-op
  // guard keeps the programmatic reset in onClear() from double-fetching
  // (the AdminCustomers form of this watcher — the fixed one).
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  watch(searchTerm, (value) => {
    if (searchTimer) clearTimeout(searchTimer);
    if (value.trim() === activeSearch.value) return;
    searchTimer = setTimeout(() => {
      activeSearch.value = value.trim();
      fetchPage(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (searchTimer) clearTimeout(searchTimer);
  });

  function onClear(): void {
    // Cancel any in-flight debounce so the reset below doesn't fire a second,
    // late request on top of this one.
    if (searchTimer) clearTimeout(searchTimer);
    searchTerm.value = '';
    activeSearch.value = '';
    fetchPage(1);
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    // The composable owns perPage (reconciled from the server echo); set it
    // then re-fetch the first page at the new size.
    store.perPage = perPage;
    fetchPage(1);
  }

  /**
   * Link label for a row: name, then the extid. The billing email is
   * deliberately NOT a label fallback — a raw address in link text would break
   * the console-wide obscure-by-default pattern; it renders through
   * {@link RevealEmail} under the link instead (see the organization cell).
   */
  function orgLabel(row: ColonelStripeOrganization): string {
    return row.display_name || row.extid;
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <section data-testid="billing-stripe-orgs">
    <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.billing.stripeOrgs.title') }}
        <span
          v-if="pagination"
          class="ml-1 text-sm font-normal text-gray-500 tabular-nums dark:text-gray-400"
          data-testid="billing-stripe-orgs-count">
          ({{ pagination.total_count }})
        </span>
      </h3>
      <p class="text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.billing.stripeOrgs.description') }}
      </p>
    </div>

    <!-- The roster endpoint is not served by this backend build. Informational,
         not an error: there is nothing for the operator to retry. -->
    <div
      v-if="unavailable"
      class="flex items-start gap-2 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-800 dark:bg-gray-800/40"
      role="status"
      data-testid="billing-stripe-orgs-unavailable">
      <OIcon
        collection="heroicons"
        name="information-circle"
        size="5"
        class="mt-0.5 shrink-0 text-gray-500 dark:text-gray-400" />
      <span class="text-sm text-gray-700 dark:text-gray-300">
        {{ t('web.admin.billing.stripeOrgs.unavailable') }}
      </span>
    </div>

    <template v-else>
      <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
      <div
        v-if="error"
        class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="billing-stripe-orgs-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.billing.stripeOrgs.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          data-testid="billing-stripe-orgs-retry"
          @click="fetchPage(pagination?.page ?? 1)">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.billing.retry') }}
        </button>
      </div>

      <!-- The server's index scan is bounded: when it caps, total_count is a
           FLOOR. Say so rather than letting "(N)" read as the population. -->
      <div
        v-if="capped || staleCount > 0"
        class="mb-4 flex flex-col gap-1 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
        role="status"
        data-testid="billing-stripe-orgs-caveat">
        <span v-if="capped">{{ t('web.admin.billing.stripeOrgs.capped') }}</span>
        <span v-if="staleCount > 0">
          {{ t('web.admin.billing.stripeOrgs.stale', { count: staleCount }) }}
        </span>
      </div>

      <div class="mb-4">
        <FilterBar
          v-model:search="searchTerm"
          :search-placeholder="t('web.admin.billing.stripeOrgs.searchPlaceholder')"
          :has-active-filters="hasActiveFilters"
          testid="billing-stripe-orgs-filterbar"
          @clear="onClear" />
      </div>

      <div
        class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <DataTable
          :columns="columns"
          :rows="stripeOrganizations"
          row-key="extid"
          :loading="loading"
          :empty-text="
            activeSearch
              ? t('web.admin.billing.stripeOrgs.emptySearch')
              : t('web.admin.billing.stripeOrgs.empty')
          "
          testid="billing-stripe-orgs-table">
          <!-- The org is the route to everything else (members, investigate,
               reconcile), so the name cell is the link — keyboard reachable,
               unlike a clickable row. -->
          <template #cell-organization="{ row }">
            <router-link
              :to="{ name: 'AdminOrganizationDetail', params: { id: row.extid } }"
              :data-testid="`stripe-org-link-${row.extid}`"
              class="inline-flex items-center gap-1 font-medium text-brand-600 hover:text-brand-800 hover:underline focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-brand-400 dark:hover:text-brand-300">
              {{ orgLabel(row) }}
              <OIcon
                collection="heroicons"
                name="arrow-top-right-on-square"
                size="3"
                class="shrink-0" />
            </router-link>
            <!-- Obscure-by-default (same as the Owner column): when the label
                 degraded to the extid, surface the billing address through
                 RevealEmail. It lives OUTSIDE the link — RevealEmail's toggle
                 is interactive, and nesting it in an anchor would turn every
                 reveal click into a navigation (and is invalid nesting). -->
            <div
              v-if="!row.display_name && row.billing_email"
              class="mt-0.5"
              :data-testid="`stripe-org-billing-email-${row.extid}`">
              <RevealEmail :email="row.billing_email ?? null" />
            </div>
            <!-- The muted extid line only when it is not already the label. -->
            <div
              v-if="row.display_name"
              class="mt-0.5 font-mono text-xs text-gray-400 tabular-nums dark:text-gray-500">
              {{ row.extid }}
            </div>
          </template>

          <template #cell-owner="{ row }">
            <RevealEmail :email="row.owner_email ?? row.billing_email ?? null" />
          </template>

          <template #cell-plan="{ row }">
            {{ row.planid || t('web.admin.billing.stripeOrgs.none') }}
          </template>

          <template #cell-subscription="{ row }">
            <span
              v-if="row.subscription_status"
              class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
              :class="
                row.subscription_status === 'active' || row.subscription_status === 'trialing'
                  ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200'
                  : 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200'
              ">
              {{ row.subscription_status }}
            </span>
            <span
              v-else
              class="text-gray-400 dark:text-gray-600">
              —
            </span>
          </template>

          <template #cell-stripeCustomer="{ row }">
            <span class="inline-flex items-center gap-1.5">
              <span
                class="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs break-all text-gray-700 tabular-nums dark:bg-gray-800 dark:text-gray-300">
                {{ row.stripe_customer_id }}
              </span>
              <CopyButton
                :text="row.stripe_customer_id"
                :tooltip="t('web.admin.billing.stripeOrgs.copyStripeId')"
                :testid="`stripe-org-copy-${row.extid}`" />
            </span>
          </template>
        </DataTable>
      </div>

      <KitPagination
        v-if="pagination"
        :pagination="pagination"
        :loading="loading"
        class="mt-4"
        @update:page="onPageChange"
        @update:per-page="onPerPageChange" />
    </template>
  </section>
</template>
