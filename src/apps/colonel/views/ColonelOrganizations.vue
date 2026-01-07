<!-- src/apps/colonel/views/ColonelOrganizations.vue -->
<!--
  Billing Health Monitor - Admin view for identifying organizations with billing sync issues.
  Design principles:
  - Lead with unique identifier (contact_email), not generic "Default Organization"
  - Only badge problems (potentially_stale), not normal state (synced)
  - Table format for scanability during admin triage
  - Group billing data together
  - Show sync_status_reason prominently when there's a problem
-->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import type { ColonelOrganization } from '@/schemas/api/account/endpoints/colonel';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { organizations, organizationsPagination, isLoading } = storeToRefs(store);
  const { fetchOrganizations } = store;

  // Filter state
  const statusFilter = ref<string>('');
  const syncStatusFilter = ref<string>('');

  // Expanded row state for Stripe IDs
  const expandedRows = ref<Set<string>>(new Set());

  // Sort state
  type SortField = 'contact_email' | 'planid' | 'subscription_status' | 'sync_status' | 'created';
  type SortDirection = 'asc' | 'desc';
  const sortField = ref<SortField>('sync_status');
  const sortDirection = ref<SortDirection>('desc');

  onMounted(() => fetchOrganizations());

  // Apply filters
  async function applyFilters(): Promise<void> {
    await fetchOrganizations(
      1,
      50,
      statusFilter.value || undefined,
      syncStatusFilter.value || undefined
    );
  }

  // Clear filters
  async function clearFilters(): Promise<void> {
    statusFilter.value = '';
    syncStatusFilter.value = '';
    await fetchOrganizations();
  }

  // Toggle row expansion for Stripe IDs
  function toggleRowExpansion(orgId: string): void {
    if (expandedRows.value.has(orgId)) {
      expandedRows.value.delete(orgId);
    } else {
      expandedRows.value.add(orgId);
    }
  }

  // Sort handler
  function handleSort(field: SortField): void {
    if (sortField.value === field) {
      sortDirection.value = sortDirection.value === 'asc' ? 'desc' : 'asc';
    } else {
      sortField.value = field;
      sortDirection.value = 'asc';
    }
  }

  // Get sort priority for sync_status (stale first, then unknown, then synced)
  function getSyncStatusPriority(status: string): number {
    if (status === 'potentially_stale') return 0;
    if (status === 'unknown') return 1;
    return 2;
  }

  // Get sortable value for an organization based on current sort field
  function getSortValue(org: ColonelOrganization): string | number {
    switch (sortField.value) {
      case 'contact_email':
        return org.contact_email ?? '';
      case 'planid':
        return org.planid ?? '';
      case 'subscription_status':
        return org.subscription_status ?? '';
      case 'sync_status':
        return getSyncStatusPriority(org.sync_status);
      case 'created':
        return org.created;
      default:
        return 0;
    }
  }

  // Sorted organizations
  const sortedOrganizations = computed(() => {
    const orgs = [...organizations.value];
    const dir = sortDirection.value === 'asc' ? 1 : -1;

    return orgs.sort((a, b) => {
      const aVal = getSortValue(a);
      const bVal = getSortValue(b);

      if (aVal < bVal) return -1 * dir;
      if (aVal > bVal) return 1 * dir;
      return 0;
    });
  });

  // Subscription status badge - only show for non-active states
  function getSubscriptionBadgeClass(status: string | null): string {
    switch (status) {
      case 'trialing':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900/50 dark:text-blue-200';
      case 'past_due':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-200';
      case 'canceled':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      default:
        return '';
    }
  }

  // Check if subscription needs badge (non-normal states)
  function needsSubscriptionBadge(status: string | null): boolean {
    return status !== null && status !== 'active';
  }

  // Get primary identifier for an org
  function getPrimaryIdentifier(org: ColonelOrganization): string {
    return org.contact_email || org.extid;
  }

  // Format plan ID for display (strip common suffixes)
  function formatPlanId(planid: string | null): string {
    if (!planid) return 'free';
    // Remove common suffixes for cleaner display
    return planid
      .replace(/_monthly$/, '')
      .replace(/_yearly$/, '')
      .replace(/_v\d+$/, '');
  }

  const totalOrganizations = computed(() => organizationsPagination.value?.total_count || 0);
  const staleCount = computed(() =>
    organizations.value.filter((o) => o.sync_status === 'potentially_stale').length
  );
  const unknownCount = computed(() =>
    organizations.value.filter((o) => o.sync_status === 'unknown').length
  );
