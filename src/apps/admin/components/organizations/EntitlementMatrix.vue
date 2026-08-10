<!-- src/apps/admin/components/organizations/EntitlementMatrix.vue -->

<script setup lang="ts">
  import type { ColonelOrganizationDetailEntitlements } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The entitlement resolution matrix — one row per entitlement name, one
   * column per source set, so an operator debugging "why can't this org do X"
   * reads the whole causal chain in a single horizontal scan:
   *
   *   in plan? + granted? − revoked? = expected ... and is it materialized?
   *
   * Four parallel chip lists (what this replaces) could show the four sets but
   * never the JOIN between them: with 20+ entitlements you cannot see that
   * `custom_domains` is missing *because* of an admin revoke without diffing
   * lists by eye. Rows carry the verdict explicitly in a State column, and the
   * two failure modes are highlighted:
   *
   * - orphaned (`drift.extra`)  — materialized but NOT expected; left behind
   *   when a revoke was never re-materialized. Reconcile removes it.
   * - missing (`drift.missing`) — expected but NOT materialized; this is the
   *   permission the user is actually missing right now.
   *
   * Presentational only: it renders what the detail GET already returned and
   * mutates nothing.
   */
  const props = defineProps<{
    /** The entitlement block from `GET /api/colonel/organizations/:id`. */
    entitlements: ColonelOrganizationDetailEntitlements;
  }>();

  const { t } = useI18n();

  /** Per-row verdict, in priority order (drift outranks its cause). */
  type MatrixState = 'orphaned' | 'missing' | 'revoked' | 'granted' | 'plan';

  interface MatrixRow {
    name: string;
    inPlan: boolean;
    granted: boolean;
    revoked: boolean;
    expected: boolean;
    materialized: boolean;
    state: MatrixState;
  }

  const drift = computed(() => props.entitlements.drift);
  const inSync = computed(() => drift.value.in_sync);

  /**
   * The union of every source set, sorted. Catalog entries the org touches in
   * NO set are deliberately absent — this is the org's resolution story, not
   * the catalog (the override picker covers the catalog).
   */
  const rows = computed<MatrixRow[]>(() => {
    const e = props.entitlements;
    const plan = new Set(e.plan);
    const grants = new Set(e.grants);
    const revokes = new Set(e.revokes);
    const expected = new Set(e.expected);
    const materialized = new Set(e.materialized);
    const extra = new Set(e.drift.extra);
    const missing = new Set(e.drift.missing);

    const names = [...new Set([...e.plan, ...e.grants, ...e.revokes, ...e.materialized])].sort();

    return names.map((name) => {
      const row = {
        name,
        inPlan: plan.has(name),
        granted: grants.has(name),
        revoked: revokes.has(name),
        expected: expected.has(name),
        materialized: materialized.has(name),
      };
      // Drift first — an orphaned/missing row is the finding, whatever caused
      // it — then the override that explains a non-plan outcome.
      let state: MatrixState = 'plan';
      if (extra.has(name)) state = 'orphaned';
      else if (missing.has(name)) state = 'missing';
      else if (row.revoked) state = 'revoked';
      else if (row.granted && !row.inPlan) state = 'granted';
      return { ...row, state };
    });
  });

  /** The five boolean columns, in resolution order (sources → result). */
  const markColumns = computed(() => [
    {
      key: 'inPlan',
      label: t('web.admin.organizations.entitlements.matrix.columns.inPlan'),
      read: (row: MatrixRow) => row.inPlan,
    },
    {
      key: 'granted',
      label: t('web.admin.organizations.entitlements.matrix.columns.granted'),
      read: (row: MatrixRow) => row.granted,
    },
    {
      key: 'revoked',
      label: t('web.admin.organizations.entitlements.matrix.columns.revoked'),
      read: (row: MatrixRow) => row.revoked,
    },
    {
      key: 'expected',
      label: t('web.admin.organizations.entitlements.matrix.columns.expected'),
      read: (row: MatrixRow) => row.expected,
    },
    {
      key: 'materialized',
      label: t('web.admin.organizations.entitlements.matrix.columns.materialized'),
      read: (row: MatrixRow) => row.materialized,
    },
  ]);

  function stateLabel(state: MatrixState): string {
    switch (state) {
      case 'orphaned':
        return t('web.admin.organizations.entitlements.matrix.state.orphaned');
      case 'missing':
        return t('web.admin.organizations.entitlements.matrix.state.missing');
      case 'revoked':
        return t('web.admin.organizations.entitlements.matrix.state.revoked');
      case 'granted':
        return t('web.admin.organizations.entitlements.matrix.state.granted');
      default:
        return t('web.admin.organizations.entitlements.matrix.state.plan');
    }
  }

  function stateBadgeClass(state: MatrixState): string {
    switch (state) {
      case 'orphaned':
      case 'missing':
        return 'bg-amber-100 text-amber-800 dark:bg-amber-900/50 dark:text-amber-200';
      case 'revoked':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      case 'granted':
        return 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
    }
  }

  /** Drift rows get a warning wash; the rest stay neutral. */
  function rowClass(row: MatrixRow): string {
    if (row.state === 'orphaned' || row.state === 'missing') {
      return 'bg-amber-50 dark:bg-amber-900/20';
    }
    return '';
  }

  /** A revoke is the most-missed cause; make the name read as struck out. */
  function nameClass(row: MatrixRow): string {
    return row.revoked
      ? 'line-through decoration-red-500/70 text-gray-400 dark:text-gray-500'
      : 'text-gray-900 dark:text-gray-100';
  }

  // ---- Summary signals -------------------------------------------------------

  const materializedFlag = computed(() => props.entitlements.materialized_flag);

  const materializedAtLabel = computed(() => {
    const at = props.entitlements.materialized_at;
    return at ? formatDisplayDateTime(at) : t('web.admin.organizations.entitlements.summary.never');
  });

  /**
   * `plan_stale` is TRI-state on the wire: null means the plan could not be
   * loaded, i.e. we could not compare. Rendering that as "current" would assert
   * a state nobody verified, so it gets its own unknown label.
   */
  const planStaleLabel = computed(() => {
    const stale = props.entitlements.plan_stale;
    if (stale === null) return t('web.admin.organizations.entitlements.summary.planUnknown');
    return stale
      ? t('web.admin.organizations.entitlements.summary.planStale')
      : t('web.admin.organizations.entitlements.summary.planCurrent');
  });

  const planStaleClass = computed(() => {
    const stale = props.entitlements.plan_stale;
    if (stale === null) return 'text-gray-500 dark:text-gray-400';
    return stale ? 'text-amber-700 dark:text-amber-300' : 'text-gray-900 dark:text-gray-100';
  });
