<!-- src/apps/admin/views/AdminCustomerDetail.vue -->

<script setup lang="ts">

  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { AdminConfirmDialog, DataTable, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelUserDetailReceipt,
    ColonelUserDetailSecret,
  } from '@/schemas/api/internal/responses/colonel';
  import {
    colonelAvailablePlansResponseSchema,
    colonelUserDetailResponseSchema,
    colonelUserMutationResponseSchema,
  } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  /**
   * Customer detail — the "support without SSH" read-out plus the guarded
   * mutation buttons (ticket #22, the reference slice for tickets 30/31/32).
   *
   * - Single-resource fetch via {@link useResourceFetch} against
   *   GET /api/colonel/users/:id, keyed by the customer's PUBLIC id (extid).
   * - Read-out: profile, plan/entitlement, verification + role, key timestamps,
   *   lifetime stats, billing (plan + latest Stripe invoice, gracefully
   *   degrading when Stripe is unconfigured/unreachable), and the customer's
   *   secrets / receipts / organizations. Loading, empty, not-found and error
   *   states are all handled explicitly.
   * - Guarded actions (CONTRACT 3 / D4): set-role, verify, unverify and
   *   unsuspend go through a simple confirm; PURGE and SUSPEND require typed
   *   confirmation (retype the public id) via {@link AdminConfirmDialog} in
   *   danger mode. Suspension is the reversible trust & safety pause (no data
   *   destroyed — unlike purge); colonel accounts cannot be suspended. Audit
   *   is emitted server-side; nothing here logs it.
   */
  const props = defineProps<{
    /** The customer's public id (route param), forwarded from the router. */
    id: string;
  }>();

  const { t } = useI18n();
  const router = useRouter();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const publicId = computed(() => props.id);
  const userUrl = (): string => `/api/colonel/users/${encodeURIComponent(publicId.value)}`;

  const {
    data: userData,
    loading: userLoading,
    error: userError,
    validationError: userValidationError,
    notFound: userNotFound,
    load: loadUser,
    refresh: refreshUser,
  } = useResourceFetch({
    url: userUrl,
    schema: colonelUserDetailResponseSchema,
    context: 'ColonelUserDetailResponse',
  });

  const record = computed(() => userData.value?.record ?? null);
  const details = computed(() => userData.value?.details ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const loadFailed = computed(
    () => (userError.value !== null && !userNotFound.value) || userValidationError.value !== null
  );

  // ---- Available plans (for the plan selector) ------------------------------
  // The endpoint returns a BARE { plans, source } body (no record/details
  // envelope), so the schema is a plain object, not createApiResponseSchema.
  // Loaded once on mount; the list is site-wide, not per-customer.
  const { data: plansData, load: loadPlans } = useResourceFetch({
    url: '/api/colonel/available-plans',
    schema: colonelAvailablePlansResponseSchema,
    context: 'ColonelAvailablePlansResponse',
  });

  const availablePlans = computed(() => plansData.value?.plans ?? []);
  /** True when plans came from billing.yaml (Stripe unconfigured/unreachable). */
  const plansFromLocalConfig = computed(() => plansData.value?.source === 'local_config');

  /**
   * Selectable plan ids, sorted by display_order then name. The customer's
   * current planid is always included (prepended) even if the catalog no longer
   * lists it, so a legacy plan still renders as the selected option.
   */
  const planOptions = computed(() => {
    const options = [...availablePlans.value]
      .sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0) || a.name.localeCompare(b.name))
      .map((p) => ({ planid: p.planid, label: `${p.name} (${p.planid})` }));
    const current = record.value?.planid;
    if (current && !options.some((o) => o.planid === current)) {
      options.unshift({ planid: current, label: current });
    }
    return options;
  });

  // ---- Guarded actions ------------------------------------------------------

  type ActionKey =
    | 'setRole'
    | 'changePlan'
    | 'verify'
    | 'unverify'
    | 'suspend'
    | 'unsuspend'
    | 'purge';

  /** Assignable roles, mirrored from the backend SetRole::VALID_ROLES. */
  const ROLE_OPTIONS = ['colonel', 'admin', 'staff', 'customer'] as const;

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);
  const pendingRole = ref('');
  /** Plan selector value; synced to the loaded record's planid. */
  const pendingPlan = ref('');
  /** Optional operator-supplied suspension reason (sent with the suspend POST). */
  const suspendReason = ref('');

  // Keep the role + plan selectors in sync with the loaded record.
  watch(
    record,
    (value) => {
      pendingRole.value = value?.role ?? '';
      pendingPlan.value = value?.planid ?? '';
    },
    { immediate: true }
  );

  /**
   * POST/DELETE a colonel mutation endpoint, then run the response through the
   * shared ack schema so it stays a live tripwire. A 2xx means the mutation
   * succeeded server-side regardless of ack shape (we refresh the record after),
   * so a schema mismatch is reported by gracefulParse but does not fail the action.
   */
  async function callMutation(
    method: 'post' | 'delete',
    path: string,
    body?: unknown
  ): Promise<void> {
    const response =
      method === 'delete' ? await $api.delete(path) : await $api.post(path, body ?? {});
    gracefulParse(
      colonelUserMutationResponseSchema,
      response.data,
      'ColonelUserMutationResponse'
    );
  }

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    switch (activeAction.value) {
      case 'setRole':
        return callMutation('post', `${userUrl()}/role`, { role: pendingRole.value });
      case 'changePlan':
        return callMutation('post', `${userUrl()}/plan`, { planid: pendingPlan.value });
      case 'verify':
        return callMutation('post', `${userUrl()}/verify`);
      case 'unverify':
        return callMutation('post', `${userUrl()}/unverify`);
      case 'suspend':
        return callMutation(
          'post',
          `${userUrl()}/suspend`,
          suspendReason.value.trim() ? { reason: suspendReason.value.trim() } : {}
        );
      case 'unsuspend':
        return callMutation('post', `${userUrl()}/unsuspend`);
      case 'purge':
        return callMutation('delete', userUrl());
      default:
        throw new Error('No active action');
    }
  });

  /**
   * The i18n key segment per action (mostly the action name, but setRole →
   * `role` and changePlan → `plan` to match the existing translation tree).
   */
  const ACTION_I18N_KEY: Record<ActionKey, string> = {
    setRole: 'role',
    changePlan: 'plan',
    verify: 'verify',
    unverify: 'unverify',
    suspend: 'suspend',
    unsuspend: 'unsuspend',
    purge: 'purge',
  };

  /** Destructive actions gate confirm behind retyping the public id. */
  const DANGER_ACTIONS: readonly ActionKey[] = ['purge', 'suspend'];

  const dialogConfig = computed(() => {
    const action = activeAction.value;
    const blank = {
      title: '',
      description: undefined,
      confirmToken: undefined,
      variant: 'default' as const,
      confirmText: undefined,
    };
    if (!action) return blank;

    const key = ACTION_I18N_KEY[action];
    // Extra interpolation vars only setRole/changePlan use; harmless elsewhere.
    const args: Record<string, string> = { email: record.value?.email ?? '' };
    if (action === 'setRole') {
      args.role = t(`web.admin.customers.roles.${pendingRole.value}`, pendingRole.value);
    } else if (action === 'changePlan') {
      args.plan = pendingPlan.value;
    }
    const isDanger = DANGER_ACTIONS.includes(action);
    return {
      title: t(`web.admin.customers.actions.${key}.confirmTitle`),
      description: t(`web.admin.customers.actions.${key}.confirmDescription`, args),
      // Typed-confirmation gate: retype the public id to enable confirm.
      confirmToken: isDanger ? publicId.value : undefined,
      variant: isDanger ? ('danger' as const) : ('default' as const),
      confirmText: isDanger ? t(`web.admin.customers.actions.${key}.button`) : undefined,
    };
  });

  const successMessageKey: Record<ActionKey, string> = {
    setRole: 'web.admin.customers.actions.role.success',
    changePlan: 'web.admin.customers.actions.plan.success',
    verify: 'web.admin.customers.actions.verify.success',
    unverify: 'web.admin.customers.actions.unverify.success',
    suspend: 'web.admin.customers.actions.suspend.success',
    unsuspend: 'web.admin.customers.actions.unsuspend.success',
    purge: 'web.admin.customers.actions.purge.success',
  };

  function requestAction(key: ActionKey): void {
    activeAction.value = key;
    resetMutation();
    dialogOpen.value = true;
  }

  function requestSetRole(): void {
    // No-op guard: ignore if the role is unchanged (nothing to confirm).
    if (!pendingRole.value || pendingRole.value === record.value?.role) return;
    requestAction('setRole');
  }

  function requestChangePlan(): void {
    // No-op guard: ignore if the plan is unchanged (nothing to confirm).
    if (!pendingPlan.value || pendingPlan.value === record.value?.planid) return;
    requestAction('changePlan');
  }

  async function onConfirm(): Promise<void> {
    const key = activeAction.value;
    if (!key) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;
    notifications.show(t(successMessageKey[key]), 'success');

    if (key === 'purge') {
      // The record no longer exists — return to the list.
      router.push({ name: 'AdminCustomers' });
    } else {
      if (key === 'suspend') suspendReason.value = '';
      await refreshUser().catch(() => {});
    }
    activeAction.value = null;
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    resetMutation();
  }

  // ---- Read-out tables ------------------------------------------------------

  const secretColumns = computed<DataTableColumn<ColonelUserDetailSecret>[]>(() => [
    { key: 'shortid', label: t('web.admin.customers.detail.secretColumns.shortId') },
    { key: 'state', label: t('web.admin.customers.detail.secretColumns.state') },
    { key: 'created', label: t('web.admin.customers.detail.secretColumns.created') },
    { key: 'expiration', label: t('web.admin.customers.detail.secretColumns.expiration') },
  ]);

  const receiptColumns = computed<DataTableColumn<ColonelUserDetailReceipt>[]>(() => [
    { key: 'shortid', label: t('web.admin.customers.detail.receiptColumns.shortId') },
    { key: 'state', label: t('web.admin.customers.detail.receiptColumns.state') },
    { key: 'created', label: t('web.admin.customers.detail.receiptColumns.created') },
  ]);

  const profileFields = computed(() => {
    const r = record.value;
    if (!r) return [];
    return [
      { key: 'email', label: t('web.admin.customers.detail.fields.email'), value: r.email },
      { key: 'publicId', label: t('web.admin.customers.detail.fields.publicId'), value: r.extid },
      {
        key: 'role',
        label: t('web.admin.customers.detail.fields.role'),
        value: t(`web.admin.customers.roles.${r.role}`, r.role),
      },
      {
        key: 'verified',
        label: t('web.admin.customers.detail.fields.verified'),
        value: r.verified
          ? t('web.admin.customers.detail.yes')
          : t('web.admin.customers.detail.no'),
      },
      {
        key: 'plan',
        label: t('web.admin.customers.detail.fields.plan'),
        value: r.planid || t('web.admin.customers.detail.none'),
      },
      {
        key: 'locale',
        label: t('web.admin.customers.detail.fields.locale'),
        value: r.locale || t('web.admin.customers.detail.none'),
      },
      {
        key: 'created',
        label: t('web.admin.customers.detail.fields.created'),
        value: formatDisplayDateTime(r.created),
      },
      {
        key: 'updated',
        label: t('web.admin.customers.detail.fields.updated'),
        value: r.updated
          ? formatDisplayDateTime(r.updated)
          : t('web.admin.customers.detail.never'),
      },
      {
        key: 'lastLogin',
        label: t('web.admin.customers.detail.fields.lastLogin'),
        value: r.last_login
          ? formatDisplayDateTime(r.last_login)
          : t('web.admin.customers.detail.never'),
      },
      // Suspension context, only while suspended (who / when / why).
      ...(r.suspended
        ? [
            {
              key: 'suspendedAt',
              label: t('web.admin.customers.detail.fields.suspendedAt'),
              value: r.suspended_at
                ? formatDisplayDateTime(r.suspended_at)
                : t('web.admin.customers.detail.none'),
            },
            {
              key: 'suspendedBy',
              label: t('web.admin.customers.detail.fields.suspendedBy'),
              value: r.suspended_by || t('web.admin.customers.detail.none'),
            },
            {
              key: 'suspendedReason',
              label: t('web.admin.customers.detail.fields.suspendedReason'),
              value: r.suspended_reason || t('web.admin.customers.detail.none'),
            },
          ]
        : []),
    ];
  });

  // ---- Billing card ----------------------------------------------------------

  /** Billing summary (plan + org subscription + optional live Stripe block). */
  const billing = computed(() => details.value?.billing ?? null);

  /** "12.34 USD" from Stripe's smallest-currency-unit total. */
  function invoiceAmount(total: number | null, currency: string | null): string {
    if (total === null) return t('web.admin.customers.detail.none');
    const amount = (total / 100).toFixed(2);
    return currency ? `${amount} ${currency.toUpperCase()}` : amount;
  }

  type BillingSummary = NonNullable<typeof billing.value>;
  type BillingField = { key: string; label: string; value: string };

  /** Org-scoped rows (name, subscription status, period end), if an org exists. */
  function organizationBillingFields(b: BillingSummary): BillingField[] {
    const org = b.organization;
    if (!org) return [];

    const rows: BillingField[] = [
      {
        key: 'organization',
        label: t('web.admin.customers.detail.billing.organization'),
        value: org.display_name || org.extid,
      },
    ];
    const status = b.stripe.subscription?.status || org.subscription_status;
    if (status) {
      rows.push({
        key: 'subscriptionStatus',
        label: t('web.admin.customers.detail.billing.subscriptionStatus'),
        value: status,
      });
    }
    const periodEnd =
      b.stripe.subscription?.current_period_end ??
      (org.subscription_period_end ? Number(org.subscription_period_end) : null);
    if (periodEnd) {
      rows.push({
        key: 'periodEnd',
        label: t('web.admin.customers.detail.billing.periodEnd'),
        value: formatDisplayDateTime(new Date(periodEnd * 1000)),
      });
    }
    return rows;
  }

  /** The "latest invoice" row, only when the live Stripe read succeeded. */
  function latestInvoiceFields(b: BillingSummary): BillingField[] {
    if (!b.stripe.available) return [];

    const invoice = b.stripe.latest_invoice;
    const value = invoice
      ? [
          invoice.created ? formatDisplayDateTime(invoice.created) : null,
          invoiceAmount(invoice.total, invoice.currency),
          invoice.status,
        ]
          .filter(Boolean)
          .join(' · ')
      : t('web.admin.customers.detail.billing.noInvoices');
    return [
      { key: 'latestInvoice', label: t('web.admin.customers.detail.billing.latestInvoice'), value },
    ];
  }

  const billingFields = computed<BillingField[]>(() => {
    const b = billing.value;
    if (!b) return [];

    return [
      {
        key: 'plan',
        label: t('web.admin.customers.detail.billing.plan'),
        value: b.plan_id || record.value?.planid || t('web.admin.customers.detail.none'),
      },
      ...organizationBillingFields(b),
      ...latestInvoiceFields(b),
    ];
  });

  function goBack(): void {
    router.push({ name: 'AdminCustomers' });
  }

  onMounted(() => {
    loadUser().catch(() => {});
    // Plans populate the selector; a failure just leaves the current plan as the
    // only option (the selector degrades, the rest of the page is unaffected).
    loadPlans().catch(() => {});
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
      {{ t('web.admin.customers.detail.backToList') }}
    </button>

    <!-- Loading -->
    <div
      v-if="userLoading && !record"
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
      v-else-if="userNotFound"
      class="rounded-lg border border-gray-200 bg-white px-6 py-16 text-center dark:border-gray-800 dark:bg-gray-900"
      data-testid="detail-not-found">
      <OIcon
        collection="heroicons"
        name="user-minus"
        size="8"
        class="mx-auto text-gray-400 dark:text-gray-600" />
      <h3 class="mt-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.customers.detail.notFound') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.customers.detail.notFoundDescription') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="goBack">
        {{ t('web.admin.customers.detail.backToList') }}
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
        {{ t('web.admin.customers.detail.loadError') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadUser().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.customers.detail.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else-if="record && details"
      class="space-y-6"
      data-testid="detail-content">
      <!-- Header -->
      <div class="flex flex-wrap items-center gap-3 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          <RevealEmail :email="record.email" />
        </h2>
        <span
          class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
          :class="
            record.role === 'colonel' || record.role === 'admin'
              ? 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200'
              : 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300'
          ">
          {{ t(`web.admin.customers.roles.${record.role}`, record.role) }}
        </span>
        <span
          v-if="record.verified"
          class="inline-flex items-center gap-1 rounded bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/40 dark:text-green-200">
          <OIcon
            collection="heroicons"
            name="check-circle"
            size="3" />
          {{ t('web.admin.customers.detail.fields.verified') }}
        </span>
        <span
          v-if="record.suspended"
          class="inline-flex items-center gap-1 rounded bg-red-100 px-2 py-0.5 text-xs font-semibold tracking-wide text-red-800 uppercase dark:bg-red-900/40 dark:text-red-200"
          data-testid="suspended-badge">
          <OIcon
            collection="heroicons"
            name="no-symbol"
            size="3" />
          {{ t('web.admin.customers.suspended.badge') }}
        </span>
        <span class="font-mono text-xs text-gray-400 dark:text-gray-500">{{ record.extid }}</span>
      </div>

      <!-- Stat tiles -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        <StatCard
          :label="t('web.admin.customers.detail.sections.secrets')"
          :value="details.secrets.count"
          icon="key"
          testid="stat-secrets" />
        <StatCard
          :label="t('web.admin.customers.detail.sections.receipts')"
          :value="details.receipts.count"
          icon="receipt-percent"
          testid="stat-receipts" />
        <StatCard
          :label="t('web.admin.customers.detail.stats.secretsCreated')"
          :value="details.stats.secrets_created" />
        <StatCard
          :label="t('web.admin.customers.detail.stats.secretsShared')"
          :value="details.stats.secrets_shared" />
        <StatCard
          :label="t('web.admin.customers.detail.stats.emailsSent')"
          :value="details.stats.emails_sent" />
      </div>

      <!-- Profile + Actions -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <!-- Profile -->
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm lg:col-span-2 dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.customers.detail.sections.profile') }}
            </h3>
          </div>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-4 px-6 py-5 sm:grid-cols-2">
            <div
              v-for="field in profileFields"
              :key="field.key"
              :data-testid="`profile-${field.key}`">
              <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd class="mt-1 text-sm break-words text-gray-900 dark:text-gray-100">
                <RevealEmail
                  v-if="field.key === 'email'"
                  :email="record.email" />
                <template v-else>{{ field.value }}</template>
              </dd>
            </div>
          </dl>
        </section>

        <!-- Action panel -->
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
          data-testid="action-panel">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.customers.detail.sections.actions') }}
            </h3>
          </div>
          <div class="space-y-4 px-6 py-5">
            <!-- Change role -->
            <div>
              <label
                for="detail-role-select"
                class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.customers.actions.role.label') }}
              </label>
              <div class="mt-2 flex gap-2">
                <select
                  id="detail-role-select"
                  v-model="pendingRole"
                  data-testid="role-select"
                  class="min-w-0 flex-1 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
                  <option
                    v-for="role in ROLE_OPTIONS"
                    :key="role"
                    :value="role">
                    {{ t(`web.admin.customers.roles.${role}`) }}
                  </option>
                </select>
                <button
                  type="button"
                  data-testid="role-apply"
                  :disabled="pendingRole === record.role"
                  class="inline-flex shrink-0 items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
                  @click="requestSetRole">
                  {{ t('web.admin.customers.actions.role.apply') }}
                </button>
              </div>
            </div>

            <!-- Change plan (catalog-validated server-side; reversible) -->
            <div>
              <label
                for="detail-plan-select"
                class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.customers.actions.plan.label') }}
              </label>
              <div class="mt-2 flex gap-2">
                <select
                  id="detail-plan-select"
                  v-model="pendingPlan"
                  data-testid="plan-select"
                  class="min-w-0 flex-1 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
                  <option
                    v-for="plan in planOptions"
                    :key="plan.planid"
                    :value="plan.planid">
                    {{ plan.label }}
                  </option>
                </select>
                <button
                  type="button"
                  data-testid="plan-apply"
                  :disabled="pendingPlan === record.planid"
                  class="inline-flex shrink-0 items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
                  @click="requestChangePlan">
                  {{ t('web.admin.customers.actions.plan.apply') }}
                </button>
              </div>
              <!-- Stripe unconfigured/unreachable: plans came from billing.yaml. -->
              <p
                v-if="plansFromLocalConfig"
                class="mt-2 text-xs text-amber-600 dark:text-amber-400"
                data-testid="plan-local-config-warning">
                {{ t('web.admin.customers.actions.plan.localConfigWarning') }}
              </p>
            </div>

            <!-- Verify / unverify -->
            <button
              v-if="!record.verified"
              type="button"
              data-testid="verify-button"
              class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
              @click="requestAction('verify')">
              <OIcon
                collection="heroicons"
                name="check-circle"
                size="4" />
              {{ t('web.admin.customers.actions.verify.button') }}
            </button>
            <button
              v-else
              type="button"
              data-testid="unverify-button"
              class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
              @click="requestAction('unverify')">
              <OIcon
                collection="heroicons"
                name="x-circle"
                size="4" />
              {{ t('web.admin.customers.actions.unverify.button') }}
            </button>

            <!-- Suspend / unsuspend (reversible trust & safety pause).
                 Colonel accounts cannot be suspended (privilege guard); the
                 backend refuses too — hiding the block avoids a dead button. -->
            <div
              v-if="record.suspended || record.role !== 'colonel'"
              class="space-y-3 border-t border-gray-200 pt-4 dark:border-gray-800">
              <template v-if="!record.suspended">
                <template v-if="record.role !== 'colonel'">
                  <div>
                    <label
                      for="suspend-reason-input"
                      class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                      {{ t('web.admin.customers.actions.suspend.reasonLabel') }}
                    </label>
                    <input
                      id="suspend-reason-input"
                      v-model="suspendReason"
                      type="text"
                      maxlength="255"
                      data-testid="suspend-reason"
                      :placeholder="t('web.admin.customers.actions.suspend.reasonPlaceholder')"
                      class="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:placeholder:text-gray-500" />
                  </div>
                  <button
                    type="button"
                    data-testid="suspend-button"
                    class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                    @click="requestAction('suspend')">
                    <OIcon
                      collection="heroicons"
                      name="no-symbol"
                      size="4" />
                    {{ t('web.admin.customers.actions.suspend.button') }}
                  </button>
                </template>
              </template>
              <button
                v-else
                type="button"
                data-testid="unsuspend-button"
                class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
                @click="requestAction('unsuspend')">
                <OIcon
                  collection="heroicons"
                  name="arrow-uturn-left"
                  size="4" />
                {{ t('web.admin.customers.actions.unsuspend.button') }}
              </button>
            </div>

            <!-- Purge (destructive, typed-confirm) -->
            <div class="border-t border-gray-200 pt-4 dark:border-gray-800">
              <button
                type="button"
                data-testid="purge-button"
                class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                @click="requestAction('purge')">
                <OIcon
                  collection="heroicons"
                  name="trash"
                  size="4" />
                {{ t('web.admin.customers.actions.purge.button') }}
              </button>
            </div>
          </div>
        </section>
      </div>

      <!-- Billing ("why was I charged" — plan always renders from the model;
           the Stripe block degrades gracefully when unavailable). -->
      <section
        v-if="billing"
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="billing-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.customers.detail.sections.billing') }}
          </h3>
        </div>
        <dl class="grid grid-cols-1 gap-x-6 gap-y-4 px-6 py-5 sm:grid-cols-2">
          <div
            v-for="field in billingFields"
            :key="field.key"
            :data-testid="`billing-${field.key}`">
            <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ field.label }}
            </dt>
            <dd class="mt-1 text-sm break-words text-gray-900 dark:text-gray-100">
              {{ field.value }}
            </dd>
          </div>
        </dl>
        <div class="border-t border-gray-200 px-6 py-4 dark:border-gray-800">
          <!-- Deep link into the Stripe dashboard when the live read worked. -->
          <a
            v-if="billing.stripe.available && billing.stripe.dashboard_url"
            :href="billing.stripe.dashboard_url"
            target="_blank"
            rel="noopener noreferrer"
            data-testid="billing-stripe-link"
            class="inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-brand-400 dark:hover:text-brand-300">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              size="4" />
            {{ t('web.admin.customers.detail.billing.openStripe') }}
          </a>
          <!-- Graceful degradation: Stripe configured but unreachable / no identity. -->
          <p
            v-else-if="billing.enabled"
            class="text-sm text-gray-500 dark:text-gray-400"
            data-testid="billing-unavailable">
            {{
              t('web.admin.customers.detail.billing.unavailable', {
                reason: billing.stripe.reason ?? '',
              })
            }}
          </p>
          <p
            v-else
            class="text-sm text-gray-500 dark:text-gray-400"
            data-testid="billing-disabled">
            {{ t('web.admin.customers.detail.billing.notConfigured') }}
          </p>
        </div>
      </section>

      <!-- Secrets -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.customers.detail.sections.secrets') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400">({{ details.secrets.count }})</span>
          </h3>
        </div>
        <DataTable
          :columns="secretColumns"
          :rows="details.secrets.items"
          row-key="secret_id"
          :empty-text="t('web.admin.customers.detail.secrets.empty')"
          testid="secrets-table">
          <template #cell-created="{ row }">
            {{ formatDisplayDateTime(row.created) }}
          </template>
          <template #cell-expiration="{ row }">
            {{ row.expiration ? formatDisplayDateTime(row.expiration) : t('web.admin.customers.detail.never') }}
          </template>
        </DataTable>
      </section>

      <!-- Receipts -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.customers.detail.sections.receipts') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400">({{ details.receipts.count }})</span>
          </h3>
        </div>
        <DataTable
          :columns="receiptColumns"
          :rows="details.receipts.items"
          row-key="receipt_id"
          :empty-text="t('web.admin.customers.detail.receipts.empty')"
          testid="receipts-table">
          <template #cell-created="{ row }">
            {{ formatDisplayDateTime(row.created) }}
          </template>
        </DataTable>
      </section>

      <!-- Organizations -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.customers.detail.sections.organizations') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400">({{ details.organizations.length }})</span>
          </h3>
        </div>
        <ul
          v-if="details.organizations.length > 0"
          class="divide-y divide-gray-200 dark:divide-gray-800"
          data-testid="organizations-list">
          <li
            v-for="org in details.organizations"
            :key="org.organization_id"
            class="flex items-center justify-between px-6 py-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-gray-900 dark:text-gray-100">
                {{ org.display_name || t('web.admin.customers.detail.none') }}
              </p>
              <p class="truncate font-mono text-xs text-gray-400 dark:text-gray-500">
                {{ org.extid }}
              </p>
            </div>
            <span
              v-if="org.is_default"
              class="ml-3 shrink-0 rounded bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
              {{ t('web.admin.customers.detail.organizations.default') }}
            </span>
          </li>
        </ul>
        <p
          v-else
          class="px-6 py-8 text-center text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.customers.detail.organizations.empty') }}
        </p>
      </section>
    </div>

    <!-- Shared guarded-action dialog (typed-confirm for purge). -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="dialogConfig.title"
      :description="dialogConfig.description"
      :confirm-token="dialogConfig.confirmToken"
      :variant="dialogConfig.variant"
      :confirm-text="dialogConfig.confirmText"
      :loading="mutationLoading"
      :error="mutationError"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </div>
</template>
