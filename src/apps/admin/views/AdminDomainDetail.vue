<!-- src/apps/admin/views/AdminDomainDetail.vue -->

<script setup lang="ts">

  import AdminDomainDnsDetails from '@/apps/admin/components/AdminDomainDnsDetails.vue';
  import DomainConfigsSection from '@/apps/admin/components/domains/DomainConfigsSection.vue';
  import DomainProbeResult from '@/apps/admin/components/domains/DomainProbeResult.vue';
  import DomainStateBadge from '@/apps/admin/components/domains/DomainStateBadge.vue';
  import { AdminConfirmDialog, StatCard } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
  import type { ColonelDomainRemoveDetails } from '@/apps/admin/stores/useAdminDomains';
  import { colonelDomainDetailResponseSchema } from '@/schemas/api/internal/responses/colonel-domains';
  import type { ColonelDomainVerifyDetails } from '@/schemas/api/internal/responses/colonel-domains';
  import type {
    ColonelDomainProbeDetails,
    ColonelDomainRepairDetails,
    ColonelDomainTransferDetails,
  } from '@/schemas/api/internal/responses/colonel-domaintoolbox';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  /**
   * Domain detail — the custom-domains peer of AdminCustomerDetail.vue: one
   * record, a full read-out, and every per-domain operation the colonel API
   * exposes, each behind the console's standard guard.
   *
   * - Single-resource fetch via {@link useResourceFetch} against
   *   `GET /api/colonel/domains/:extid`, keyed by the domain's PUBLIC id.
   * - Read-out: identity + timestamps, verification/serving state, the owning
   *   organization (linked to its own detail page) and the DNS records the
   *   operator must publish ({@link AdminDomainDnsDetails}, reused verbatim from
   *   the list's attach panel).
   * - Operations, ALL driven through {@link useAdminDomains} so this page, the
   *   list and the Domain Toolbox share one implementation per verb:
   *     verify   — one-click confirm; the honest post-check state is reported.
   *     probe    — read-only HTTPS/TLS diagnostics, no confirmation.
   *     repair   — dry-run PREVIEW first, apply behind typed confirmation.
   *     transfer — dry-run PREVIEW first, apply behind typed confirmation.
   *     remove   — dry-run PREVIEW first, apply behind typed confirmation.
   *   `dry_run` defaults to TRUE server-side on repair/transfer/remove, so the
   *   preview is free and the apply must say `dry_run: false` explicitly.
   * - Audit is emitted SERVER-SIDE by each operation; nothing here logs it.
   */
  const props = defineProps<{
    /** The domain's public id (route param), forwarded from the router. */
    id: string;
  }>();

  const { t } = useI18n();
  const router = useRouter();
  const notifications = useNotificationsStore();
  const store = useAdminDomains();

  const publicId = computed(() => props.id);
  const domainUrl = (): string => `/api/colonel/domains/${encodeURIComponent(publicId.value)}`;

  const {
    data: domainData,
    loading: domainLoading,
    error: domainError,
    validationError: domainValidationError,
    notFound: domainNotFound,
    load: loadDomain,
    refresh: refreshDomain,
  } = useResourceFetch({
    url: domainUrl,
    schema: colonelDomainDetailResponseSchema,
    context: 'ColonelDomainDetailResponse',
  });

  const record = computed(() => domainData.value?.record ?? null);
  const cluster = computed(() => domainData.value?.details?.cluster ?? null);

  /** A non-404 network/HTTP failure, or a Zod contract mismatch. */
  const loadFailed = computed(
    () =>
      (domainError.value !== null && !domainNotFound.value) ||
      domainValidationError.value !== null
  );

  /** External URL so an operator can open the live domain in a new tab. */
  const externalUrl = computed(() =>
    record.value ? `https://${record.value.display_domain}` : ''
  );

  function yesNo(value: boolean | null | undefined): string {
    return value ? t('web.admin.domains.detail.yes') : t('web.admin.domains.detail.no');
  }

  // ---- Owning organization ---------------------------------------------------
  //
  // The detail endpoint returns the domain's safe_dump, which does NOT carry
  // org_id / org_name (they are not safe_dump fields on CustomDomain). The store
  // caches every list row it has seen, so arriving from the list gives us the
  // owner; a cold deep-link degrades to an explicit "unknown" note instead of a
  // wrong or empty value. The record fields are read first so this page picks
  // the owner up automatically if the endpoint ever starts sending it.

  const listRow = computed(() => store.rowFor(publicId.value));
  const orgId = computed(() => record.value?.org_id || listRow.value?.org_id || '');
  const orgName = computed(() => record.value?.org_name || listRow.value?.org_name || '');

  // ---- Read-out fields -------------------------------------------------------

  const overviewFields = computed(() => {
    const r = record.value;
    if (!r) return [];
    return [
      {
        key: 'publicId',
        label: t('web.admin.domains.fields.publicId'),
        value: r.extid,
        mono: true,
      },
      {
        key: 'domainId',
        label: t('web.admin.domains.fields.domainId'),
        value: r.domain_id,
        mono: true,
      },
      {
        key: 'baseDomain',
        label: t('web.admin.domains.fields.baseDomain'),
        value: r.base_domain || t('web.admin.domains.detail.none'),
        mono: true,
      },
      {
        key: 'subdomain',
        label: t('web.admin.domains.fields.subdomain'),
        value: r.subdomain || r.trd || t('web.admin.domains.detail.none'),
        mono: true,
      },
      {
        key: 'apex',
        label: t('web.admin.domains.fields.apex'),
        value: yesNo(r.is_apex),
        mono: false,
      },
      {
        key: 'status',
        label: t('web.admin.domains.fields.status'),
        value: r.status || t('web.admin.domains.detail.none'),
        mono: false,
      },
      {
        key: 'created',
        label: t('web.admin.domains.fields.created'),
        value: r.created
          ? formatDisplayDateTime(r.created)
          : t('web.admin.domains.detail.none'),
        mono: false,
      },
      {
        key: 'updated',
        label: t('web.admin.domains.fields.updated'),
        value: r.updated
          ? formatDisplayDateTime(r.updated)
          : t('web.admin.domains.detail.never'),
        mono: false,
      },
    ];
  });

  // ---- Probe (read-only, no confirmation) ------------------------------------

  const probeDetails = ref<ColonelDomainProbeDetails | null>(null);

  const {
    loading: probeLoading,
    error: probeError,
    run: runProbe,
    reset: resetProbe,
  } = useAdminMutation(async () => {
    probeDetails.value = await store.probe(publicId.value);
  });

  async function onProbe(): Promise<void> {
    resetProbe();
    probeDetails.value = null;
    await runProbe();
  }

  // ---- Repair (dry-run preview → typed-confirm apply) ------------------------

  const repairOrgId = ref('');
  const repairPlan = ref<ColonelDomainRepairDetails | null>(null);

  const {
    loading: repairPreviewLoading,
    error: repairPreviewError,
    run: runRepairPreview,
    reset: resetRepairPreview,
  } = useAdminMutation(async () => {
    repairPlan.value = await store.repair(publicId.value, {
      orgId: repairOrgId.value.trim() || undefined,
      dryRun: true,
    });
  });

  async function onRepairPreview(): Promise<void> {
    resetRepairPreview();
    repairPlan.value = null;
    await runRepairPreview();
  }

  /** Only offer the apply when the preview actually planned repairs. */
  const repairApplicable = computed(
    () => repairPlan.value?.status === 'planned' && (repairPlan.value?.issues.length ?? 0) > 0
  );

  // ---- Transfer (dry-run preview → typed-confirm apply) ----------------------

  const transferToOrg = ref('');
  const transferFromOrg = ref('');
  const transferPlan = ref<ColonelDomainTransferDetails | null>(null);

  const transferReady = computed(() => transferToOrg.value.trim() !== '');

  const {
    loading: transferPreviewLoading,
    error: transferPreviewError,
    run: runTransferPreview,
    reset: resetTransferPreview,
  } = useAdminMutation(async () => {
    transferPlan.value = await store.transfer(publicId.value, {
      toOrg: transferToOrg.value.trim(),
      fromOrg: transferFromOrg.value.trim() || undefined,
      dryRun: true,
    });
  });

  async function onTransferPreview(): Promise<void> {
    if (!transferReady.value) return;
    resetTransferPreview();
    transferPlan.value = null;
    await runTransferPreview();
  }

  const transferApplicable = computed(() => transferPlan.value?.status === 'planned');

  // ---- Remove (dry-run preview → typed-confirm apply) ------------------------

  const removePlan = ref<ColonelDomainRemoveDetails | null>(null);

  const {
    loading: removePreviewLoading,
    error: removePreviewError,
    run: runRemovePreview,
    reset: resetRemovePreview,
  } = useAdminMutation(async () => {
    removePlan.value = await store.remove(publicId.value, true);
  });

  async function onRemovePreview(): Promise<void> {
    resetRemovePreview();
    removePlan.value = null;
    await runRemovePreview();
  }

  /**
   * The apply button exists ONLY behind a preview that says `planned`, matching
   * repair and transfer. Without this gate the typed-confirm dialog opens cold:
   * the operator retypes the extid having never been told which org loses the
   * domain or whether a survivor row reasserts the display_domain index. The
   * server guard (`dry_run !== false`) keeps the apply honest, but honesty
   * about WHAT was destroyed is not the same as showing it first.
   *
   * Ops::Domains::Remove emits `planned` on every dry run and `removed` only on
   * an apply, so a `removed` status here means the ack drifted from the request
   * — not something to hand an apply button to.
   */
  const removeApplicable = computed(() => removePlan.value?.status === 'planned');

  /**
   * The identifier the server gates every applying domain verb on (#4326): the
   * domain's HOSTNAME, not the extid the URL already carries. The record is
   * loaded before any apply button exists, so the fallback is only reachable if
   * the read failed — in which case the call 403s and says what to send.
   */
  function applyConfirmToken(): string {
    return record.value?.display_domain ?? publicId.value;
  }

  // ---- The single guarded-action dialog --------------------------------------

  type ActionKey = 'verify' | 'repair' | 'transfer' | 'remove';

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);
  /** The last verify outcome, read in onConfirm to pick an honest message. */
  const verifyResult = ref<ColonelDomainVerifyDetails | null>(null);

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    switch (activeAction.value) {
      case 'verify':
        verifyResult.value = await store.verify(publicId.value);
        return;
      case 'repair':
        await store.repair(publicId.value, {
          orgId: repairOrgId.value.trim() || undefined,
          dryRun: false,
          confirm: applyConfirmToken(),
        });
        return;
      case 'transfer':
        await store.transfer(publicId.value, {
          toOrg: transferToOrg.value.trim(),
          fromOrg: transferFromOrg.value.trim() || undefined,
          dryRun: false,
          confirm: applyConfirmToken(),
        });
        return;
      case 'remove': {
        // The endpoint DEFAULTS dry_run to true and the false flag rides the
        // query string, so the ack must PROVE the apply happened: only
        // `details.dry_run === false` is a real removal. A missing/malformed
        // ack or a dry_run echo (query param lost to a proxy strip / backend
        // drift) means the server only PREVIEWED — reporting success would
        // toast "removed", drop the cached row and navigate away while the
        // domain still exists.
        const removeAck = await store.remove(publicId.value, false, applyConfirmToken());
        if (!removeAck || removeAck.dry_run !== false) {
          throw new Error(t('web.admin.domains.actions.remove.notApplied'));
        }
        return;
      }
      default:
        throw new Error('No active action');
    }
  });

  /** Repair, transfer and remove all rewrite or destroy ownership state. */
  const DANGER_ACTIONS: readonly ActionKey[] = ['repair', 'transfer', 'remove'];

  /**
   * i18n root per action. Verify points at the SHARED `verify.*` subtree the
   * list screen already uses, so the two surfaces never drift into two wordings
   * of the same confirmation.
   */
  const ACTION_I18N_ROOT: Record<ActionKey, string> = {
    verify: 'web.admin.domains.verify',
    repair: 'web.admin.domains.actions.repair',
    transfer: 'web.admin.domains.actions.transfer',
    remove: 'web.admin.domains.actions.remove',
  };

  const dialogConfig = computed(() => {
    const action = activeAction.value;
    if (!action) {
      return {
        title: '',
        description: undefined as string | undefined,
        confirmToken: undefined as string | undefined,
        variant: 'default' as const,
        confirmText: undefined as string | undefined,
      };
    }

    const root = ACTION_I18N_ROOT[action];
    const isDanger = DANGER_ACTIONS.includes(action);
    const args: Record<string, string> = {
      domain: record.value?.display_domain ?? publicId.value,
      org: transferToOrg.value.trim(),
    };
    return {
      title: t(`${root}.confirmTitle`),
      description: t(`${root}.confirmDescription`, args),
      // Typed-confirmation gate: retype the domain's public id, matching the
      // console convention (AdminCustomerDetail, Domain Toolbox).
      confirmToken: isDanger ? publicId.value : undefined,
      variant: isDanger ? ('danger' as const) : ('default' as const),
      confirmText: t(`${root}.button`),
    };
  });

  function requestAction(key: ActionKey): void {
    activeAction.value = key;
    resetMutation();
    dialogOpen.value = true;
  }

  /** Per-state operator notification for verify. Unknown states fall back. */
  const VERIFY_MESSAGE_KEYS: Record<string, string> = {
    verified: 'web.admin.domains.verify.success.verified',
    resolving: 'web.admin.domains.verify.success.resolving',
    pending: 'web.admin.domains.verify.success.pending',
    unverified: 'web.admin.domains.verify.success.unverified',
  };

  function notifyVerifyOutcome(): void {
    const state = verifyResult.value?.current_state ?? '';
    const messageKey = VERIFY_MESSAGE_KEYS[state] ?? 'web.admin.domains.verify.success.done';
    notifications.show(
      t(messageKey, { domain: record.value?.display_domain ?? publicId.value }),
      state === 'verified' ? 'success' : 'info'
    );
  }

  async function onConfirm(): Promise<void> {
    const action = activeAction.value;
    if (!action) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;

    if (action === 'verify') {
      notifyVerifyOutcome();
      verifyResult.value = null;
    } else {
      notifications.show(t(`${ACTION_I18N_ROOT[action]}.success`), 'success');
    }

    if (action === 'remove') {
      // The record no longer exists — drop the cached row and return to the list.
      store.forget(publicId.value);
      activeAction.value = null;
      router.push({ name: 'AdminDomains' });
      return;
    }

    // The plans described the pre-mutation world; clear them before refreshing.
    repairPlan.value = null;
    transferPlan.value = null;
    removePlan.value = null;
    await refreshDomain().catch(() => {});
    activeAction.value = null;
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    resetMutation();
  }

  // ---- Override verification status (inline form) ----------------------------

  const overrideOpen = ref(false);
  const overrideVerified = ref<boolean | null>(null);
  const overrideResolving = ref<boolean | null>(null);

  const {
    loading: overrideLoading,
    error: overrideError,
    run: runOverride,
    reset: resetOverride,
  } = useAdminMutation(async () => {
    const r = record.value;
    if (!r) return;

    const options: { verified?: boolean; resolving?: boolean } = {};
    if (overrideVerified.value !== null && overrideVerified.value !== r.verified) {
      options.verified = overrideVerified.value;
    }
    if (overrideResolving.value !== null && overrideResolving.value !== r.resolving) {
      options.resolving = overrideResolving.value;
    }

    if (Object.keys(options).length === 0) {
      notifications.show(t('web.admin.domains.override.noChange'), 'info');
      return;
    }

    await store.override(publicId.value, { ...options, confirm: applyConfirmToken() });
  });

  function openOverride(): void {
    if (!record.value) return;
    overrideVerified.value = record.value.verified;
    overrideResolving.value = record.value.resolving;
    resetOverride();
    overrideOpen.value = true;
  }

  function closeOverride(): void {
    overrideOpen.value = false;
    overrideVerified.value = null;
    overrideResolving.value = null;
  }

  async function applyOverride(): Promise<void> {
    const ok = await runOverride();
    if (!ok) return;

    closeOverride();
    notifications.show(t('web.admin.domains.override.success'), 'success');
    await refreshDomain().catch(() => {});
  }

  function goBack(): void {
    router.push({ name: 'AdminDomains' });
  }

  onMounted(() => {
    loadDomain().catch(() => {});
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
      {{ t('web.admin.domains.detail.backToList') }}
    </button>

    <!-- Loading -->
    <div
      v-if="domainLoading && !record"
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
      v-else-if="domainNotFound"
      class="rounded-lg border border-gray-200 bg-white px-6 py-16 text-center dark:border-gray-800 dark:bg-gray-900"
      data-testid="detail-not-found">
      <OIcon
        collection="heroicons"
        name="globe-alt"
        size="8"
        class="mx-auto text-gray-400 dark:text-gray-600" />
      <h3 class="mt-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.domains.detail.notFound') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domains.detail.notFoundDescription') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="goBack">
        {{ t('web.admin.domains.detail.backToList') }}
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
        {{ t('web.admin.domains.detail.loadError') }}
      </p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadDomain().catch(() => {})">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.domains.detail.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else-if="record"
      class="space-y-6"
      data-testid="detail-content">
      <!-- Header -->
      <div class="flex flex-wrap items-center gap-3 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ record.display_domain }}
        </h2>
        <DomainStateBadge
          :state="record.verification_state"
          testid="detail-state-badge" />
        <span
          v-if="record.ready"
          class="inline-flex items-center gap-1 rounded bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/40 dark:text-green-200"
          data-testid="detail-ready-badge">
          <OIcon
            collection="heroicons"
            name="check-badge"
            size="3" />
          {{ t('web.admin.domains.tls.serving') }}
        </span>
        <a
          :href="externalUrl"
          target="_blank"
          rel="noopener noreferrer"
          data-testid="detail-open-external"
          :aria-label="t('web.admin.domains.attach.openExternal', { domain: record.display_domain })"
          :title="t('web.admin.domains.attach.openExternal', { domain: record.display_domain })"
          class="rounded text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400">
          <OIcon
            collection="heroicons"
            name="arrow-top-right-on-square"
            size="4" />
        </a>
        <span class="font-mono text-xs text-gray-400 dark:text-gray-500">{{ record.extid }}</span>
      </div>

      <!-- Stat tiles -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard
          :label="t('web.admin.domains.columns.state')"
          :value="t(`web.colonel.customDomains.status.${record.verification_state}`, record.verification_state)"
          icon="shield-check"
          testid="stat-state" />
        <StatCard
          :label="t('web.admin.domains.fields.verified')"
          :value="yesNo(record.verified)"
          icon="check-circle"
          testid="stat-verified" />
        <StatCard
          :label="t('web.admin.domains.fields.resolving')"
          :value="yesNo(record.resolving)"
          icon="signal"
          testid="stat-resolving" />
        <StatCard
          :label="t('web.admin.domains.fields.ready')"
          :value="yesNo(record.ready)"
          icon="check-badge"
          testid="stat-ready" />
      </div>

      <!-- Override status inline form -->
      <div
        v-if="overrideOpen"
        class="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950"
        data-testid="override-form">
        <h4 class="mb-3 text-sm font-medium text-amber-900 dark:text-amber-100">
          {{ t('web.admin.domains.override.title') }}
        </h4>
        <p class="mb-4 text-xs text-amber-700 dark:text-amber-300">
          {{ t('web.admin.domains.override.description') }}
        </p>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input
              v-model="overrideVerified"
              type="checkbox"
              :true-value="true"
              :false-value="false"
              class="h-4 w-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800" />
            {{ t('web.admin.domains.override.verified') }}
          </label>
          <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input
              v-model="overrideResolving"
              type="checkbox"
              :true-value="true"
              :false-value="false"
              class="h-4 w-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800" />
            {{ t('web.admin.domains.override.resolving') }}
          </label>
        </div>
        <p
          v-if="overrideError"
          class="mt-2 text-sm text-red-700 dark:text-red-300"
          role="alert">
          {{ overrideError }}
        </p>
        <div class="mt-4 flex gap-2">
          <button
            type="button"
            data-testid="override-apply"
            :disabled="overrideLoading"
            class="inline-flex items-center gap-1 rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 focus:ring-2 focus:ring-amber-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
            @click="applyOverride">
            <OIcon
              v-if="overrideLoading"
              collection="heroicons"
              name="arrow-path"
              size="4"
              class="animate-spin" />
            {{ t('web.admin.domains.override.apply') }}
          </button>
          <button
            type="button"
            data-testid="override-cancel"
            :disabled="overrideLoading"
            class="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="closeOverride">
            {{ t('web.admin.domains.override.cancel') }}
          </button>
        </div>
      </div>

      <!-- Override trigger button (when form is closed) -->
      <div
        v-if="!overrideOpen"
        class="flex justify-end">
        <button
          type="button"
          data-testid="override-button"
          class="inline-flex items-center gap-1.5 rounded-md border border-amber-300 px-3 py-1.5 text-sm font-medium text-amber-700 hover:bg-amber-50 focus:ring-2 focus:ring-amber-500 focus:outline-none dark:border-amber-600 dark:text-amber-300 dark:hover:bg-amber-950"
          @click="openOverride">
          <OIcon
            collection="heroicons"
            name="adjustments-horizontal"
            size="4" />
          {{ t('web.admin.domains.override.button') }}
        </button>
      </div>

      <!-- Overview + Actions -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <!-- Overview -->
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm lg:col-span-2 dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.domains.detail.sections.overview') }}
            </h3>
          </div>
          <dl class="grid grid-cols-1 gap-x-6 gap-y-4 px-6 py-5 sm:grid-cols-2">
            <div
              v-for="field in overviewFields"
              :key="field.key"
              :data-testid="`profile-${field.key}`">
              <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd
                :class="[
                  'mt-1 text-sm break-words text-gray-900 dark:text-gray-100',
                  field.mono ? 'font-mono tabular-nums' : '',
                ]">
                {{ field.value }}
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
              {{ t('web.admin.domains.detail.sections.actions') }}
            </h3>
          </div>
          <div class="space-y-4 px-6 py-5">
            <!-- Verify (reversible, one-click confirm) -->
            <button
              type="button"
              data-testid="verify-button"
              class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
              @click="requestAction('verify')">
              <OIcon
                collection="heroicons"
                name="shield-check"
                size="4" />
              {{ t('web.admin.domains.verify.button') }}
            </button>

            <!-- Probe (read-only: reaches the network, changes nothing) -->
            <button
              type="button"
              data-testid="probe-button"
              :disabled="probeLoading"
              class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
              @click="onProbe">
              <OIcon
                collection="heroicons"
                :name="probeLoading ? 'arrow-path' : 'signal'"
                size="4"
                :class="probeLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
              {{ t('web.admin.domains.actions.probe.button') }}
            </button>
            <p
              v-if="probeError"
              class="text-sm text-red-700 dark:text-red-300"
              role="alert"
              data-testid="probe-error">
              {{ probeError }}
            </p>

            <!-- Remove (destructive, typed-confirm). Preview first: the endpoint
                 dry-runs by default, so this costs nothing and names the org
                 that is about to lose the domain. -->
            <div class="space-y-3 border-t border-gray-200 pt-4 dark:border-gray-800">
              <button
                type="button"
                data-testid="remove-preview"
                :disabled="removePreviewLoading"
                class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
                @click="onRemovePreview">
                {{ t('web.admin.domains.actions.remove.previewButton') }}
              </button>
              <p
                v-if="removePreviewError"
                class="text-sm text-red-700 dark:text-red-300"
                role="alert"
                data-testid="remove-preview-error">
                {{ removePreviewError }}
              </p>
              <div
                v-if="removePlan"
                class="rounded-md bg-gray-50 px-3 py-2 text-xs text-gray-700 dark:bg-gray-800 dark:text-gray-300"
                data-testid="remove-plan">
                <p>
                  {{ t('web.admin.domains.actions.remove.previewStatus') }}
                  <span class="font-mono font-medium">{{ removePlan.status }}</span>
                </p>
                <p class="mt-1">
                  {{ t('web.admin.domains.actions.remove.previewOrg') }}
                  <span class="font-medium">{{
                    removePlan.org_name || removePlan.org_id || t('web.admin.domains.detail.none')
                  }}</span>
                </p>
                <p
                  v-if="removePlan.reasserts_survivor"
                  class="mt-1 text-amber-700 dark:text-amber-400"
                  data-testid="remove-reasserts">
                  {{ t('web.admin.domains.actions.remove.reassertsSurvivor') }}
                </p>
              </div>
              <button
                v-if="removeApplicable"
                type="button"
                data-testid="remove-button"
                class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
                @click="requestAction('remove')">
                <OIcon
                  collection="heroicons"
                  name="trash"
                  size="4" />
                {{ t('web.admin.domains.actions.remove.button') }}
              </button>
            </div>
          </div>
        </section>
      </div>

      <!-- Owning organization -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="organization-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.domains.detail.sections.organization') }}
          </h3>
        </div>
        <div class="px-6 py-5">
          <div
            v-if="orgId"
            class="flex flex-wrap items-center justify-between gap-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-gray-900 dark:text-gray-100">
                {{ orgName || t('web.admin.domains.detail.none') }}
              </p>
              <p class="truncate font-mono text-xs text-gray-400 dark:text-gray-500">
                {{ orgId }}
              </p>
            </div>
            <router-link
              :to="{ name: 'AdminOrganizationDetail', params: { id: orgId } }"
              data-testid="organization-link"
              class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800">
              {{ t('web.admin.domains.detail.organization.open') }}
              <OIcon
                collection="heroicons"
                name="arrow-right"
                size="4" />
            </router-link>
          </div>
          <p
            v-else
            class="text-sm text-gray-500 dark:text-gray-400"
            data-testid="organization-unknown">
            {{ t('web.admin.domains.detail.organization.unknown') }}
          </p>
        </div>
      </section>

      <!-- Per-domain config records (signin/signup/homepage/api/incoming/sso/mailer) -->
      <DomainConfigsSection
        :extid="publicId"
        :display-domain="record.display_domain" />

      <!-- DNS records to publish (same component the attach panel uses) -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="dns-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.domains.detail.sections.dns') }}
          </h3>
        </div>
        <div class="px-6 py-5">
          <AdminDomainDnsDetails
            :record="record"
            :cluster="cluster" />
        </div>
      </section>

      <!-- Diagnostics (probe result) -->
      <section
        v-if="probeDetails"
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="probe-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.domains.detail.sections.diagnostics') }}
          </h3>
        </div>
        <div class="px-6 py-5">
          <DomainProbeResult
            :details="probeDetails"
            :domain="record.display_domain" />
        </div>
      </section>

      <!-- Ownership operations: repair + transfer. Both preview first. -->
      <section
        class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="operations-section">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.domains.detail.sections.operations') }}
          </h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domains.detail.sections.operationsHint') }}
          </p>
        </div>

        <!-- Repair -->
        <div
          class="border-b border-gray-200 px-6 py-5 dark:border-gray-800"
          data-testid="repair-block">
          <h4 class="text-sm font-semibold text-gray-900 dark:text-white">
            {{ t('web.admin.domains.actions.repair.title') }}
          </h4>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domains.actions.repair.description') }}
          </p>

          <div class="mt-3 flex flex-wrap items-end gap-3">
            <div class="min-w-[16rem] flex-1">
              <label
                for="domain-repair-orgid"
                class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.admin.domains.actions.repair.orgIdLabel') }}
              </label>
              <input
                id="domain-repair-orgid"
                v-model="repairOrgId"
                type="text"
                data-testid="repair-orgid-input"
                :placeholder="t('web.admin.domains.actions.repair.orgIdPlaceholder')"
                class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
            </div>
            <button
              type="button"
              data-testid="repair-preview"
              :disabled="repairPreviewLoading"
              class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              @click="onRepairPreview">
              {{ t('web.admin.domains.actions.preview') }}
            </button>
          </div>

          <p
            v-if="repairPreviewError"
            class="mt-3 text-sm text-red-700 dark:text-red-300"
            role="alert"
            data-testid="repair-preview-error">
            {{ repairPreviewError }}
          </p>

          <div
            v-if="repairPlan"
            class="mt-4"
            data-testid="repair-plan">
            <p class="mb-2 text-sm text-gray-700 dark:text-gray-300">
              {{ t('web.admin.domains.actions.repair.statusLabel') }}
              <span
                class="font-mono font-medium"
                data-testid="repair-status">{{ repairPlan.status }}</span>
            </p>
            <ul
              v-if="repairPlan.issues.length"
              class="ml-4 list-disc space-y-1 text-sm text-gray-700 dark:text-gray-300">
              <li
                v-for="(issue, index) in repairPlan.issues"
                :key="index">
                {{ issue }}
              </li>
            </ul>
            <p
              v-else
              class="text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.admin.domains.actions.repair.noIssues') }}
            </p>

            <button
              v-if="repairApplicable"
              type="button"
              data-testid="repair-apply"
              class="mt-4 inline-flex items-center gap-1 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 focus:ring-2 focus:ring-amber-500 focus:outline-none"
              @click="requestAction('repair')">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth"
                size="4" />
              {{ t('web.admin.domains.actions.repair.button') }}
            </button>
          </div>
        </div>

        <!-- Transfer -->
        <div
          class="px-6 py-5"
          data-testid="transfer-block">
          <h4 class="text-sm font-semibold text-gray-900 dark:text-white">
            {{ t('web.admin.domains.actions.transfer.title') }}
          </h4>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domains.actions.transfer.description') }}
          </p>

          <div class="mt-3 grid gap-3 sm:grid-cols-2">
            <div>
              <label
                for="domain-transfer-to"
                class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.admin.domains.actions.transfer.toOrgLabel') }}
              </label>
              <input
                id="domain-transfer-to"
                v-model="transferToOrg"
                type="text"
                data-testid="transfer-toorg-input"
                class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
            </div>
            <div>
              <label
                for="domain-transfer-from"
                class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.admin.domains.actions.transfer.fromOrgLabel') }}
              </label>
              <input
                id="domain-transfer-from"
                v-model="transferFromOrg"
                type="text"
                data-testid="transfer-fromorg-input"
                :placeholder="t('web.admin.domains.actions.transfer.fromOrgPlaceholder')"
                class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
            </div>
          </div>

          <button
            type="button"
            data-testid="transfer-preview"
            :disabled="!transferReady || transferPreviewLoading"
            class="mt-3 inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
            @click="onTransferPreview">
            {{ t('web.admin.domains.actions.preview') }}
          </button>

          <p
            v-if="transferPreviewError"
            class="mt-3 text-sm text-red-700 dark:text-red-300"
            role="alert"
            data-testid="transfer-preview-error">
            {{ transferPreviewError }}
          </p>

          <div
            v-if="transferPlan"
            class="mt-4 text-sm"
            data-testid="transfer-plan">
            <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt class="text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.domains.actions.transfer.from') }}
                </dt>
                <dd class="font-mono text-gray-900 dark:text-white">
                  {{
                    transferPlan.from_org_id
                      ? `${transferPlan.from_org_name || '—'} (${transferPlan.from_org_id})`
                      : t('web.admin.domains.actions.transfer.orphaned')
                  }}
                </dd>
              </div>
              <div>
                <dt class="text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.domains.actions.transfer.to') }}
                </dt>
                <dd class="font-mono text-gray-900 dark:text-white">
                  {{ transferPlan.to_org_name || '—' }} ({{ transferPlan.to_org_id }})
                </dd>
              </div>
            </dl>

            <button
              v-if="transferApplicable"
              type="button"
              data-testid="transfer-apply"
              class="mt-4 inline-flex items-center gap-1 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 focus:ring-2 focus:ring-amber-500 focus:outline-none"
              @click="requestAction('transfer')">
              <OIcon
                collection="heroicons"
                name="arrow-right"
                size="4" />
              {{ t('web.admin.domains.actions.transfer.button') }}
            </button>
          </div>
        </div>
      </section>
    </div>

    <!-- Shared guarded-action dialog (typed-confirm for repair/transfer/remove). -->
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
