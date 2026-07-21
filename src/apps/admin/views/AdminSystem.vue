<!-- src/apps/admin/views/AdminSystem.vue -->

<script setup lang="ts">

  import { DataTable, JsonViewer, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { QueueMetric } from '@/schemas/api/internal/responses/colonel';
  import {
    brandDiagnosticsResponseSchema,
    databaseMetricsResponseSchema,
    queueMetricsResponseSchema,
    redisMetricsResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-system';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * System screen (ticket #33) — the read-only status/info read-out, a Phase-2
   * parity port of the legacy `ColonelSystem` / `ColonelSystemMainDB` /
   * `ColonelSystemRedis` views rebuilt fresh on the Slice-3 template. It does NOT
   * import `src/apps/colonel/*` or `colonelInfoStore`.
   *
   * Four independent single-GET read-outs via {@link useResourceFetch} (CONTRACT
   * 1 — single screens use useResourceFetch, not a paginated store). All reads
   * REUSE the frozen wrapped schemas (CONTRACT 3):
   *   - GET /api/colonel/system/database → server + memory + db sizes + model counts
   *   - GET /api/colonel/queue           → connection + worker health + per-queue
   *   - GET /api/colonel/system/redis    → full Redis/Valkey INFO (JsonViewer)
   *   - GET /api/colonel/system/brand    → brand-pack resolution diagnostic (#3822)
   *
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4).
   */
  const { t } = useI18n();

  // ---- Database metrics -----------------------------------------------------

  const {
    data: dbData,
    loading: dbLoading,
    error: dbError,
    validationError: dbValidationError,
    load: loadDb,
  } = useResourceFetch({
    url: '/api/colonel/system/database',
    schema: databaseMetricsResponseSchema,
    context: 'DatabaseMetricsResponse',
  });

  const db = computed(() => dbData.value?.details ?? null);
  const dbFailed = computed(() => dbError.value !== null || dbValidationError.value !== null);

  // Valkey reports both valkey_version and a Redis-compat redis_version. Prefer
  // Valkey when present so the page reflects the real engine (parity with the
  // legacy MainDB view).
  const engineName = computed(() =>
    db.value?.redis_info.valkey_version ? 'Valkey' : 'Redis'
  );
  const engineVersion = computed(
    () => db.value?.redis_info.valkey_version ?? db.value?.redis_info.redis_version ?? '—'
  );

  const num = (value: number | undefined | null): string =>
    typeof value === 'number' ? value.toLocaleString() : '—';

  /** Database-size rows, normalised from the record<string, {keys,…} | string>. */
  const databaseSizeRows = computed(() => {
    const sizes = db.value?.database_sizes ?? {};
    return Object.entries(sizes).map(([name, info]) => {
      if (info !== null && typeof info === 'object' && 'keys' in info) {
        return {
          name,
          keys: info.keys as number,
          expires: info.expires as number,
          raw: null as string | null,
        };
      }
      return { name, keys: null, expires: null, raw: String(info) };
    });
  });

  // ---- Queue metrics --------------------------------------------------------

  const {
    data: queueData,
    loading: queueLoading,
    error: queueError,
    validationError: queueValidationError,
    load: loadQueue,
  } = useResourceFetch({
    url: '/api/colonel/queue',
    schema: queueMetricsResponseSchema,
    context: 'QueueMetricsResponse',
  });

  const queue = computed(() => queueData.value?.details ?? null);
  const queueFailed = computed(
    () => queueError.value !== null || queueValidationError.value !== null
  );

  const queueColumns = computed<DataTableColumn<QueueMetric>[]>(() => [
    { key: 'name', label: t('web.admin.system.queue.columns.name') },
    { key: 'pending_messages', label: t('web.admin.system.queue.columns.pending'), align: 'right' },
    { key: 'consumers', label: t('web.admin.system.queue.columns.consumers'), align: 'right' },
  ]);

  /** Worker-health badge classes, keyed by the backend health enum. */
  function healthBadgeClass(status: string): string {
    switch (status) {
      case 'healthy':
        return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
      case 'degraded':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200';
      case 'unhealthy':
        return 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
    }
  }

  // ---- Redis full INFO ------------------------------------------------------

  const {
    data: redisData,
    loading: redisLoading,
    error: redisError,
    validationError: redisValidationError,
    load: loadRedis,
  } = useResourceFetch({
    url: '/api/colonel/system/redis',
    schema: redisMetricsResponseSchema,
    context: 'RedisMetricsResponse',
  });

  const redis = computed(() => redisData.value?.details ?? null);
  const redisFailed = computed(
    () => redisError.value !== null || redisValidationError.value !== null
  );

  // ---- Brand-pack diagnostics (#3822) ---------------------------------------

  const {
    data: brandData,
    loading: brandLoading,
    error: brandError,
    validationError: brandValidationError,
    load: loadBrand,
  } = useResourceFetch({
    url: '/api/colonel/system/brand',
    schema: brandDiagnosticsResponseSchema,
    context: 'BrandDiagnosticsResponse',
  });

  const brand = computed(() => brandData.value?.details ?? null);
  const brandFailed = computed(
    () => brandError.value !== null || brandValidationError.value !== null
  );

  /** One probed brand search root (the `roots[]` element shape). */
  interface BrandRoot {
    path: string;
    exists: boolean;
  }

  const brandRootColumns = computed<DataTableColumn<BrandRoot>[]>(() => [
    { key: 'path', label: t('web.admin.system.brand.roots.columns.path') },
    { key: 'exists', label: t('web.admin.system.brand.roots.columns.exists'), align: 'right' },
  ]);

  /**
   * Danger-flag badge classes for the two boolean tripwires. Polarity is
   * inverted vs a health enum: `false` is the healthy state (green), `true`
   * means the tripwire fired (red) — these are the fields the tool exists to
   * surface, so a tripped flag reads loud.
   */
  function dangerBadgeClass(tripped: boolean): string {
    return tripped
      ? 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200'
      : 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
  }

  /**
   * On-disk existence badge for a search root / manifest. Normal polarity here:
   * present = green, missing = red (the inverse of {@link dangerBadgeClass}).
   */
  function existsBadgeClass(exists: boolean): string {
    return exists
      ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200'
      : 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200';
  }

  function loadAll(): void {
    loadDb().catch(() => {});
    loadQueue().catch(() => {});
    loadRedis().catch(() => {});
    loadBrand().catch(() => {});
  }

  onMounted(loadAll);
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.system.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.system.description') }}
      </p>
    </header>

    <!-- ================= Database metrics ================= -->
    <section
      class="mb-8"
      data-testid="system-database">
      <h3 class="mb-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.system.database.title', { engine: engineName }) }}
      </h3>

      <!-- Loading -->
      <div
        v-if="dbLoading && !db"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
        data-testid="system-database-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>

      <!-- Error -->
      <div
        v-else-if="dbFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="system-database-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.system.database.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadDb().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.system.retry') }}
        </button>
      </div>

      <!-- Loaded -->
      <div
        v-else-if="db"
        class="space-y-4">
        <!-- Model counts + server tiles -->
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          <StatCard
            :label="t('web.admin.system.database.stats.customers')"
            :value="num(db.model_counts.customers)"
            icon="users"
            testid="stat-customers" />
          <StatCard
            :label="t('web.admin.system.database.stats.secrets')"
            :value="num(db.model_counts.secrets)"
            icon="key"
            testid="stat-secrets" />
          <StatCard
            :label="t('web.admin.system.database.stats.receipts')"
            :value="num(db.model_counts.receipts)"
            icon="receipt-percent"
            testid="stat-receipts" />
          <StatCard
            :label="t('web.admin.system.database.stats.totalKeys')"
            :value="num(db.total_keys)"
            icon="circle-stack"
            testid="stat-total-keys" />
        </div>

        <!-- Server info -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.database.server') }}
          </h4>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3">
            <div data-testid="server-version">
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.version') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ engineVersion }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.mode') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ db.redis_info.redis_mode ?? '—' }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.uptimeDays') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ num(db.redis_info.uptime_in_days) }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.connectedClients') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ num(db.redis_info.connected_clients) }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.opsPerSec') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ num(db.redis_info.instantaneous_ops_per_sec) }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.totalCommands') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ num(db.redis_info.total_commands_processed) }}
              </dd>
            </div>
          </dl>
        </div>

        <!-- Memory -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.database.memory') }}
          </h4>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-4">
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.usedMemory') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ db.memory_stats.used_memory_human }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.rssMemory') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ db.memory_stats.used_memory_rss_human }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.peakMemory') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ db.memory_stats.used_memory_peak_human }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.database.fields.fragmentation') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">
                {{ db.memory_stats.mem_fragmentation_ratio.toFixed(2) }}
              </dd>
            </div>
          </dl>
        </div>

        <!-- Database sizes -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="system-database-sizes">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.database.databases') }}
          </h4>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <div
              v-for="row in databaseSizeRows"
              :key="row.name"
              class="rounded border border-gray-200 p-3 dark:border-gray-700">
              <div class="font-mono text-sm font-semibold text-gray-900 dark:text-white">
                {{ row.name }}
              </div>
              <div class="mt-1 text-xs text-gray-600 dark:text-gray-400">
                <template v-if="row.raw === null">
                  {{ t('web.admin.system.database.dbSummary', { keys: num(row.keys), expires: num(row.expires) }) }}
                </template>
                <template v-else>
                  {{ row.raw }}
                </template>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- ================= Queue status ================= -->
    <section
      class="mb-8"
      data-testid="system-queue">
      <h3 class="mb-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.system.queue.title') }}
      </h3>

      <div
        v-if="queueLoading && !queue"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
        data-testid="system-queue-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>

      <div
        v-else-if="queueFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="system-queue-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.system.queue.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadQueue().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.system.retry') }}
        </button>
      </div>

      <div
        v-else-if="queue"
        class="space-y-4">
        <!-- Connection + health summary -->
        <div class="flex flex-wrap items-center gap-3">
          <span
            class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
            :class="queue.connection.connected
              ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200'
              : 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200'"
            data-testid="queue-connection">
            <OIcon
              collection="heroicons"
              :name="queue.connection.connected ? 'check-circle' : 'x-circle'"
              size="3" />
            {{ queue.connection.connected
              ? t('web.admin.system.queue.connected')
              : t('web.admin.system.queue.disconnected') }}
          </span>
          <span
            v-if="queue.connection.host"
            class="font-mono text-xs text-gray-500 dark:text-gray-400">
            {{ queue.connection.host }}
          </span>
          <span
            class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
            :class="healthBadgeClass(queue.worker_health.status)"
            data-testid="queue-health">
            {{ t(`web.admin.system.queue.health.${queue.worker_health.status}`, queue.worker_health.status) }}
          </span>
          <span
            v-if="queue.worker_health.active_workers !== undefined"
            class="text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.admin.system.queue.activeWorkers', { count: queue.worker_health.active_workers }) }}
          </span>
        </div>

        <!-- Per-queue table -->
        <div
          class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <DataTable
            :columns="queueColumns"
            :rows="queue.queues"
            row-key="name"
            :empty-text="t('web.admin.system.queue.empty')"
            testid="queue-table">
            <template #cell-name="{ row }">
              <span class="font-mono text-gray-900 dark:text-white">{{ row.name }}</span>
            </template>
            <template #cell-pending_messages="{ row }">
              {{ num(row.pending_messages) }}
            </template>
            <template #cell-consumers="{ row }">
              {{ num(row.consumers) }}
            </template>
          </DataTable>
        </div>
      </div>
    </section>

    <!-- ================= Redis / Valkey full INFO ================= -->
    <section data-testid="system-redis">
      <h3 class="mb-1 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.system.redis.title') }}
      </h3>
      <p
        v-if="redis"
        class="mb-3 text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.admin.system.redis.captured', { at: formatDisplayDateTime(redis.timestamp) }) }}
      </p>

      <div
        v-if="redisLoading && !redis"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
        data-testid="system-redis-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>

      <div
        v-else-if="redisFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="system-redis-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.system.redis.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadRedis().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.system.retry') }}
        </button>
      </div>

      <div
        v-else-if="redis"
        class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <JsonViewer
          :data="redis.redis_info"
          :expand-depth="1"
          testid="system-redis-json" />
      </div>
    </section>

    <!-- ================= Brand-pack diagnostics (#3822) ================= -->
    <section
      class="mt-8"
      data-testid="system-brand">
      <h3 class="mb-1 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.system.brand.title') }}
      </h3>
      <p class="mb-3 text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.admin.system.brand.description') }}
      </p>

      <!-- Loading -->
      <div
        v-if="brandLoading && !brand"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
        data-testid="system-brand-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>

      <!-- Error -->
      <div
        v-else-if="brandFailed"
        class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
        role="alert"
        data-testid="system-brand-error">
        <span class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.system.brand.loadError') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadBrand().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.system.retry') }}
        </button>
      </div>

      <!-- Loaded -->
      <div
        v-else-if="brand"
        class="space-y-4"
        data-testid="system-brand-loaded">
        <!-- Danger flags — the reason this tool exists, so they read first. -->
        <div
          class="flex flex-wrap items-center gap-3"
          data-testid="brand-flags">
          <span
            class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
            :class="dangerBadgeClass(brand.fell_back_to_default)"
            data-testid="brand-fallback-badge">
            <OIcon
              collection="heroicons"
              :name="brand.fell_back_to_default ? 'exclamation-triangle' : 'check-circle'"
              size="3" />
            {{ brand.fell_back_to_default
              ? t('web.admin.system.brand.flags.fellBack.danger')
              : t('web.admin.system.brand.flags.fellBack.ok') }}
          </span>
          <span
            class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
            :class="dangerBadgeClass(brand.boot_vs_live_mismatch)"
            data-testid="brand-mismatch-badge">
            <OIcon
              collection="heroicons"
              :name="brand.boot_vs_live_mismatch ? 'exclamation-triangle' : 'check-circle'"
              size="3" />
            {{ brand.boot_vs_live_mismatch
              ? t('web.admin.system.brand.flags.mismatch.danger')
              : t('web.admin.system.brand.flags.mismatch.ok') }}
          </span>
        </div>

        <!-- Headline tiles -->
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3">
          <StatCard
            :label="t('web.admin.system.brand.stats.brandPack')"
            :value="brand.config.brand_pack ?? t('web.admin.system.brand.none')"
            icon="archive-box"
            testid="brand-stat-pack" />
          <StatCard
            :label="t('web.admin.system.brand.stats.overlayAssets')"
            :value="num(brand.overlay_assets.length)"
            icon="rectangle-group"
            testid="brand-stat-overlays" />
          <StatCard
            :label="t('web.admin.system.brand.stats.manifestKeys')"
            :value="num(brand.manifest.keys_on_disk.length)"
            icon="key"
            testid="brand-stat-keys" />
        </div>

        <!-- Resolution -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="brand-resolution">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.brand.resolution') }}
          </h4>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div data-testid="brand-resolved-dir">
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.resolvedDir') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.resolved_dir ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.home') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.home }}
              </dd>
            </div>
          </dl>
        </div>

        <!-- Environment vs Config (the divergence catcher) -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="brand-env-config">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.brand.envVsConfig') }}
          </h4>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div data-testid="brand-env-pack">
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.envPack') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.env.brand_pack ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
            <div data-testid="brand-config-pack">
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.configPack') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.config.brand_pack ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.envAssetsDir') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.env.brand_assets_dir ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.fields.configAssetsDir') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.config.brand_assets_dir ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
          </dl>
        </div>

        <!-- Search roots -->
        <div
          class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="brand-roots">
          <h4 class="border-b border-gray-100 px-5 py-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:border-gray-800 dark:text-gray-400">
            {{ t('web.admin.system.brand.roots.title') }}
          </h4>
          <DataTable
            :columns="brandRootColumns"
            :rows="brand.roots"
            row-key="path"
            :empty-text="t('web.admin.system.brand.roots.empty')"
            testid="brand-roots-table">
            <template #cell-path="{ row }">
              <span class="font-mono text-gray-900 dark:text-white">{{ row.path }}</span>
            </template>
            <template #cell-exists="{ row }">
              <span
                class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
                :class="existsBadgeClass(row.exists)">
                <OIcon
                  collection="heroicons"
                  :name="row.exists ? 'check-circle' : 'x-circle'"
                  size="3" />
                {{ row.exists
                  ? t('web.admin.system.brand.exists.yes')
                  : t('web.admin.system.brand.exists.no') }}
              </span>
            </template>
          </DataTable>
        </div>

        <!-- Manifest -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="brand-manifest">
          <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.system.brand.manifest.title') }}
          </h4>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div class="sm:col-span-2">
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.manifest.path') }}
              </dt>
              <dd class="mt-0.5 font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ brand.manifest.path ?? t('web.admin.system.brand.none') }}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.admin.system.brand.manifest.exists') }}
              </dt>
              <dd class="mt-1">
                <span
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
                  :class="existsBadgeClass(brand.manifest.exists)"
                  data-testid="brand-manifest-exists">
                  <OIcon
                    collection="heroicons"
                    :name="brand.manifest.exists ? 'check-circle' : 'x-circle'"
                    size="3" />
                  {{ brand.manifest.exists
                    ? t('web.admin.system.brand.exists.yes')
                    : t('web.admin.system.brand.exists.no') }}
                </span>
              </dd>
            </div>
          </dl>
          <div class="mt-4">
            <p class="mb-1.5 text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.system.brand.manifest.keysOnDisk') }}
            </p>
            <div
              v-if="brand.manifest.keys_on_disk.length"
              class="flex flex-wrap gap-1.5"
              data-testid="brand-manifest-keys">
              <span
                v-for="key in brand.manifest.keys_on_disk"
                :key="key"
                class="inline-flex rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                {{ key }}
              </span>
            </div>
            <p
              v-else
              class="text-xs text-gray-400 dark:text-gray-500">
              {{ t('web.admin.system.brand.none') }}
            </p>
          </div>
        </div>

        <!-- Absorbed keys + overlay assets -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div
            class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
            data-testid="brand-absorbed">
            <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.system.brand.absorbed') }}
            </h4>
            <div
              v-if="brand.config.brand_absorbed.length"
              class="flex flex-wrap gap-1.5">
              <span
                v-for="entry in brand.config.brand_absorbed"
                :key="entry"
                class="inline-flex rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                {{ entry }}
              </span>
            </div>
            <p
              v-else
              class="text-xs text-gray-400 dark:text-gray-500">
              {{ t('web.admin.system.brand.none') }}
            </p>

            <h4
              class="mt-4 mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.system.brand.operatorKeys') }}
            </h4>
            <div
              v-if="brand.config.brand_operator_keys.length"
              class="flex flex-wrap gap-1.5"
              data-testid="brand-operator-keys">
              <span
                v-for="entry in brand.config.brand_operator_keys"
                :key="entry"
                class="inline-flex rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                {{ entry }}
              </span>
            </div>
            <p
              v-else
              class="text-xs text-gray-400 dark:text-gray-500">
              {{ t('web.admin.system.brand.none') }}
            </p>
          </div>

          <div
            class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
            data-testid="brand-overlay-assets">
            <h4 class="mb-3 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.system.brand.overlayAssets') }}
            </h4>
            <div
              v-if="brand.overlay_assets.length"
              class="flex flex-wrap gap-1.5">
              <span
                v-for="asset in brand.overlay_assets"
                :key="asset"
                class="inline-flex rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                {{ asset }}
              </span>
            </div>
            <p
              v-else
              class="text-xs text-gray-400 dark:text-gray-500">
              {{ t('web.admin.system.brand.none') }}
            </p>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
