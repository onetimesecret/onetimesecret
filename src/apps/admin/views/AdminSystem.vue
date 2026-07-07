<!-- src/apps/admin/views/AdminSystem.vue -->

<script setup lang="ts">
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { DataTable, JsonViewer, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { QueueMetric } from '@/schemas/api/account/responses/colonel';
  import {
    databaseMetricsResponseSchema,
    queueMetricsResponseSchema,
    redisMetricsResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-system';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';

  /**
   * System screen (ticket #33) — the read-only status/info read-out, a Phase-2
   * parity port of the legacy `ColonelSystem` / `ColonelSystemMainDB` /
   * `ColonelSystemRedis` views rebuilt fresh on the Slice-3 template. It does NOT
   * import `src/apps/colonel/*` or `colonelInfoStore`.
   *
   * Three independent single-GET read-outs via {@link useResourceFetch} (CONTRACT
   * 1 — single screens use useResourceFetch, not a paginated store). All reads
   * REUSE the frozen wrapped schemas (CONTRACT 3):
   *   - GET /api/colonel/system/database → server + memory + db sizes + model counts
   *   - GET /api/colonel/queue           → connection + worker health + per-queue
   *   - GET /api/colonel/system/redis    → full Redis/Valkey INFO (JsonViewer)
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

  function loadAll(): void {
    loadDb().catch(() => {});
    loadQueue().catch(() => {});
    loadRedis().catch(() => {});
  }

  onMounted(loadAll);
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.system.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.system.description') }}
      </p>
    </div>

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
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
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
          <h4 class="mb-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.system.database.server') }}
          </h4>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3">
            <div data-testid="server-version">
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.version') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ engineVersion }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.mode') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ db.redis_info.redis_mode ?? '—' }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.uptimeDays') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ num(db.redis_info.uptime_in_days) }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.connectedClients') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ num(db.redis_info.connected_clients) }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.opsPerSec') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ num(db.redis_info.instantaneous_ops_per_sec) }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.totalCommands') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ num(db.redis_info.total_commands_processed) }}</dd>
            </div>
          </dl>
        </div>

        <!-- Memory -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <h4 class="mb-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.system.database.memory') }}
          </h4>
          <dl class="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-4">
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.usedMemory') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ db.memory_stats.used_memory_human }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.rssMemory') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ db.memory_stats.used_memory_rss_human }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.peakMemory') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ db.memory_stats.used_memory_peak_human }}</dd>
            </div>
            <div>
              <dt class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.admin.system.database.fields.fragmentation') }}</dt>
              <dd class="mt-0.5 font-mono text-sm text-gray-900 dark:text-white">{{ db.memory_stats.mem_fragmentation_ratio.toFixed(2) }}</dd>
            </div>
          </dl>
        </div>

        <!-- Database sizes -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="system-database-sizes">
          <h4 class="mb-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.system.database.databases') }}
          </h4>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <div
              v-for="row in databaseSizeRows"
              :key="row.name"
              class="rounded border border-gray-200 p-3 dark:border-gray-700">
              <div class="font-mono text-sm font-semibold text-gray-900 dark:text-white">{{ row.name }}</div>
              <div class="mt-1 text-xs text-gray-600 dark:text-gray-400">
                <template v-if="row.raw === null">
                  {{ t('web.admin.system.database.dbSummary', { keys: num(row.keys), expires: num(row.expires) }) }}
                </template>
                <template v-else>{{ row.raw }}</template>
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
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
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
          class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
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
  </div>
</template>
