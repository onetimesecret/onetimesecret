<!-- src/apps/admin/views/AdminOverview.vue -->

<script setup lang="ts">
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  import TrendSparkline from '@/apps/admin/components/TrendSparkline.vue';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { ColonelTrendPoint } from '@/schemas/api/internal/responses/colonel-trends';
  import {
    colonelInfoResponseSchema,
    colonelStatsResponseSchema,
  } from '@/schemas/api/internal/responses/colonel';
  import { colonelTrendsResponseSchema } from '@/schemas/api/internal/responses/colonel-trends';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';

  /**
   * Overview dashboard (observability lane) — the landing screen is now a real
   * dashboard, replacing the Phase-0 launcher that only mirrored the sidebar.
   *
   * Three INDEPENDENT read-outs fetched in PARALLEL via {@link useResourceFetch}
   * (the AdminSystem multi-fetch pattern — skeleton states per section, no
   * blocking spinner wall, each section degrades + retries on its own):
   *
   *   - GET /api/colonel/stats  → stat tiles (real counts incl. session_count)
   *   - GET /api/colonel/trends → 30-day signups / secrets-created sparklines
   *   - GET /api/colonel/info   → user feedback (today / yesterday / older),
   *     the V1 FeedbackSection parity lost in the cutover
   *
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
   */
  const { t } = useI18n();

  // ---- Stats (stat tiles) -----------------------------------------------------

  const {
    data: statsData,
    loading: statsLoading,
    error: statsError,
    validationError: statsValidationError,
    load: loadStats,
  } = useResourceFetch({
    url: '/api/colonel/stats',
    schema: colonelStatsResponseSchema,
    context: 'ColonelStatsResponse',
  });

  const counts = computed(() => statsData.value?.details?.counts ?? null);
  const statsFailed = computed(
    () => statsError.value !== null || statsValidationError.value !== null
  );

  const num = (value: number | undefined | null): string =>
    typeof value === 'number' ? value.toLocaleString() : '—';

  /** The six headline tiles; each links into its console section. */
  const statTiles = computed(() => [
    {
      key: 'customers',
      label: t('web.admin.overview.stats.customers'),
      value: num(counts.value?.customer_count),
      icon: 'users',
      to: '/colonel/customers',
    },
    {
      key: 'secrets',
      label: t('web.admin.overview.stats.secrets'),
      value: num(counts.value?.secret_count),
      icon: 'key',
      to: '/colonel/secrets',
    },
    {
      key: 'sessions',
      label: t('web.admin.overview.stats.sessions'),
      value: num(counts.value?.session_count),
      icon: 'finger-print',
      to: '/colonel/sessions',
    },
    {
      key: 'receipts',
      label: t('web.admin.overview.stats.receipts'),
      value: num(counts.value?.receipt_count),
      icon: 'rectangle-stack',
      to: undefined,
    },
    {
      key: 'secretsCreated',
      label: t('web.admin.overview.stats.secretsCreated'),
      value: num(counts.value?.secrets_created),
      icon: 'arrow-trending-up',
      to: undefined,
    },
    {
      key: 'emailsSent',
      label: t('web.admin.overview.stats.emailsSent'),
      value: num(counts.value?.emails_sent),
      icon: 'envelope',
      to: '/colonel/email-tools',
    },
  ]);

  // ---- Trends (sparklines) ------------------------------------------------------

  const {
    data: trendsData,
    loading: trendsLoading,
    error: trendsError,
    validationError: trendsValidationError,
    load: loadTrends,
  } = useResourceFetch({
    url: '/api/colonel/trends',
    schema: colonelTrendsResponseSchema,
    context: 'ColonelTrendsResponse',
  });

  const trendsFailed = computed(
    () => trendsError.value !== null || trendsValidationError.value !== null
  );

  const latest = (points: ColonelTrendPoint[]): number =>
    points.length > 0 ? points[points.length - 1].count : 0;

  const trendCards = computed(() => {
    const series = trendsData.value?.details?.series;
    if (!series) return [];
    return [
      {
        key: 'signups',
        label: t('web.admin.overview.trends.signups'),
        points: series.signups,
        today: latest(series.signups),
      },
      {
        key: 'secretsCreated',
        label: t('web.admin.overview.trends.secretsCreated'),
        points: series.secrets_created,
        today: latest(series.secrets_created),
      },
    ];
  });

  // ---- Feedback (V1 parity) -----------------------------------------------------

  const {
    data: infoData,
    loading: infoLoading,
    error: infoError,
    validationError: infoValidationError,
    load: loadInfo,
  } = useResourceFetch({
    url: '/api/colonel/info',
    schema: colonelInfoResponseSchema,
    context: 'ColonelInfoResponse',
  });

  const infoFailed = computed(
    () => infoError.value !== null || infoValidationError.value !== null
  );

  const feedbackGroups = computed(() => {
    const details = infoData.value?.details;
    if (!details) return [];
    return [
      {
        key: 'today',
        label: t('web.admin.overview.feedback.today'),
        items: details.today_feedback,
      },
      {
        key: 'yesterday',
        label: t('web.admin.overview.feedback.yesterday'),
        items: details.yesterday_feedback,
      },
      {
        key: 'older',
        label: t('web.admin.overview.feedback.older'),
        items: details.older_feedback ?? [],
      },
    ];
  });

  const feedbackTotal = computed(
    () => infoData.value?.details?.counts?.feedback_count ?? null
  );

  // ---- Parallel load ------------------------------------------------------------

  /** Kick off all three reads at once; each section handles its own failure. */
  function loadAll(): void {
    loadStats().catch(() => {});
    loadTrends().catch(() => {});
    loadInfo().catch(() => {});
  }

  onMounted(loadAll);
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <div class="mb-6 flex items-center gap-3">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.colonel.titles.index') }}
      </h2>
    </div>

    <!-- ==== Stat tiles ==================================================== -->
    <section
      :aria-label="t('web.admin.overview.stats.heading')"
      class="mb-8">
      <div
        v-if="statsFailed"
        class="mb-4 flex items-center justify-between gap-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-800 dark:bg-gray-800/50"
        role="alert"
        data-testid="overview-stats-error">
        <span class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.admin.overview.stats.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
          @click="loadStats().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.overview.retry') }}
        </button>
      </div>

      <!-- One dense readout strip rather than six hero cards: an operator scans
           these counts, they aren't a billboard. Hairline separators come from a
           gap-px grid over a tinted background (wrap-safe, unlike divide-x). -->
      <div
        v-else
        class="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-gray-200 bg-gray-200 shadow-sm sm:grid-cols-3 lg:grid-cols-6 dark:border-gray-800 dark:bg-gray-800"
        data-testid="overview-stats">
        <component
          :is="tile.to ? 'router-link' : 'div'"
          v-for="tile in statTiles"
          :key="tile.key"
          :to="tile.to"
          :data-testid="`overview-stat-${tile.key}`"
          class="flex flex-col gap-1 bg-white p-4 transition-colors dark:bg-gray-900"
          :class="
            tile.to
              ? 'hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500 dark:hover:bg-gray-800/60'
              : ''
          ">
          <span
            class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-gray-500 dark:text-gray-400">
            <OIcon
              collection="heroicons"
              :name="tile.icon"
              size="4"
              class="shrink-0 text-gray-400 dark:text-gray-500" />
            <span class="truncate">{{ tile.label }}</span>
          </span>
          <Skeleton
            v-if="statsLoading"
            height="h-8"
            width="w-12"
            :pulse="true" />
          <span
            v-else
            class="text-2xl font-semibold tabular-nums text-gray-900 dark:text-white">
            {{ tile.value }}
          </span>
        </component>
      </div>
    </section>

    <!-- ==== Trends (30-day sparklines) ==================================== -->
    <section
      :aria-label="t('web.admin.overview.trends.title')"
      class="mb-8">
      <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.admin.overview.trends.title') }}
        </h3>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.admin.overview.trends.collectingNote') }}
        </p>
      </div>

      <div
        v-if="trendsFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-800 dark:bg-gray-800/50"
        role="alert"
        data-testid="overview-trends-error">
        <span class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.admin.overview.trends.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
          @click="loadTrends().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.overview.retry') }}
        </button>
      </div>

      <div
        v-else-if="trendsLoading"
        class="grid grid-cols-1 gap-4 sm:grid-cols-2"
        data-testid="overview-trends-loading">
        <div
          v-for="key in ['signups', 'secretsCreated']"
          :key="key"
          class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-800">
          <Skeleton
            height="h-5"
            width="w-32"
            :pulse="true" />
          <Skeleton
            class="mt-3"
            height="h-14"
            width="w-full"
            :pulse="true" />
        </div>
      </div>

      <div
        v-else
        class="grid grid-cols-1 gap-4 sm:grid-cols-2"
        data-testid="overview-trends">
        <div
          v-for="card in trendCards"
          :key="card.key"
          class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-800"
          :data-testid="`overview-trend-${card.key}`">
          <div class="flex items-baseline justify-between gap-2">
            <p class="truncate text-sm font-medium text-gray-500 dark:text-gray-400">
              {{ card.label }}
            </p>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              <span class="text-xl font-semibold text-gray-900 dark:text-white">{{
                card.today.toLocaleString()
              }}</span>
              {{ t('web.admin.overview.trends.today') }}
            </p>
          </div>
          <div class="mt-3 text-brand-600 dark:text-brand-400">
            <TrendSparkline
              :points="card.points"
              :label="
                t('web.admin.overview.trends.sparklineAria', {
                  label: card.label,
                  count: card.today,
                })
              "
              :testid="`overview-sparkline-${card.key}`" />
          </div>
        </div>
      </div>
    </section>

    <!-- ==== Feedback (V1 parity) ========================================== -->
    <section :aria-label="t('web.admin.overview.feedback.title')">
      <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.admin.overview.feedback.title') }}
        </h3>
        <p
          v-if="feedbackTotal !== null"
          class="text-xs text-gray-500 dark:text-gray-400"
          data-testid="overview-feedback-total">
          {{ t('web.admin.overview.feedback.total', { count: feedbackTotal }) }}
        </p>
      </div>

      <div
        v-if="infoFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-800 dark:bg-gray-800/50"
        role="alert"
        data-testid="overview-feedback-error">
        <span class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.admin.overview.feedback.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
          @click="loadInfo().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.overview.retry') }}
        </button>
      </div>

      <div
        v-else-if="infoLoading"
        class="grid grid-cols-1 gap-4 lg:grid-cols-3"
        data-testid="overview-feedback-loading">
        <div
          v-for="key in ['today', 'yesterday', 'older']"
          :key="key"
          class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-800">
          <Skeleton
            height="h-5"
            width="w-24"
            :pulse="true" />
          <Skeleton
            class="mt-3"
            height="h-4"
            width="w-full"
            :pulse="true" />
          <Skeleton
            class="mt-2"
            height="h-4"
            width="w-3/4"
            :pulse="true" />
        </div>
      </div>

      <div
        v-else
        class="grid grid-cols-1 gap-4 lg:grid-cols-3"
        data-testid="overview-feedback">
        <div
          v-for="group in feedbackGroups"
          :key="group.key"
          class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-800"
          :data-testid="`overview-feedback-${group.key}`">
          <h4
            class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ group.label }}
            <span class="ml-1 font-normal normal-case">({{ group.items.length }})</span>
          </h4>

          <p
            v-if="group.items.length === 0"
            class="py-4 text-sm text-gray-400 dark:text-gray-500">
            {{ t('web.admin.overview.feedback.empty') }}
          </p>

          <ul
            v-else
            class="max-h-72 space-y-3 overflow-y-auto">
            <li
              v-for="(item, index) in group.items"
              :key="`${group.key}-${index}`"
              class="border-b border-gray-100 pb-2 last:border-b-0 last:pb-0 dark:border-gray-700">
              <p class="break-words text-sm text-gray-900 dark:text-gray-100">{{ item.msg }}</p>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                {{ formatDisplayDateTime(item.stamp) }}
              </p>
            </li>
          </ul>
        </div>
      </div>
    </section>
  </div>
</template>
