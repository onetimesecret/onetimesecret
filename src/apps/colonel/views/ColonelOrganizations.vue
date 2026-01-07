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
  import type {
    ColonelOrganization,
    InvestigateOrganizationResult,
  } from '@/schemas/api/account/endpoints/colonel';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { organizations, organizationsPagination, isLoading } = storeToRefs(store);
  const { fetchOrganizations, investigateOrganization } = store;

  // Filter state
  const statusFilter = ref<string>('');
  const syncStatusFilter = ref<string>('');

  // Expanded row state for Stripe IDs
  const expandedRows = ref<Set<string>>(new Set());

  // Investigation state
  const investigatingOrgs = ref<Set<string>>(new Set());
  const investigationResults = ref<Map<string, InvestigateOrganizationResult>>(new Map());
  const investigationErrors = ref<Map<string, string>>(new Map());

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
  // Uses extid (external ID) for consistent URL-friendly identifiers
  function toggleRowExpansion(extId: string): void {
    if (expandedRows.value.has(extId)) {
      expandedRows.value.delete(extId);
    } else {
      expandedRows.value.add(extId);
    }
  }

  // Investigate an organization's billing state
  // Uses extid (external ID) for API routes per project conventions
  async function handleInvestigate(extId: string): Promise<void> {
    investigatingOrgs.value.add(extId);
    investigationErrors.value.delete(extId);

    try {
      const result = await investigateOrganization(extId);
      investigationResults.value.set(extId, result);
      // Auto-expand the row to show results
      expandedRows.value.add(extId);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Investigation failed';
      investigationErrors.value.set(extId, message);
    } finally {
      investigatingOrgs.value.delete(extId);
    }
  }

  // Check if org has investigation result
  function hasInvestigationResult(extId: string): boolean {
    return investigationResults.value.has(extId);
  }

  // Get investigation result for an org
  function getInvestigationResult(extId: string): InvestigateOrganizationResult | undefined {
    return investigationResults.value.get(extId);
  }

  // Get verdict badge class
  function getVerdictBadgeClass(verdict: string): string {
    switch (verdict) {
      case 'synced':
        return 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200';
      case 'mismatch_detected':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
    }
  }

  // Get severity badge class for issues
  function getSeverityBadgeClass(severity: string): string {
    switch (severity) {
      case 'critical':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      case 'high':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900/50 dark:text-orange-200';
      case 'medium':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-200';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
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
          {{ t('web.colonel.organizations.pageTitle') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.organizations.organizationsCount', { count: totalOrganizations }) }}
          <template v-if="staleCount > 0 || unknownCount > 0">
            <span class="mx-1">-</span>
            <span
              v-if="staleCount > 0"
              class="font-medium text-yellow-600 dark:text-yellow-400">
              {{ t('web.colonel.organizations.needAttention', { count: staleCount }) }}
            </span>
            <span
              v-if="staleCount > 0 && unknownCount > 0"
              class="mx-1">/</span>
            <span
              v-if="unknownCount > 0"
              class="text-gray-500 dark:text-gray-400">
              {{ t('web.colonel.organizations.unknownCount', { count: unknownCount }) }}
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
            {{ t('web.colonel.organizations.filters.syncStatus') }}:
          </label>
          <select
            id="sync-status-filter"
            v-model="syncStatusFilter"
            class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="">{{ t('web.colonel.organizations.filters.all') }}</option>
            <option value="potentially_stale">{{ t('web.colonel.organizations.filters.potentiallyStale') }}</option>
            <option value="unknown">{{ t('web.colonel.organizations.filters.unknown') }}</option>
            <option value="synced">{{ t('web.colonel.organizations.filters.synced') }}</option>
          </select>
        </div>

        <div class="flex items-center gap-2">
          <label
            for="status-filter"
            class="text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.colonel.organizations.filters.subscription') }}:
          </label>
          <select
            id="status-filter"
            v-model="statusFilter"
            class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="">{{ t('web.colonel.organizations.filters.all') }}</option>
            <option value="active">{{ t('web.colonel.organizations.filters.active') }}</option>
            <option value="trialing">{{ t('web.colonel.organizations.filters.trialing') }}</option>
            <option value="past_due">{{ t('web.colonel.organizations.filters.pastDue') }}</option>
            <option value="canceled">{{ t('web.colonel.organizations.filters.canceled') }}</option>
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
          {{ t('web.colonel.organizations.noOrganizations') }}
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
                  {{ t('web.colonel.organizations.columns.account') }}
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
                  {{ t('web.colonel.organizations.columns.billing') }}
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
                  {{ t('web.colonel.organizations.columns.status') }}
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
                {{ t('web.colonel.organizations.columns.usage') }}
              </th>

              <!-- Created -->
              <th
                scope="col"
                class="cursor-pointer px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                @click="handleSort('created')">
                <div class="flex items-center gap-1">
                  {{ t('web.colonel.organizations.columns.created') }}
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
                <span class="sr-only">{{ t('web.colonel.organizations.columns.details') }}</span>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <template
              v-for="org in sortedOrganizations"
              :key="org.extid">
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
                      {{ t('web.colonel.organizations.status.active') }}
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
                      {{ t('web.colonel.organizations.status.stale') }}
                    </span>
                    <div
                      v-if="org.sync_status_reason"
                      class="mt-1 max-w-xs text-xs text-yellow-700 dark:text-yellow-300">
                      {{ org.sync_status_reason }}
                    </div>
                  </template>
                  <template v-else-if="org.sync_status === 'unknown'">
                    <span class="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                      {{ t('web.colonel.organizations.status.unknown') }}
                    </span>
                  </template>
                  <template v-else>
                    <span class="text-xs text-gray-400 dark:text-gray-500">-</span>
                  </template>
                </td>

                <!-- Usage (members/domains) -->
                <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                  <span :title="t('web.colonel.organizations.usage.members', { count: org.member_count })">{{ org.member_count }}m</span>
                  <span class="mx-1">/</span>
                  <span :title="t('web.colonel.organizations.usage.domains', { count: org.domain_count })">{{ org.domain_count }}d</span>
                </td>

                <!-- Created -->
                <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                  {{ org.created_human }}
                </td>

                <!-- Actions -->
                <td class="whitespace-nowrap px-4 py-3 text-right">
                  <div class="flex items-center justify-end gap-2">
                    <!-- Investigate button -->
                    <button
                      type="button"
                      class="inline-flex items-center rounded px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 hover:text-brand-700 dark:text-brand-400 dark:hover:bg-brand-900/20 dark:hover:text-brand-300"
                      :disabled="investigatingOrgs.has(org.extid)"
                      @click="handleInvestigate(org.extid)">
                      <svg
                        v-if="investigatingOrgs.has(org.extid)"
                        class="mr-1 size-3 animate-spin"
                        fill="none"
                        viewBox="0 0 24 24">
                        <circle
                          class="opacity-25"
                          cx="12"
                          cy="12"
                          r="10"
                          stroke="currentColor"
                          stroke-width="4" />
                        <path
                          class="opacity-75"
                          fill="currentColor"
                          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                      </svg>
                      <svg
                        v-else
                        class="mr-1 size-3"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                      </svg>
                      {{ investigatingOrgs.has(org.extid) ? t('web.colonel.organizations.actions.checking') : t('web.colonel.organizations.actions.investigate') }}
                    </button>

                    <!-- Expand/collapse button -->
                    <button
                      type="button"
                      class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      :aria-expanded="expandedRows.has(org.extid)"
                      :aria-label="expandedRows.has(org.extid) ? 'Collapse details' : 'Expand details'"
                      @click="toggleRowExpansion(org.extid)">
                      <svg
                        class="size-5 transition-transform"
                        :class="{ 'rotate-180': expandedRows.has(org.extid) }"
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
                  </div>
                </td>
              </tr>

              <!-- Expanded row for details and investigation results -->
              <tr
                v-if="expandedRows.has(org.extid)"
                class="bg-gray-50 dark:bg-gray-800/50">
                <td
                  colspan="6"
                  class="px-4 py-4">
                  <!-- Stripe IDs -->
                  <div class="mb-4 flex flex-wrap gap-6 text-xs">
                    <div v-if="org.stripe_customer_id">
                      <span class="font-medium text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.expanded.customer') }}:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.stripe_customer_id }}
                      </code>
                    </div>
                    <div v-if="org.stripe_subscription_id">
                      <span class="font-medium text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.expanded.subscription') }}:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.stripe_subscription_id }}
                      </code>
                    </div>
                    <div>
                      <span class="font-medium text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.expanded.orgId') }}:</span>
                      <code class="ml-1 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                        {{ org.extid }}
                      </code>
                    </div>
                  </div>

                  <!-- Investigation error -->
                  <div
                    v-if="investigationErrors.get(org.extid)"
                    class="rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-300">
                    {{ t('web.colonel.organizations.investigation.failed') }}: {{ investigationErrors.get(org.extid) }}
                  </div>

                  <!-- Investigation results -->
                  <div
                    v-if="hasInvestigationResult(org.extid)"
                    class="rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-600 dark:bg-gray-700">
                    <div class="mb-3 flex items-center justify-between">
                      <h4 class="text-sm font-medium text-gray-900 dark:text-white">
                        {{ t('web.colonel.organizations.investigation.result') }}
                      </h4>
                      <div class="flex items-center gap-2">
                        <span
                          :class="[
                            'inline-flex items-center rounded px-2 py-0.5 text-xs font-medium',
                            getVerdictBadgeClass(getInvestigationResult(org.extid)!.comparison.verdict)
                          ]">
                          {{ getInvestigationResult(org.extid)!.comparison.verdict === 'synced' ? t('web.colonel.organizations.investigation.verifiedSynced') : getInvestigationResult(org.extid)!.comparison.verdict === 'mismatch_detected' ? t('web.colonel.organizations.investigation.mismatchFound') : t('web.colonel.organizations.investigation.unableToCompare') }}
                        </span>
                        <span class="text-xs text-gray-500 dark:text-gray-400">
                          {{ getInvestigationResult(org.extid)!.investigated_at }}
                        </span>
                      </div>
                    </div>

                    <!-- Comparison details -->
                    <div
                      v-if="getInvestigationResult(org.extid)!.comparison.details"
                      class="mb-3 text-sm text-gray-600 dark:text-gray-300">
                      {{ getInvestigationResult(org.extid)!.comparison.details }}
                    </div>

                    <!-- Issues list -->
                    <div
                      v-if="getInvestigationResult(org.extid)!.comparison.issues?.length"
                      class="space-y-2">
                      <div
                        v-for="(issue, idx) in getInvestigationResult(org.extid)!.comparison.issues"
                        :key="idx"
                        class="rounded border border-gray-200 bg-gray-50 p-2 text-xs dark:border-gray-600 dark:bg-gray-800">
                        <div class="flex items-center gap-2">
                          <span
                            :class="[
                              'inline-flex items-center rounded px-1.5 py-0.5 font-medium',
                              getSeverityBadgeClass(issue.severity)
                            ]">
                            {{ issue.severity }}
                          </span>
                          <span class="font-medium text-gray-700 dark:text-gray-300">{{ issue.field }}</span>
                        </div>
                        <div class="mt-1 grid grid-cols-2 gap-4">
                          <div>
                            <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.local') }}:</span>
                            <code class="ml-1 text-gray-900 dark:text-white">{{ issue.local }}</code>
                          </div>
                          <div>
                            <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.stripe') }}:</span>
                            <code class="ml-1 text-gray-900 dark:text-white">{{ issue.stripe }}</code>
                          </div>
                        </div>
                      </div>
                    </div>

                    <!-- Stripe data summary (when available) -->
                    <div
                      v-if="getInvestigationResult(org.extid)!.stripe.available && getInvestigationResult(org.extid)!.stripe.subscription"
                      class="mt-3 border-t border-gray-200 pt-3 dark:border-gray-600">
                      <h5 class="mb-2 text-xs font-medium text-gray-500 dark:text-gray-400">
                        {{ t('web.colonel.organizations.investigation.stripeDetails') }}
                      </h5>
                      <div class="grid grid-cols-2 gap-2 text-xs md:grid-cols-4">
                        <div>
                          <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.statusLabel') }}:</span>
                          <span class="ml-1 font-medium text-gray-900 dark:text-white">
                            {{ getInvestigationResult(org.extid)!.stripe.subscription!.status }}
                          </span>
                        </div>
                        <div>
                          <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.product') }}:</span>
                          <span class="ml-1 font-medium text-gray-900 dark:text-white">
                            {{ getInvestigationResult(org.extid)!.stripe.subscription!.product_name || 'N/A' }}
                          </span>
                        </div>
                        <div>
                          <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.resolvedPlan') }}:</span>
                          <span class="ml-1 font-medium text-gray-900 dark:text-white">
                            {{ getInvestigationResult(org.extid)!.stripe.subscription!.resolved_plan_id || '(none)' }}
                          </span>
                        </div>
                        <div>
                          <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.organizations.investigation.priceId') }}:</span>
                          <code class="ml-1 font-mono text-gray-700 dark:text-gray-300">
                            {{ getInvestigationResult(org.extid)!.stripe.subscription!.price_id || 'N/A' }}
                          </code>
                        </div>
                      </div>
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