</script>

<template>
  <div>
    <div
      v-if="isLoading"
      class="py-12 text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <!-- Back navigation -->
      <div class="mb-4">
        <router-link
          to="/colonel"
          class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
          <svg
            class="mr-1 size-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 19l-7-7 7-7" />
          </svg>
          {{ t('web.COMMON.back') }}
        </router-link>
      </div>

      <!-- Header with status summary -->
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          Billing Health Monitor
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ totalOrganizations }} organizations
          <template v-if="staleCount > 0 || unknownCount > 0">
            <span class="mx-1">-</span>
            <span
              v-if="staleCount > 0"
              class="font-medium text-yellow-600 dark:text-yellow-400">
              {{ staleCount }} need attention
            </span>
            <span
              v-if="staleCount > 0 && unknownCount > 0"
              class="mx-1">/</span>
            <span
              v-if="unknownCount > 0"
              class="text-gray-500 dark:text-gray-400">
              {{ unknownCount }} unknown
            </span>
          </template>
        </p>
      </div>

      <!-- Filters -->
      <div class="mb-6 flex flex-wrap items-center gap-4 rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-800">
        <div class="flex items-center gap-2">
          <label
            for="sync-status-filter"
            class="text-sm font-medium text-gray-700 dark:text-gray-300">
            Sync Status:
          </label>
          <select
            id="sync-status-filter"
            v-model="syncStatusFilter"
            class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="">All</option>
            <option value="potentially_stale">Potentially Stale</option>
            <option value="unknown">Unknown</option>
            <option value="synced">Synced</option>
          </select>
        </div>

        <div class="flex items-center gap-2">
          <label
            for="status-filter"
            class="text-sm font-medium text-gray-700 dark:text-gray-300">
            Subscription:
          </label>
          <select
            id="status-filter"
            v-model="statusFilter"
            class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="">All</option>
            <option value="active">Active</option>
            <option value="trialing">Trialing</option>
            <option value="past_due">Past Due</option>
            <option value="canceled">Canceled</option>
          </select>
        </div>

        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-md bg-brand-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            @click="applyFilters">
            {{ t('web.LABELS.filter') }}
          </button>
          <button
            type="button"
            class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
            @click="clearFilters">
            {{ t('web.LABELS.clear') }}
          </button>
        </div>
      </div>

      <!-- Empty state -->
      <div
        v-if="organizations.length === 0"
        class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-800">
        <p class="text-gray-500 dark:text-gray-400">
          No organizations found
        </p>
      </div>

      <!-- Organizations table -->
      <div
        v-else
        class="overflow-x-auto rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-900">
            <tr>
              <!-- Primary Identifier (Email) -->
              <th
                scope="col"
                class="cursor-pointer px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                @click="handleSort('contact_email')">
                <div class="flex items-center gap-1">
                  Account
                  <svg
                    v-if="sortField === 'contact_email'"
                    class="size-3"
                    :class="{ 'rotate-180': sortDirection === 'desc' }"
                    fill="currentColor"
                    viewBox="0 0 20 20">
                    <path d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" />
                  </svg>
                </div>
              </th>

              <!-- Billing Group: Plan + Subscription -->
              <th
                scope="col"
                class="cursor-pointer px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                @click="handleSort('planid')">
                <div class="flex items-center gap-1">
                  Billing
                  <svg
                    v-if="sortField === 'planid'"
                    class="size-3"
                    :class="{ 'rotate-180': sortDirection === 'desc' }"
                    fill="currentColor"
                    viewBox="0 0 20 20">
                    <path d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" />
                  </svg>
                </div>
              </th>

              <!-- Status (only show issues) -->
              <th
                scope="col"
                class="cursor-pointer px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                @click="handleSort('sync_status')">
                <div class="flex items-center gap-1">
                  Status
                  <svg
                    v-if="sortField === 'sync_status'"
                    class="size-3"
                    :class="{ 'rotate-180': sortDirection === 'desc' }"
                    fill="currentColor"
                    viewBox="0 0 20 20">
                    <path d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" />
                  </svg>
                </div>
              </th>

              <!-- Usage stats -->
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Usage
              </th>

              <!-- Created -->
              <th
                scope="col"
                class="cursor-pointer px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                @click="handleSort('created')">
                <div class="flex items-center gap-1">
                  Created
                  <svg
                    v-if="sortField === 'created'"
                    class="size-3"
                    :class="{ 'rotate-180': sortDirection === 'desc' }"
                    fill="currentColor"
                    viewBox="0 0 20 20">
                    <path d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" />
                  </svg>
                </div>
              </th>

              <!-- Expand for Stripe IDs -->
              <th
                scope="col"
                class="px-4 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                <span class="sr-only">Details</span>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <template
              v-for="org in sortedOrganizations"
              :key="org.org_id">
              <!-- Main row -->
              <tr
                class="hover:bg-gray-50 dark:hover:bg-gray-700/50"
                :class="{
                  'bg-yellow-50/50 dark:bg-yellow-900/10': org.sync_status === 'potentially_stale'
                }">
                <!-- Account (primary identifier) -->
                <td class="whitespace-nowrap px-4 py-3">
                  <div class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ getPrimaryIdentifier(org) }}
                  </div>
                  <div
                    v-if="org.display_name && org.display_name !== 'Default Organization'"
                    class="text-xs text-gray-500 dark:text-gray-400">
                    {{ org.display_name }}
                  </div>
                </td>

                <!-- Billing (Plan + Subscription grouped) -->
                <td class="whitespace-nowrap px-4 py-3">
                  <div class="text-sm text-gray-900 dark:text-white">
                    {{ formatPlanId(org.planid) }}
                  </div>
                  <div class="mt-0.5">
                    <span
                      v-if="needsSubscriptionBadge(org.subscription_status)"
                      :class="[
                        'inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium',
                        getSubscriptionBadgeClass(org.subscription_status)
                      ]">
                      {{ org.subscription_status }}
                    </span>
                    <span
                      v-else-if="org.subscription_status === 'active'"
                      class="text-xs text-gray-500 dark:text-gray-400">
                      active
                    </span>
                    <span
                      v-else
                      class="text-xs text-gray-400 dark:text-gray-500">
                      -
                    </span>
                  </div>
                </td>

                <!-- Status (only badge problems) -->
                <td class="px-4 py-3">
                  <template v-if="org.sync_status === 'potentially_stale'">
                    <span class="inline-flex items-center rounded bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-200">
                      Stale
                    </span>
                    <div
                      v-if="org.sync_status_reason"
                      class="mt-1 max-w-xs text-xs text-yellow-700 dark:text-yellow-300">
                      {{ org.sync_status_reason }}
                    </div>
                  </template>
                  <template v-else-if="org.sync_status === 'unknown'">
                    <span class="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                      Unknown
                    </span>
                  </template>
                  <template v-else>
                    <span class="text-xs text-gray-400 dark:text-gray-500">-</span>
                  </template>
                </td>

                <!-- Usage (members/domains) -->
                <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                  <span :title="`${org.member_count} members`">{{ org.member_count }}m</span>
                  <span class="mx-1">/</span>
                  <span :title="`${org.domain_count} domains`">{{ org.domain_count }}d</span>
                </td>

                <!-- Created -->
                <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                  {{ org.created_human }}
                </td>

                <!-- Expand button -->
                <td class="whitespace-nowrap px-4 py-3 text-right">
                  <button
                    v-if="org.stripe_customer_id || org.stripe_subscription_id"
                    type="button"
                    class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                    :aria-expanded="expandedRows.has(org.org_id)"
                    :aria-label="expandedRows.has(org.org_id) ? 'Collapse Stripe details' : 'Expand Stripe details'"
                    @click="toggleRowExpansion(org.org_id)">
                    <svg
                      class="size-5 transition-transform"
                      :class="{ 'rotate-180': expandedRows.has(org.org_id) }"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                </td>
              </tr>

              <!-- Expanded row for Stripe IDs -->
              <tr
                v-if="expandedRows.has(org.org_id)"
                class="bg-gray-50 dark:bg-gray-800/50">
                <td
                  colspan="6"
                  class="px-4 py-3">
                  <div class="flex flex-wrap gap-6 text-xs">
                    <div v-if="org.stripe_customer_id">
                      <span class="font-medium text-gray-500 dark:text-gray-400">Customer:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.stripe_customer_id }}
                      </code>
                    </div>
                    <div v-if="org.stripe_subscription_id">
                      <span class="font-medium text-gray-500 dark:text-gray-400">Subscription:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.stripe_subscription_id }}
                      </code>
                    </div>
                    <div>
                      <span class="font-medium text-gray-500 dark:text-gray-400">Org ID:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.extid }}
                      </code>
                    </div>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