</script>

<template>
  <div class="space-y-5">
    <!-- Summary signals: the four wire-level flags, none of them inferred. -->
    <dl
      class="grid grid-cols-2 gap-4 sm:grid-cols-4"
      data-testid="entitlements-summary">
      <div data-testid="entitlements-summary-sync">
        <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.organizations.entitlements.summary.sync') }}
        </dt>
        <dd
          class="mt-1 text-sm font-medium"
          :class="
            inSync ? 'text-green-700 dark:text-green-300' : 'text-amber-700 dark:text-amber-300'
          ">
          {{
            inSync
              ? t('web.admin.organizations.detail.entitlements.inSync')
              : t('web.admin.organizations.detail.entitlements.driftBadge')
          }}
        </dd>
      </div>
      <div data-testid="entitlements-summary-materialized">
        <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.organizations.entitlements.summary.materialized') }}
        </dt>
        <dd
          class="mt-1 text-sm font-medium"
          :class="
            materializedFlag
              ? 'text-gray-900 dark:text-gray-100'
              : 'text-amber-700 dark:text-amber-300'
          ">
          {{
            materializedFlag
              ? t('web.admin.organizations.entitlements.summary.yes')
              : t('web.admin.organizations.entitlements.summary.no')
          }}
        </dd>
      </div>
      <div data-testid="entitlements-summary-materialized-at">
        <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.organizations.entitlements.summary.materializedAt') }}
        </dt>
        <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100">
          {{ materializedAtLabel }}
        </dd>
      </div>
      <div data-testid="entitlements-summary-plan-stale">
        <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.organizations.entitlements.summary.planDefinition') }}
        </dt>
        <dd
          class="mt-1 text-sm font-medium"
          :class="planStaleClass">
          {{ planStaleLabel }}
        </dd>
      </div>
    </dl>

    <!-- Drift call-out: the same two lists the matrix highlights, summarised. -->
    <div
      v-if="!inSync"
      class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm dark:border-amber-900/50 dark:bg-amber-900/20"
      role="alert"
      data-testid="entitlements-drift">
      <p class="flex items-center gap-1 font-medium text-amber-800 dark:text-amber-200">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="4" />
        {{ t('web.admin.organizations.detail.entitlements.driftWarning') }}
      </p>
      <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div>
          <p
            class="text-xs font-medium tracking-wider text-amber-700 uppercase dark:text-amber-300">
            {{ t('web.admin.organizations.detail.entitlements.driftExtra') }}
          </p>
          <div class="mt-1 flex flex-wrap gap-1">
            <span
              v-for="ent in drift.extra"
              :key="`extra-${ent}`"
              class="inline-flex items-center rounded bg-amber-100 px-2 py-0.5 font-mono text-xs text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
              {{ ent }}
            </span>
            <span
              v-if="drift.extra.length === 0"
              class="text-xs text-amber-600 dark:text-amber-400"
              >—</span
            >
          </div>
        </div>
        <div>
          <p
            class="text-xs font-medium tracking-wider text-amber-700 uppercase dark:text-amber-300">
            {{ t('web.admin.organizations.detail.entitlements.driftMissing') }}
          </p>
          <div class="mt-1 flex flex-wrap gap-1">
            <span
              v-for="ent in drift.missing"
              :key="`missing-${ent}`"
              class="inline-flex items-center rounded bg-amber-100 px-2 py-0.5 font-mono text-xs text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
              {{ ent }}
            </span>
            <span
              v-if="drift.missing.length === 0"
              class="text-xs text-amber-600 dark:text-amber-400"
              >—</span
            >
          </div>
        </div>
      </div>
    </div>

    <!--
      The matrix. The wrapper scrolls, not the page: seven columns do not fit a
      phone, and a sideways-scrolling page is worse than a sideways-scrolling
      table.
    -->
    <div
      class="overflow-x-auto rounded-md border border-gray-200 dark:border-gray-800"
      data-testid="entitlements-matrix-scroll">
      <table
        class="min-w-full text-left text-sm"
        data-testid="entitlements-matrix">
        <caption class="sr-only">
          {{
            t('web.admin.organizations.entitlements.matrix.caption')
          }}
        </caption>
        <thead class="bg-gray-50 dark:bg-gray-800/60">
          <tr>
            <th
              scope="col"
              class="px-3 py-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.entitlements.matrix.columns.entitlement') }}
            </th>
            <th
              v-for="column in markColumns"
              :key="column.key"
              scope="col"
              class="px-3 py-2 text-center text-xs font-medium tracking-wider whitespace-nowrap text-gray-500 uppercase dark:text-gray-400">
              {{ column.label }}
            </th>
            <th
              scope="col"
              class="px-3 py-2 text-xs font-medium tracking-wider whitespace-nowrap text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.entitlements.matrix.columns.state') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 dark:divide-gray-800">
          <tr
            v-for="row in rows"
            :key="row.name"
            :class="rowClass(row)"
            :data-state="row.state"
            :data-testid="`entitlement-row-${row.name}`">
            <th
              scope="row"
              class="px-3 py-2 font-mono text-xs font-normal whitespace-nowrap"
              :class="nameClass(row)">
              {{ row.name }}
            </th>
            <td
              v-for="column in markColumns"
              :key="column.key"
              class="px-3 py-2 text-center whitespace-nowrap"
              :class="
                column.read(row)
                  ? 'text-gray-900 dark:text-gray-100'
                  : 'text-gray-300 dark:text-gray-600'
              ">
              <span aria-hidden="true">{{ column.read(row) ? '✓' : '—' }}</span>
              <span class="sr-only">{{
                column.read(row)
                  ? t('web.admin.organizations.entitlements.matrix.yes')
                  : t('web.admin.organizations.entitlements.matrix.no')
              }}</span>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                class="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium"
                :class="stateBadgeClass(row.state)">
                {{ stateLabel(row.state) }}
              </span>
            </td>
          </tr>
          <tr v-if="rows.length === 0">
            <td
              :colspan="markColumns.length + 2"
              class="px-3 py-6 text-center text-sm text-gray-500 dark:text-gray-400"
              data-testid="entitlements-matrix-empty">
              {{ t('web.admin.organizations.entitlements.matrix.empty') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Legend: the resolution formula, plus what each warning state means. -->
    <div
      class="rounded-md bg-gray-50 p-3 text-xs text-gray-600 dark:bg-gray-800/50 dark:text-gray-400"
      data-testid="entitlements-legend">
      <p class="font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.admin.organizations.entitlements.matrix.legend.formula') }}
      </p>
      <ul class="mt-2 space-y-1">
        <li>{{ t('web.admin.organizations.entitlements.matrix.legend.orphaned') }}</li>
        <li>{{ t('web.admin.organizations.entitlements.matrix.legend.missing') }}</li>
        <li>{{ t('web.admin.organizations.entitlements.matrix.legend.revoked') }}</li>
      </ul>
    </div>
  </div>
</template>
