<!-- src/apps/admin/views/AdminOrganizationDetail.vue -->

<script setup lang="ts">
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { AdminConfirmDialog, DataTable, JsonViewer, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { InvestigateOrganizationResult } from '@/schemas/api/internal/responses/colonel';
  import { investigateOrganizationResponseSchema } from '@/schemas/api/internal/responses/colonel';
  import type {
    ColonelOrganizationDetailDomain,
    ColonelOrganizationDetailMember,
    ColonelReconcileOrganizationRecord,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import {
    colonelEntitlementOverrideResponseSchema,
    colonelOrganizationDetailResponseSchema,
    colonelReconcileOrganizationResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { getPlanLabel } from '@/types/billing';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  /**
   * Organization detail — the first-class detail page the colonel audit demanded
   * (the drawer-only list left operators editing entitlements blind and with no
   * view of members/domains). Fixes:
   *
   * - Entitlements read on load: plan / grants / revokes / materialized are shown
   *   distinctly so the operator sees WHY each entitlement resolves, BEFORE any
   *   mutation. Drift + plan-stale are surfaced as warnings.
   * - Members + Domains tables (previously invisible from the console).
   * - Investigate (read-only Stripe compare) PLUS Reconcile — the remediation the
   *   investigation points to (re-pull Stripe / re-materialize). Reconcile is
   *   MUTATING, so it is gated behind a typed-confirmation dialog (retype extid)
   *   and shows the before/after billing diff on success.
   *
   * Single-resource fetch via {@link useResourceFetch} against
   * GET /api/colonel/organizations/:id, keyed by the org's PUBLIC id (extid).
   * Every mutation refreshes that GET so the panel always renders live state,
   * never a partial ack.
   */
  const props = defineProps<{
    /** The organization's public id (route param), forwarded from the router. */
    id: string;
  }>();

  const { t } = useI18n();
  const router = useRouter();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const publicId = computed(() => props.id);
  const orgUrl = (): string => `/api/colonel/organizations/${encodeURIComponent(publicId.value)}`;

  const {
    data: orgData,
    loading: orgLoading,
    error: orgError,
    validationError: orgValidationError,
    notFound: orgNotFound,
    load: loadOrg,
    refresh: refreshOrg,
  } = useResourceFetch({
    url: orgUrl,
    schema: colonelOrganizationDetailResponseSchema,
    context: 'ColonelOrganizationDetailResponse',
  });

  const record = computed(() => orgData.value?.record ?? null);
  const details = computed(() => orgData.value?.details ?? null);
  const entitlements = computed(() => details.value?.entitlements ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const loadFailed = computed(
    () => (orgError.value !== null && !orgNotFound.value) || orgValidationError.value !== null
  );

  function planLabel(planid: string | null): string {
    return planid ? getPlanLabel(planid) : getPlanLabel('free');
  }

  // ---- Header + billing read-out --------------------------------------------

  const heading = computed(() => {
    const r = record.value;
    if (!r) return '';
    return r.display_name || r.contact_email || r.extid;
  });

  type ReadField = { key: string; label: string; value: string; mono?: boolean };

  /** Non-email billing rows (emails are rendered via RevealEmail, out of loop). */
  const billingFields = computed<ReadField[]>(() => {
    const r = record.value;
    if (!r) return [];
    return [
      { key: 'plan', label: t('web.admin.organizations.fields.plan'), value: planLabel(r.planid) },
      {
        key: 'subscription',
        label: t('web.admin.organizations.fields.subscription'),
        value: r.subscription_status || t('web.admin.organizations.detail.none'),
      },
      {
        key: 'periodEnd',
        label: t('web.admin.organizations.fields.periodEnd'),
        value: r.subscription_period_end || t('web.admin.organizations.detail.none'),
      },
      {
        key: 'stripeCustomer',
        label: t('web.admin.organizations.fields.stripeCustomer'),
        value: r.stripe_customer_id || t('web.admin.organizations.detail.none'),
        mono: true,
      },
      {
        key: 'stripeSubscription',
        label: t('web.admin.organizations.fields.stripeSubscription'),
        value: r.stripe_subscription_id || t('web.admin.organizations.detail.none'),
        mono: true,
      },
      {
        key: 'orgId',
        label: t('web.admin.organizations.fields.orgId'),
        value: r.extid,
        mono: true,
      },
      {
        key: 'created',
        label: t('web.admin.organizations.fields.created'),
        value: formatDisplayDateTime(r.created),
      },
      {
        key: 'updated',
        label: t('web.admin.organizations.fields.updated'),
        value: r.updated
          ? formatDisplayDateTime(r.updated)
          : t('web.admin.organizations.detail.none'),
      },
    ];
  });

  // ---- Entitlement chips (read-on-load breakdown) ---------------------------

  const drift = computed(() => entitlements.value?.drift ?? null);
  const inSync = computed(() => drift.value?.in_sync ?? true);
  const planStale = computed(() => entitlements.value?.plan_stale === true);

  // ---- Entitlement overrides (MUTATING — guarded + audited server-side) ------

  type EntitlementAction = 'grant' | 'revoke' | 'clear';

  const entitlementInput = ref('');
  const entitlementDialogOpen = ref(false);
  const activeEntitlementAction = ref<EntitlementAction | null>(null);
  /** The entitlement name captured when the dialog was requested (grant/revoke). */
  const pendingEntitlement = ref('');

  const {
    loading: entitlementLoading,
    error: entitlementError,
    run: runEntitlement,
    reset: resetEntitlement,
  } = useAdminMutation(async () => {
    const action = activeEntitlementAction.value;
    if (!action) throw new Error('No active entitlement action');

    const base = `${orgUrl()}/entitlements`;
    const response =
      action === 'clear'
        ? await $api.delete(`${base}/overrides`)
        : await $api.post(`${base}/${action}`, { entitlement: pendingEntitlement.value });

    // Tripwire only: a 2xx means the mutation succeeded regardless of ack shape;
    // the panel is driven by the refreshed detail GET, not this ack.
    gracefulParse(
      colonelEntitlementOverrideResponseSchema,
      response.data,
      'ColonelEntitlementOverrideResponse'
    );
  });

  function requestGrant(): void {
    if (!entitlementInput.value.trim()) return;
    pendingEntitlement.value = entitlementInput.value.trim();
    activeEntitlementAction.value = 'grant';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }
  function requestRevoke(): void {
    if (!entitlementInput.value.trim()) return;
    pendingEntitlement.value = entitlementInput.value.trim();
    activeEntitlementAction.value = 'revoke';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }
  function requestClear(): void {
    pendingEntitlement.value = '';
    activeEntitlementAction.value = 'clear';
    resetEntitlement();
    entitlementDialogOpen.value = true;
  }

  const entitlementDialogConfig = computed(() => {
    const name = heading.value;
    const token = record.value?.extid; // typed-confirmation: retype the public id.
    switch (activeEntitlementAction.value) {
      case 'grant':
        return {
          title: t('web.admin.organizations.entitlements.confirm.grantTitle'),
          description: t('web.admin.organizations.entitlements.confirm.grantDescription', {
            entitlement: pendingEntitlement.value,
            org: name,
          }),
          confirmToken: token,
          variant: 'default' as const,
          confirmText: t('web.admin.organizations.entitlements.grant'),
        };
      case 'revoke':
        return {
          title: t('web.admin.organizations.entitlements.confirm.revokeTitle'),
          description: t('web.admin.organizations.entitlements.confirm.revokeDescription', {
            entitlement: pendingEntitlement.value,
            org: name,
          }),
          confirmToken: token,
          variant: 'danger' as const,
          confirmText: t('web.admin.organizations.entitlements.revoke'),
        };
      case 'clear':
        return {
          title: t('web.admin.organizations.entitlements.confirm.clearTitle'),
          description: t('web.admin.organizations.entitlements.confirm.clearDescription', {
            org: name,
          }),
          confirmToken: token,
          variant: 'danger' as const,
          confirmText: t('web.admin.organizations.entitlements.clear'),
        };
      default:
        return {
          title: '',
          description: undefined,
          confirmToken: undefined,
          variant: 'default' as const,
          confirmText: undefined,
        };
    }
  });

  const ENTITLEMENT_SUCCESS_KEYS: Record<EntitlementAction, string> = {
    grant: 'web.admin.organizations.entitlements.success.granted',
    revoke: 'web.admin.organizations.entitlements.success.revoked',
    clear: 'web.admin.organizations.entitlements.success.cleared',
  };

  async function onEntitlementConfirm(): Promise<void> {
    const action = activeEntitlementAction.value;
    if (!action) return;

    const ok = await runEntitlement();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    entitlementDialogOpen.value = false;
    notifications.show(
      t(ENTITLEMENT_SUCCESS_KEYS[action], { entitlement: pendingEntitlement.value }),
      'success'
    );
    if (action === 'clear') entitlementInput.value = '';
    activeEntitlementAction.value = null;
    // Drive the panel from live state, never a partial ack.
    await refreshOrg().catch(() => {});
  }

  function onEntitlementCancel(): void {
    entitlementDialogOpen.value = false;
    activeEntitlementAction.value = null;
    resetEntitlement();
  }

  // ---- Investigate (read-only; POST-to-read, no mutation / no audit) --------

  const investigateLoading = ref(false);
  const investigateError = ref<string | null>(null);
  const investigateResult = ref<InvestigateOrganizationResult | null>(null);

  async function runInvestigate(): Promise<void> {
    investigateLoading.value = true;
    investigateError.value = null;
    try {
      const response = await $api.post(`${orgUrl()}/investigate`);
      const parsed = gracefulParse(
        investigateOrganizationResponseSchema,
        response.data,
        'InvestigateOrganizationResponse'
      );
      if (parsed.ok) {
        investigateResult.value = parsed.data.record;
      } else {
        investigateError.value = t('web.admin.organizations.investigate.parseError');
      }
    } catch {
      investigateError.value = t('web.colonel.organizations.investigation.failed');
    } finally {
      investigateLoading.value = false;
    }
  }

  function verdictBadgeClass(verdict: string): string {
    switch (verdict) {
      case 'synced':
        return 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200';
      case 'mismatch_detected':
        return 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300';
    }
  }
  function verdictLabel(verdict: string): string {
    switch (verdict) {
      case 'synced':
        return t('web.colonel.organizations.investigation.verifiedSynced');
      case 'mismatch_detected':
        return t('web.colonel.organizations.investigation.mismatchFound');
      default:
        return t('web.colonel.organizations.investigation.unableToCompare');
    }
  }
  function severityBadgeClass(severity: string): string {
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

  // ---- Reconcile (MUTATING remediation — guarded + audited server-side) ------

  const reconcileDialogOpen = ref(false);
  const reconcileResult = ref<ColonelReconcileOrganizationRecord | null>(null);

  const {
    loading: reconcileLoading,
    error: reconcileError,
    run: runReconcileMutation,
    reset: resetReconcile,
  } = useAdminMutation(async () => {
    const response = await $api.post(`${orgUrl()}/reconcile`);
    const parsed = gracefulParse(
      colonelReconcileOrganizationResponseSchema,
      response.data,
      'ColonelReconcileOrganizationResponse'
    );
    // A 2xx means the reconcile ran; hold the record for the before/after diff.
    reconcileResult.value = parsed.ok ? parsed.data.record : null;
  });

  function requestReconcile(): void {
    resetReconcile();
    reconcileDialogOpen.value = true;
  }

  async function onReconcileConfirm(): Promise<void> {
    const ok = await runReconcileMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    reconcileDialogOpen.value = false;
    notifications.show(t('web.admin.organizations.detail.reconcile.success'), 'success');
    // Refresh so billing + entitlements reflect the reconciled state.
    await refreshOrg().catch(() => {});
  }

  function onReconcileCancel(): void {
    reconcileDialogOpen.value = false;
    resetReconcile();
  }

  const reconcileDiffRows = computed(() => {
    const r = reconcileResult.value;
    if (!r) return [];
    return [
      {
        key: 'planid',
        label: t('web.admin.organizations.fields.plan'),
        before: r.before.planid || '—',
        after: r.after.planid || '—',
      },
      {
        key: 'subscriptionStatus',
        label: t('web.admin.organizations.fields.subscription'),
        before: r.before.subscription_status || '—',
        after: r.after.subscription_status || '—',
      },
      {
        key: 'periodEnd',
        label: t('web.admin.organizations.fields.periodEnd'),
        before: r.before.subscription_period_end || '—',
        after: r.after.subscription_period_end || '—',
      },
      {
        key: 'materializedCount',
        label: t('web.admin.organizations.detail.reconcile.materializedCount'),
        before: String(r.before.materialized_count),
        after: String(r.after.materialized_count),
      },
    ];
  });

  // ---- Members + Domains tables ---------------------------------------------

  const memberColumns = computed<DataTableColumn<ColonelOrganizationDetailMember>[]>(() => [
    { key: 'email', label: t('web.admin.organizations.detail.members.email') },
    { key: 'role', label: t('web.admin.organizations.detail.members.role') },
    { key: 'status', label: t('web.admin.organizations.detail.members.status') },
    { key: 'joined', label: t('web.admin.organizations.detail.members.joined') },
  ]);

  const domainColumns = computed<DataTableColumn<ColonelOrganizationDetailDomain>[]>(() => [
    { key: 'display_domain', label: t('web.admin.organizations.detail.domains.domain') },
    { key: 'state', label: t('web.admin.organizations.detail.domains.state') },
    { key: 'created', label: t('web.admin.organizations.detail.domains.created') },
  ]);

  function goBack(): void {
    router.push({ name: 'AdminOrganizations' });
  }

  onMounted(() => {
    loadOrg().catch(() => {});
  });
</script>

<template>
  <div class="mx-auto max-w-5xl">
    <!-- Back link -->
    <button
      type="button"
      class="mb-4 inline-flex items-center gap-1 text-sm font-medium text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-gray-200"
      data-testid="detail-back"
      @click="goBack">
      <OIcon
        collection="heroicons"
        name="arrow-left"
        size="4" />
      {{ t('web.admin.organizations.detail.backToList') }}
    </button>

    <!-- Loading -->
    <div
      v-if="orgLoading && !record"
      class="flex items-center justify-center py-24 text-gray-500 dark:text-gray-400"
      data-testid="detail-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        size="6"
        class="animate-spin motion-reduce:animate-none" />
      <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
    </div>

    <!-- Not found -->
    <div
      v-else-if="orgNotFound"
      class="rounded-lg border border-gray-200 bg-white px-6 py-16 text-center dark:border-gray-800 dark:bg-gray-900"
      data-testid="detail-not-found">
      <OIcon
        collection="heroicons"
        name="building-office-2"
        size="8"
        class="mx-auto text-gray-400 dark:text-gray-600" />
      <h3 class="mt-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.organizations.detail.notFound') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.organizations.detail.notFoundDescription') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="goBack">
        {{ t('web.admin.organizations.detail.backToList') }}
      </button>
    </div>

    <!-- Load error (network/HTTP non-404, or contract mismatch) -->
    <div
      v-else-if="loadFailed"
      class="rounded-lg border border-red-200 bg-red-50 px-6 py-16 text-center dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="detail-error">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="8"
        class="mx-auto text-red-500 dark:text-red-400" />
      <p class="mt-3 text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.organizations.detail.loadError') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadOrg().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.organizations.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else-if="record && details && entitlements"
      class="space-y-6"
      data-testid="detail-content">
      <!-- Header -->
      <div
        class="flex flex-wrap items-center gap-3 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ heading }}
        </h2>
        <span
          v-if="record.is_default"
          class="inline-flex rounded bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300"
          data-testid="default-badge">
          {{ t('web.admin.organizations.detail.badges.default') }}
        </span>
        <span
          v-if="record.archived"
          class="inline-flex items-center gap-1 rounded bg-amber-100 px-2 py-0.5 text-xs font-semibold tracking-wide text-amber-800 uppercase dark:bg-amber-900/40 dark:text-amber-200"
          data-testid="archived-badge">
          <OIcon
            collection="heroicons"
            name="archive-box"
            size="3" />
          {{ t('web.admin.organizations.detail.badges.archived') }}
        </span>
        <span class="font-mono text-xs text-gray-400 dark:text-gray-500">{{ record.extid }}</span>
      </div>

      <!-- Stat tiles -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard
          :label="t('web.colonel.organizations.columns.members')"
          :value="record.member_count"
          icon="users"
          testid="stat-members" />
        <StatCard
          :label="t('web.colonel.organizations.columns.domains')"
          :value="record.domain_count"
          icon="globe-alt"
          testid="stat-domains" />
        <StatCard
          :label="t('web.admin.organizations.fields.plan')"
          :value="planLabel(record.planid)"
          icon="credit-card"
          testid="stat-plan" />
        <StatCard
          :label="t('web.colonel.organizations.columns.status')"
          :value="record.sync_status"
          icon="shield-check"
          testid="stat-sync" />
      </div>

      <!-- Billing read-out -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="billing-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.detail.sections.billing') }}
          </h3>
        </div>
        <dl class="grid grid-cols-1 gap-x-6 gap-y-4 px-6 py-5 sm:grid-cols-2">
          <!-- Emails via RevealEmail (obscured by default). -->
          <div data-testid="billing-contactEmail">
            <dt
              class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.fields.contactEmail') }}
            </dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100">
              <RevealEmail :email="record.contact_email" />
            </dd>
          </div>
          <div data-testid="billing-owner">
            <dt
              class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.fields.owner') }}
            </dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100">
              <RevealEmail :email="record.owner_email" />
            </dd>
          </div>
          <div data-testid="billing-billingEmail">
            <dt
              class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.fields.billingEmail') }}
            </dt>
            <dd class="mt-1 text-sm text-gray-900 dark:text-gray-100">
              <RevealEmail :email="record.billing_email" />
            </dd>
          </div>
          <!-- Non-email rows. -->
          <div
            v-for="field in billingFields"
            :key="field.key"
            :data-testid="`billing-${field.key}`">
            <dt
              class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ field.label }}
            </dt>
            <dd
              class="mt-1 text-sm break-words text-gray-900 dark:text-gray-100"
              :class="field.mono ? 'font-mono text-xs' : ''">
              {{ field.value }}
            </dd>
          </div>
        </dl>
      </section>

      <!-- Entitlements: current state on load + grant/revoke/clear -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="entitlements-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <div class="flex flex-wrap items-center gap-3">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.organizations.entitlements.section') }}
            </h3>
            <span
              v-if="inSync"
              class="inline-flex items-center gap-1 rounded bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/40 dark:text-green-200"
              data-testid="entitlements-insync">
              <OIcon
                collection="heroicons"
                name="check-circle"
                size="3" />
              {{ t('web.admin.organizations.detail.entitlements.inSync') }}
            </span>
            <span
              v-else
              class="inline-flex items-center gap-1 rounded bg-red-100 px-2 py-0.5 text-xs font-semibold tracking-wide text-red-800 uppercase dark:bg-red-900/40 dark:text-red-200"
              data-testid="entitlements-drift-badge">
              <OIcon
                collection="heroicons"
                name="exclamation-triangle"
                size="3" />
              {{ t('web.admin.organizations.detail.entitlements.driftBadge') }}
            </span>
            <span
              v-if="planStale"
              class="inline-flex items-center gap-1 rounded bg-amber-100 px-2 py-0.5 text-xs font-semibold tracking-wide text-amber-800 uppercase dark:bg-amber-900/40 dark:text-amber-200"
              data-testid="entitlements-stale-badge">
              <OIcon
                collection="heroicons"
                name="clock"
                size="3" />
              {{ t('web.admin.organizations.detail.entitlements.staleBadge') }}
            </span>
          </div>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.organizations.detail.entitlements.description') }}
          </p>
        </div>

        <div class="space-y-5 px-6 py-5">
          <!-- Drift warning (extra / missing vs expected). -->
          <div
            v-if="!inSync && drift"
            class="rounded-md border border-red-200 bg-red-50 p-3 text-sm dark:border-red-900/50 dark:bg-red-900/20"
            role="alert"
            data-testid="entitlements-drift">
            <p class="font-medium text-red-800 dark:text-red-200">
              {{ t('web.admin.organizations.detail.entitlements.driftWarning') }}
            </p>
            <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <p
                  class="text-xs font-medium tracking-wider text-red-700 uppercase dark:text-red-300">
                  {{ t('web.admin.organizations.detail.entitlements.driftExtra') }}
                </p>
                <div class="mt-1 flex flex-wrap gap-1">
                  <span
                    v-for="ent in drift.extra"
                    :key="`extra-${ent}`"
                    class="inline-flex items-center rounded bg-red-100 px-2 py-0.5 font-mono text-xs text-red-800 dark:bg-red-900/40 dark:text-red-200">
                    {{ ent }}
                  </span>
                  <span
                    v-if="drift.extra.length === 0"
                    class="text-xs text-red-500 dark:text-red-400"
                    >—</span
                  >
                </div>
              </div>
              <div>
                <p
                  class="text-xs font-medium tracking-wider text-red-700 uppercase dark:text-red-300">
                  {{ t('web.admin.organizations.detail.entitlements.driftMissing') }}
                </p>
                <div class="mt-1 flex flex-wrap gap-1">
                  <span
                    v-for="ent in drift.missing"
                    :key="`missing-${ent}`"
                    class="inline-flex items-center rounded bg-red-100 px-2 py-0.5 font-mono text-xs text-red-800 dark:bg-red-900/40 dark:text-red-200">
                    {{ ent }}
                  </span>
                  <span
                    v-if="drift.missing.length === 0"
                    class="text-xs text-red-500 dark:text-red-400"
                    >—</span
                  >
                </div>
              </div>
            </div>
          </div>

          <!-- The distinct sources: plan / grants / revokes / materialized. -->
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div data-testid="entitlements-plan">
              <p
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.detail.entitlements.plan') }}
              </p>
              <div class="mt-1 flex flex-wrap gap-1">
                <span
                  v-for="ent in entitlements.plan"
                  :key="`plan-${ent}`"
                  class="inline-flex items-center rounded bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                  {{ ent }}
                </span>
                <span
                  v-if="entitlements.plan.length === 0"
                  class="text-xs text-gray-400 dark:text-gray-500"
                  >—</span
                >
              </div>
            </div>
            <div data-testid="entitlements-materialized">
              <p
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.detail.entitlements.materialized') }}
              </p>
              <div class="mt-1 flex flex-wrap gap-1">
                <span
                  v-for="ent in entitlements.materialized"
                  :key="`mat-${ent}`"
                  class="inline-flex items-center rounded bg-green-50 px-2 py-0.5 font-mono text-xs text-green-700 dark:bg-green-900/40 dark:text-green-200">
                  {{ ent }}
                </span>
                <span
                  v-if="entitlements.materialized.length === 0"
                  class="text-xs text-gray-400 dark:text-gray-500"
                  >—</span
                >
              </div>
            </div>
            <div data-testid="entitlements-grants">
              <p
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.entitlements.grants') }}
              </p>
              <div class="mt-1 flex flex-wrap gap-1">
                <span
                  v-for="ent in entitlements.grants"
                  :key="`grant-${ent}`"
                  class="inline-flex items-center rounded bg-brand-50 px-2 py-0.5 font-mono text-xs text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
                  {{ ent }}
                </span>
                <span
                  v-if="entitlements.grants.length === 0"
                  class="text-xs text-gray-400 dark:text-gray-500"
                  >—</span
                >
              </div>
            </div>
            <div data-testid="entitlements-revokes">
              <p
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.entitlements.revokes') }}
              </p>
              <div class="mt-1 flex flex-wrap gap-1">
                <span
                  v-for="ent in entitlements.revokes"
                  :key="`revoke-${ent}`"
                  class="inline-flex items-center rounded bg-red-50 px-2 py-0.5 font-mono text-xs text-red-700 dark:bg-red-900/30 dark:text-red-300">
                  {{ ent }}
                </span>
                <span
                  v-if="entitlements.revokes.length === 0"
                  class="text-xs text-gray-400 dark:text-gray-500"
                  >—</span
                >
              </div>
            </div>
          </div>

          <!-- Grant / revoke / clear controls. -->
          <div class="border-t border-gray-200 pt-5 dark:border-gray-800">
            <label
              for="org-entitlement-input"
              class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.entitlements.inputLabel') }}
            </label>
            <div class="mt-2 flex flex-wrap gap-2">
              <input
                id="org-entitlement-input"
                v-model="entitlementInput"
                type="text"
                autocomplete="off"
                spellcheck="false"
                data-testid="org-entitlement-input"
                :placeholder="t('web.admin.organizations.entitlements.placeholder')"
                class="min-w-0 flex-1 rounded-md border border-gray-300 px-3 py-2 font-mono text-sm placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
              <button
                type="button"
                data-testid="org-entitlement-grant"
                :disabled="!entitlementInput.trim()"
                class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
                @click="requestGrant">
                {{ t('web.admin.organizations.entitlements.grant') }}
              </button>
              <button
                type="button"
                data-testid="org-entitlement-revoke"
                :disabled="!entitlementInput.trim()"
                class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                @click="requestRevoke">
                {{ t('web.admin.organizations.entitlements.revoke') }}
              </button>
            </div>
            <button
              type="button"
              data-testid="org-entitlement-clear"
              class="mt-3 inline-flex items-center gap-1 text-sm font-medium text-red-700 hover:text-red-800 focus:outline-none dark:text-red-400 dark:hover:text-red-300"
              @click="requestClear">
              <OIcon
                collection="heroicons"
                name="trash"
                size="4" />
              {{ t('web.admin.organizations.entitlements.clear') }}
            </button>
          </div>
        </div>
      </section>

      <!-- Members -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.detail.sections.members') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400"
              >({{ details.members.length }})</span
            >
          </h3>
        </div>
        <DataTable
          :columns="memberColumns"
          :rows="details.members"
          row-key="extid"
          :empty-text="t('web.admin.organizations.detail.members.empty')"
          testid="members-table">
          <template #cell-email="{ row }">
            <span class="inline-flex items-center gap-2">
              <RevealEmail :email="row.email" />
              <span
                v-if="row.is_owner"
                class="inline-flex shrink-0 rounded bg-brand-50 px-1.5 py-0.5 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
                {{ t('web.admin.organizations.detail.members.owner') }}
              </span>
            </span>
          </template>
          <template #cell-role="{ row }">
            {{ row.role || '—' }}
          </template>
          <template #cell-status="{ row }">
            {{ row.status || '—' }}
          </template>
          <template #cell-joined="{ row }">
            {{ row.joined_at ? formatDisplayDateTime(row.joined_at) : '—' }}
          </template>
        </DataTable>
      </section>

      <!-- Domains -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.detail.sections.domains') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400"
              >({{ details.domains.length }})</span
            >
          </h3>
        </div>
        <DataTable
          :columns="domainColumns"
          :rows="details.domains"
          row-key="extid"
          :empty-text="t('web.admin.organizations.detail.domains.empty')"
          testid="domains-table">
          <template #cell-display_domain="{ row }">
            <div class="font-medium text-gray-900 dark:text-white">{{ row.display_domain }}</div>
            <div class="font-mono text-xs text-gray-400 dark:text-gray-500">
              {{ row.base_domain }}
            </div>
          </template>
          <template #cell-state="{ row }">
            <div class="flex flex-wrap items-center gap-1.5">
              <span
                class="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium"
                :class="
                  row.verified
                    ? 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-200'
                    : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300'
                ">
                {{ row.verification_state }}
              </span>
              <span
                v-if="row.ready"
                class="inline-flex items-center rounded bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/50 dark:text-green-200">
                {{ t('web.admin.organizations.detail.domains.ready') }}
              </span>
              <span
                v-if="row.resolving"
                class="inline-flex items-center rounded bg-blue-100 px-1.5 py-0.5 text-xs font-medium text-blue-800 dark:bg-blue-900/50 dark:text-blue-200">
                {{ t('web.admin.organizations.detail.domains.resolving') }}
              </span>
            </div>
          </template>
          <template #cell-created="{ row }">
            {{ row.created ? formatDisplayDateTime(row.created) : '—' }}
          </template>
        </DataTable>
      </section>

      <!-- Investigate + Reconcile -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="org-investigate">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.detail.sections.investigate') }}
          </h3>
          <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.organizations.investigate.description') }}
          </p>
        </div>

        <div class="space-y-4 px-6 py-5">
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              data-testid="org-investigate-button"
              :disabled="investigateLoading"
              class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
              @click="runInvestigate">
              <OIcon
                collection="heroicons"
                :name="investigateLoading ? 'arrow-path' : 'magnifying-glass'"
                size="4"
                :class="investigateLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
              {{
                investigateLoading
                  ? t('web.colonel.organizations.actions.checking')
                  : t('web.colonel.organizations.actions.investigate')
              }}
            </button>
            <!-- Reconcile: the remediation the investigation points to. -->
            <button
              type="button"
              data-testid="org-reconcile-button"
              :disabled="reconcileLoading"
              class="inline-flex items-center gap-1 rounded-md border border-amber-400 px-3 py-2 text-sm font-semibold text-amber-700 hover:bg-amber-50 focus:ring-2 focus:ring-amber-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-amber-700 dark:text-amber-300 dark:hover:bg-amber-900/30"
              @click="requestReconcile">
              <OIcon
                collection="heroicons"
                name="arrow-path-rounded-square"
                size="4" />
              {{ t('web.admin.organizations.detail.reconcile.button') }}
            </button>
          </div>

          <!-- Reconcile before/after diff (success). -->
          <div
            v-if="reconcileResult"
            class="rounded-md border border-amber-200 bg-amber-50 p-4 dark:border-amber-900/50 dark:bg-amber-900/20"
            data-testid="org-reconcile-result">
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-medium text-amber-800 dark:text-amber-200">
                {{ t('web.admin.organizations.detail.reconcile.resultTitle') }}
              </span>
              <span
                class="inline-flex items-center rounded bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
                {{ t(`web.admin.organizations.detail.reconcile.mode.${reconcileResult.mode}`) }}
              </span>
              <span class="text-xs text-amber-700 dark:text-amber-300">{{
                reconcileResult.status
              }}</span>
            </div>
            <p
              v-if="reconcileResult.reason"
              class="mt-1 text-xs text-amber-700 dark:text-amber-300">
              {{ reconcileResult.reason }}
            </p>
            <table class="mt-3 w-full text-left text-xs">
              <thead>
                <tr class="text-amber-700 dark:text-amber-300">
                  <th class="py-1 pr-4 font-medium"></th>
                  <th class="py-1 pr-4 font-medium">
                    {{ t('web.admin.organizations.detail.reconcile.before') }}
                  </th>
                  <th class="py-1 font-medium">
                    {{ t('web.admin.organizations.detail.reconcile.after') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in reconcileDiffRows"
                  :key="row.key"
                  :data-testid="`reconcile-diff-${row.key}`"
                  class="border-t border-amber-200/60 dark:border-amber-900/40">
                  <td class="py-1 pr-4 text-amber-700 dark:text-amber-300">{{ row.label }}</td>
                  <td class="py-1 pr-4 font-mono text-gray-700 line-through dark:text-gray-400">
                    {{ row.before }}
                  </td>
                  <td class="py-1 font-mono font-medium text-gray-900 dark:text-white">
                    {{ row.after }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Investigate error -->
          <div
            v-if="investigateError"
            class="rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-300"
            role="alert"
            data-testid="org-investigate-error">
            {{ investigateError }}
          </div>

          <!-- Investigate result -->
          <div
            v-else-if="investigateResult"
            class="space-y-4"
            data-testid="org-investigate-result">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
                :class="verdictBadgeClass(investigateResult.comparison.verdict)"
                data-testid="org-investigate-verdict">
                {{ verdictLabel(investigateResult.comparison.verdict) }}
              </span>
              <span class="text-xs text-gray-500 dark:text-gray-400">
                {{ investigateResult.investigated_at }}
              </span>
            </div>

            <p
              v-if="investigateResult.comparison.details"
              class="text-sm text-gray-600 dark:text-gray-300">
              {{ investigateResult.comparison.details }}
            </p>

            <!-- Issues (field + local vs stripe + severity) -->
            <div
              v-if="investigateResult.comparison.issues?.length"
              class="space-y-2">
              <div
                v-for="(issue, idx) in investigateResult.comparison.issues"
                :key="idx"
                class="rounded border border-gray-200 bg-gray-50 p-2 text-xs dark:border-gray-700 dark:bg-gray-800/50">
                <div class="flex items-center gap-2">
                  <span
                    class="inline-flex items-center rounded px-1.5 py-0.5 font-medium"
                    :class="severityBadgeClass(issue.severity)">
                    {{ issue.severity }}
                  </span>
                  <span class="font-medium text-gray-700 dark:text-gray-300">{{
                    issue.field
                  }}</span>
                </div>
                <div class="mt-1 grid grid-cols-2 gap-4">
                  <div>
                    <span class="text-gray-500 dark:text-gray-400"
                      >{{ t('web.colonel.organizations.investigation.local') }}:</span
                    >
                    <code class="ml-1 text-gray-900 dark:text-white">{{ issue.local }}</code>
                  </div>
                  <div>
                    <span class="text-gray-500 dark:text-gray-400"
                      >{{ t('web.colonel.organizations.investigation.stripe') }}:</span
                    >
                    <code class="ml-1 text-gray-900 dark:text-white">{{ issue.stripe }}</code>
                  </div>
                </div>
              </div>
            </div>

            <!-- Stripe subscription summary (when available) -->
            <div
              v-if="investigateResult.stripe.available && investigateResult.stripe.subscription"
              class="border-t border-gray-200 pt-3 dark:border-gray-700">
              <h4 class="mb-2 text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.organizations.investigation.stripeDetails') }}
              </h4>
              <div class="grid grid-cols-2 gap-2 text-xs md:grid-cols-4">
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.statusLabel') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.status
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.product') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.product_name || 'N/A'
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.resolvedPlan') }}:</span
                  >
                  <span class="ml-1 font-medium text-gray-900 dark:text-white">{{
                    investigateResult.stripe.subscription.resolved_plan_id || '(none)'
                  }}</span>
                </div>
                <div>
                  <span class="text-gray-500 dark:text-gray-400"
                    >{{ t('web.colonel.organizations.investigation.priceId') }}:</span
                  >
                  <code class="ml-1 font-mono text-gray-700 dark:text-gray-300">{{
                    investigateResult.stripe.subscription.price_id || 'N/A'
                  }}</code>
                </div>
              </div>
            </div>
            <p
              v-else-if="investigateResult.stripe.reason"
              class="text-xs text-gray-500 dark:text-gray-400">
              {{ investigateResult.stripe.reason }}
            </p>

            <!-- Raw payload -->
            <div>
              <h4
                class="mb-2 text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.investigate.rawPayload') }}
              </h4>
              <JsonViewer
                :data="investigateResult"
                :expand-depth="1"
                testid="org-investigate-json" />
            </div>
          </div>
        </div>
      </section>
    </div>

    <!-- Guarded entitlement mutation (typed-confirmation — retype the extid). -->
    <AdminConfirmDialog
      v-model:open="entitlementDialogOpen"
      :title="entitlementDialogConfig.title"
      :description="entitlementDialogConfig.description"
      :confirm-token="entitlementDialogConfig.confirmToken"
      :variant="entitlementDialogConfig.variant"
      :confirm-text="entitlementDialogConfig.confirmText"
      :loading="entitlementLoading"
      :error="entitlementError"
      @confirm="onEntitlementConfirm"
      @cancel="onEntitlementCancel" />

    <!-- Guarded reconcile (typed-confirmation — retype the extid). -->
    <AdminConfirmDialog
      v-model:open="reconcileDialogOpen"
      :title="t('web.admin.organizations.detail.reconcile.confirmTitle')"
      :description="
        t('web.admin.organizations.detail.reconcile.confirmDescription', { org: heading })
      "
      :confirm-token="record?.extid"
      variant="danger"
      :confirm-text="t('web.admin.organizations.detail.reconcile.button')"
      :loading="reconcileLoading"
      :error="reconcileError"
      @confirm="onReconcileConfirm"
      @cancel="onReconcileCancel" />
  </div>
</template>
