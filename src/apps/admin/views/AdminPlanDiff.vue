<!-- src/apps/admin/views/AdminPlanDiff.vue -->

<script setup lang="ts">
  import { JsonViewer } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { ColonelBillingPlan } from '@/schemas/api/internal/responses/colonel-billing';
  import { colonelBillingCatalogResponseSchema } from '@/schemas/api/internal/responses/colonel-billing';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  /**
   * Plan diff — the config-vs-live comparison for ONE plan, as a full page.
   *
   * Promoted out of the billing screen's slide-over: the payload is two JSON
   * documents side by side, which a `max-w-md` drawer cannot show without
   * horizontal cramping. Full page width means both blobs expand at once.
   *
   * Deep-linkable by design: the page fetches the catalog itself rather than
   * reading anything handed over by the navigation, so a refresh, a bookmark or
   * a pasted link renders identically. That is one extra GET of an endpoint the
   * billing screen already reads — acceptable for an operator tool, and the only
   * shape that survives a reload.
   *
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
   */
  const props = defineProps<{
    /**
     * The plan id being diffed (route param). Not key material and not
     * customer-identifying — it is a catalog id like `identity_plus_v1`.
     */
    planid: string;
  }>();

  const { t } = useI18n();
  const router = useRouter();

  const { data, loading, error, validationError, notFound, load } = useResourceFetch({
    url: '/api/colonel/billing/catalog',
    schema: colonelBillingCatalogResponseSchema,
    context: 'ColonelBillingCatalogResponse',
  });

  const details = computed(() => data.value?.details ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const loadFailed = computed(
    () => (error.value !== null && !notFound.value) || validationError.value !== null
  );

  function findPlan(plans: ColonelBillingPlan[] | undefined): ColonelBillingPlan | null {
    return plans?.find((plan) => plan.planid === props.planid) ?? null;
  }

  const configPlan = computed(() => findPlan(details.value?.config_plans));
  const livePlan = computed(() => findPlan(details.value?.live_plans));

  /** The catalog loaded, but this planid exists on neither side. */
  const planMissing = computed(
    () => details.value !== null && configPlan.value === null && livePlan.value === null
  );

  const isLocalConfig = computed(() => details.value?.source === 'local_config');

  /** Which comparable fields drift, per the server's computed drift summary. */
  const changedFields = computed<string[]>(
    () => details.value?.drift.changed.find((c) => c.planid === props.planid)?.fields ?? []
  );

  /** Same badge vocabulary as the catalog table, so the two screens agree. */
  type PlanStatus = 'in_sync' | 'only_config' | 'only_live' | 'changed';

  const status = computed<PlanStatus | null>(() => {
    if (!details.value) return null;
    if (configPlan.value && !livePlan.value) return 'only_config';
    if (!configPlan.value && livePlan.value) return 'only_live';
    if (changedFields.value.length > 0) return 'changed';
    return 'in_sync';
  });

  function statusBadgeClass(value: PlanStatus): string {
    switch (value) {
      case 'in_sync':
        return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
      case 'changed':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200';
      case 'only_config':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-200';
      case 'only_live':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-200';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
    }
  }

  /** The plan's display name from whichever side carries it. */
  const planName = computed(() => configPlan.value?.name ?? livePlan.value?.name ?? null);

  function goBack(): void {
    router.push({ name: 'AdminBilling' });
  }

  onMounted(() => {
    load().catch(() => {});
  });
</script>

<template>
  <!-- Wider than the standard detail page (max-w-5xl): two JSON documents side
       by side is the whole point of promoting this out of the drawer. -->
  <div class="mx-auto max-w-7xl">
    <button
      type="button"
      class="mb-4 inline-flex items-center gap-1 text-sm font-medium text-gray-600 hover:text-gray-900 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-gray-100"
      data-testid="detail-back"
      @click="goBack">
      <OIcon
        collection="heroicons"
        name="arrow-left"
        size="4" />
      {{ t('web.admin.billing.diff.backToCatalog') }}
    </button>

    <!-- Loading -->
    <div
      v-if="loading && !details"
      class="flex items-center justify-center py-24 text-gray-500 dark:text-gray-400"
      data-testid="detail-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        size="6"
        class="animate-spin motion-reduce:animate-none" />
      <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
    </div>

    <!-- The catalog loaded but carries no such plan (stale link / renamed plan). -->
    <div
      v-else-if="planMissing"
      class="rounded-lg border border-gray-200 bg-white px-6 py-16 text-center dark:border-gray-800 dark:bg-gray-900"
      data-testid="detail-not-found">
      <OIcon
        collection="heroicons"
        name="rectangle-group"
        size="8"
        class="mx-auto text-gray-400 dark:text-gray-600" />
      <h3 class="mt-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.billing.diff.notFound') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.billing.diff.notFoundDescription', { planid: props.planid }) }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="goBack">
        {{ t('web.admin.billing.diff.backToCatalog') }}
      </button>
    </div>

    <!-- Load error (network/HTTP, or contract mismatch) -->
    <div
      v-else-if="loadFailed || notFound"
      class="rounded-lg border border-red-200 bg-red-50 px-6 py-16 text-center dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="detail-error">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="8"
        class="mx-auto text-red-500 dark:text-red-400" />
      <p class="mt-3 text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.billing.loadError') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="load().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.billing.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else-if="details"
      class="space-y-6"
      data-testid="detail-content">
      <!-- Header -->
      <header class="border-b-2 border-gray-900 pb-4 dark:border-gray-100">
        <div class="flex flex-wrap items-center gap-3">
          <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
            {{ planName ?? props.planid }}
          </h2>
          <span
            v-if="status"
            class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
            :class="statusBadgeClass(status)"
            data-testid="plan-diff-status">
            {{ t(`web.admin.billing.status.${status}`) }}
          </span>
          <span
            class="font-mono text-xs text-gray-400 tabular-nums dark:text-gray-500"
            data-testid="plan-diff-planid">
            {{ props.planid }}
          </span>
        </div>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.billing.diff.subtitle') }}
        </p>
      </header>

      <!-- local_config warning: drift cannot be evaluated without Stripe. -->
      <div
        v-if="isLocalConfig"
        class="flex items-start gap-2 rounded-md border border-yellow-200 bg-yellow-50 px-4 py-3 dark:border-yellow-900/50 dark:bg-yellow-900/20"
        role="status"
        data-testid="plan-diff-local-config-warning">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="5"
          class="mt-0.5 shrink-0 text-yellow-600 dark:text-yellow-400" />
        <span class="text-sm text-yellow-800 dark:text-yellow-200">
          {{ t('web.admin.billing.localConfigWarning') }}
        </span>
      </div>

      <!-- Which fields drift, per the server's drift summary. -->
      <div
        v-if="changedFields.length"
        class="flex flex-wrap items-center gap-2 rounded-md border border-yellow-200 bg-yellow-50 px-4 py-3 dark:border-yellow-900/50 dark:bg-yellow-900/20"
        data-testid="plan-diff-fields">
        <span class="text-sm font-medium text-yellow-800 dark:text-yellow-200">
          {{ t('web.admin.billing.diff.driftedFields') }}
        </span>
        <span
          v-for="field in changedFields"
          :key="field"
          class="rounded bg-yellow-100 px-2 py-0.5 font-mono text-xs text-yellow-900 dark:bg-yellow-900/40 dark:text-yellow-100">
          {{ field }}
        </span>
      </div>

      <!-- Side-by-side config vs live, full page width. -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.billing.diff.config') }}
            </h3>
          </div>
          <div class="p-4">
            <JsonViewer
              v-if="configPlan"
              :data="configPlan"
              :expand-depth="2"
              testid="billing-diff-config-json" />
            <p
              v-else
              class="rounded-lg border border-dashed border-gray-300 px-3 py-8 text-center text-sm text-gray-500 dark:border-gray-700 dark:text-gray-400"
              data-testid="billing-diff-config-absent">
              {{ t('web.admin.billing.diff.absentConfig') }}
            </p>
          </div>
        </section>

        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.billing.diff.live') }}
            </h3>
          </div>
          <div class="p-4">
            <JsonViewer
              v-if="livePlan"
              :data="livePlan"
              :expand-depth="2"
              testid="billing-diff-live-json" />
            <p
              v-else
              class="rounded-lg border border-dashed border-gray-300 px-3 py-8 text-center text-sm text-gray-500 dark:border-gray-700 dark:text-gray-400"
              data-testid="billing-diff-live-absent">
              {{ t('web.admin.billing.diff.absentLive') }}
            </p>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
