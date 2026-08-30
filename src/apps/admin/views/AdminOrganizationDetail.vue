<!-- src/apps/admin/views/AdminOrganizationDetail.vue -->

<script setup lang="ts">
  import AdminCheckoutLinkModal from '@/apps/admin/components/AdminCheckoutLinkModal.vue';
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { AdminConfirmDialog, DataTable, JsonViewer, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import AddMemberModal from '@/apps/admin/components/organizations/AddMemberModal.vue';
  import EntitlementMatrix from '@/apps/admin/components/organizations/EntitlementMatrix.vue';
  import EntitlementPicker from '@/apps/admin/components/organizations/EntitlementPicker.vue';
  import type { AddMembershipRequest } from '@/apps/admin/components/organizations/membershipSchemas';
  import { colonelAddMembershipResponseSchema } from '@/apps/admin/components/organizations/membershipSchemas';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type { InvestigateOrganizationResult } from '@/schemas/api/internal/responses/colonel';
  import {
    colonelAvailablePlansResponseSchema,
    investigateOrganizationResponseSchema,
  } from '@/schemas/api/internal/responses/colonel';
  import type {
    ColonelDeleteOrganizationDetails,
    ColonelOrganizationDetailDomain,
    ColonelOrganizationDetailMember,
    ColonelReconcileOrganizationRecord,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import {
    colonelDeleteOrganizationResponseSchema,
    colonelEntitlementOverrideResponseSchema,
    colonelOrganizationDetailResponseSchema,
    colonelReconcileOrganizationResponseSchema,
    colonelUpdateOrganizationPlanResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import { classifyError } from '@/schemas/errors';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { getPlanLabel } from '@/types/billing';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref, watch } from 'vue';
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
  const checkoutLinkOpen = ref(false);

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
        value: r.created
          ? formatDisplayDateTime(r.created)
          : t('web.admin.organizations.detail.none'),
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

  // ---- Plan change (MUTATING — catalog-validated + audited server-side) ------
  //
  // The plan control moved here from the customer detail page: the billing
  // relationship (Stripe ids, subscription state, the entitlement engine) lives
  // on the Organization, so the org is what a plan change operates on.
  // POST /organizations/:org_id/plan writes planid AND re-materializes
  // entitlements from the new plan server-side.

  // The endpoint returns a BARE { plans, source } body (no record/details
  // envelope), so the schema is a plain object, not createApiResponseSchema.
  // Loaded once on mount; the list is site-wide, not per-org.
  const { data: plansData, load: loadPlans } = useResourceFetch({
    url: '/api/colonel/available-plans',
    schema: colonelAvailablePlansResponseSchema,
    context: 'ColonelAvailablePlansResponse',
  });

  const availablePlans = computed(() => plansData.value?.plans ?? []);
  /** True when plans came from billing.yaml (Stripe unconfigured/unreachable). */
  const plansFromLocalConfig = computed(() => plansData.value?.source === 'local_config');

  /**
   * Selectable plan ids, sorted by display_order then name. The org's current
   * planid is always included (prepended) even if the catalog no longer lists
   * it, so a legacy plan still renders as the selected option.
   */
  const planOptions = computed(() => {
    const options = [...availablePlans.value]
      .sort(
        (a, b) => (a.display_order ?? 0) - (b.display_order ?? 0) || a.name.localeCompare(b.name)
      )
      .map((p) => ({ planid: p.planid, label: `${p.name} (${p.planid})` }));
    const current = record.value?.planid;
    if (current && !options.some((o) => o.planid === current)) {
      options.unshift({ planid: current, label: current });
    }
    return options;
  });

  /** Plan selector value; synced to the loaded record's planid. */
  const pendingPlan = ref('');
  watch(
    record,
    (value) => {
      pendingPlan.value = value?.planid ?? '';
    },
    { immediate: true }
  );

  const planDialogOpen = ref(false);
  /** Server-side heads-up (live Stripe subscription may overwrite the change). */
  const planChangeWarning = ref<string | null>(null);
  /**
   * Server message when the planid wrote but entitlement state may not match
   * the new plan (`details.entitlements_ok: false` — failed/absent
   * materialization, or a partial/unobserved membership cascade). The org or
   * some members keep the OLD plan's entitlements in that state, so it must
   * surface as an error, never the success toast.
   */
  const planChangeProblem = ref<string | null>(null);

  const {
    loading: planLoading,
    error: planError,
    run: runPlanMutation,
    reset: resetPlanMutation,
  } = useAdminMutation(async () => {
    const response = await $api.post(`${orgUrl()}/plan`, { planid: pendingPlan.value });
    const parsed = gracefulParse(
      colonelUpdateOrganizationPlanResponseSchema,
      response.data,
      'ColonelUpdateOrganizationPlanResponse'
    );
    // Ack drift is non-fatal: an unparseable 2xx is still a success, it just
    // loses the Stripe-overwrite warning / materialization signal.
    planChangeWarning.value = parsed.ok ? (parsed.data.details?.warning ?? null) : null;
    planChangeProblem.value =
      parsed.ok && parsed.data.details?.entitlements_ok === false
        ? (parsed.data.details?.message ?? t('web.admin.organizations.actions.plan.problem'))
        : null;
  });

  function requestChangePlan(): void {
    // No-op guard: ignore if the plan is unchanged (nothing to confirm).
    if (!pendingPlan.value || pendingPlan.value === record.value?.planid) return;
    resetPlanMutation();
    planChangeWarning.value = null;
    planChangeProblem.value = null;
    planDialogOpen.value = true;
  }

  async function onPlanConfirm(): Promise<void> {
    const ok = await runPlanMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    planDialogOpen.value = false;
    if (planChangeProblem.value) {
      // Planid wrote but entitlements did NOT re-materialize: the server's
      // message says what to do (reconcile / pick a cataloged plan).
      notifications.show(planChangeProblem.value, 'error');
    } else {
      notifications.show(t('web.admin.organizations.actions.plan.success'), 'success');
    }
    // The server's own warning text (Stripe-linked orgs) — worth a second toast.
    if (planChangeWarning.value) notifications.show(planChangeWarning.value, 'info');
    // Refresh so billing + entitlements reflect the new plan.
    await refreshOrg().catch(() => {});
  }

  function onPlanCancel(): void {
    planDialogOpen.value = false;
    resetPlanMutation();
  }

  // ---- Entitlement read-out (matrix lives in EntitlementMatrix.vue) ----------

  const drift = computed(() => entitlements.value?.drift ?? null);
  const inSync = computed(() => drift.value?.in_sync ?? true);
  const planStale = computed(() => entitlements.value?.plan_stale === true);

  // ---- Entitlement overrides (MUTATING — guarded + audited server-side) ------

  type EntitlementAction = 'grant' | 'revoke' | 'clear';

  /**
   * The billing catalog, straight off the detail payload. Empty means the
   * catalog could not be read — NOT that nothing is grantable — so every
   * catalog-membership check below fails OPEN, matching the server predicate
   * (`EntitlementOverride.known_entitlement?` returns true when the catalog is
   * unavailable).
   */
  const availableEntitlements = computed(() => details.value?.available_entitlements ?? []);

  const entitlementInput = ref('');
  /**
   * Bumped after a clear-all so the picker remounts fresh. Without it an
   * operator who used the out-of-catalog path stays stuck in free text after
   * the overrides are wiped, with no obvious way back to the dropdown.
   */
  const entitlementPickerKey = ref(0);

  /**
   * Provably not in the catalog. The CLI warns and proceeds in exactly this
   * case (`warn_unknown_entitlement`), so the console does too: warn inline,
   * repeat it in the confirm dialog, block nothing.
   */
  const entitlementOutOfCatalog = computed(() => {
    const name = entitlementInput.value.trim();
    if (name.length === 0 || availableEntitlements.value.length === 0) return false;
    return !availableEntitlements.value.some((option) => option.name === name);
  });

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

  /**
   * The CLI's out-of-catalog warning, appended to the confirm copy so the last
   * screen before the write says the same thing the terminal would.
   */
  function withCatalogWarning(description: string): string {
    if (!entitlementOutOfCatalog.value) return description;
    return `${description} ${t('web.admin.organizations.entitlements.catalogWarning', {
      entitlement: pendingEntitlement.value,
    })}`;
  }

  const entitlementDialogConfig = computed(() => {
    const name = heading.value;
    const token = record.value?.extid; // typed-confirmation: retype the public id.
    switch (activeEntitlementAction.value) {
      case 'grant':
        return {
          title: t('web.admin.organizations.entitlements.confirm.grantTitle'),
          description: withCatalogWarning(
            t('web.admin.organizations.entitlements.confirm.grantDescription', {
              entitlement: pendingEntitlement.value,
              org: name,
            })
          ),
          confirmToken: token,
          variant: 'default' as const,
          confirmText: t('web.admin.organizations.entitlements.grant'),
        };
      case 'revoke':
        return {
          title: t('web.admin.organizations.entitlements.confirm.revokeTitle'),
          description: withCatalogWarning(
            t('web.admin.organizations.entitlements.confirm.revokeDescription', {
              entitlement: pendingEntitlement.value,
              org: name,
            })
          ),
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
    if (action === 'clear') {
      entitlementInput.value = '';
      entitlementPickerKey.value += 1;
    }
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

  // Membership-cascade outcome (#3907 item 3). The applied paths return
  // `reason: null`, so this is the ONLY console-visible signal that a
  // reconcile left memberships with stale entitlements (`failed_ids` are the
  // membership objids `bin/ots memberships doctor` follow-up works in).
  const reconcileCascade = computed(() => reconcileResult.value?.memberships ?? null);

  const reconcileDiffRows = computed(() => {
    const r = reconcileResult.value;
    // `after` is null on dry runs / Stripe errors (schema-nullable since
    // #3937); the adapter never sends those today, but the diff needs both
    // snapshots either way.
    if (!r || !r.after) return [];
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

  // ---- Delete (IRREVERSIBLE — preview, then a typed-confirmation apply) -----
  //
  // Console peer of `bin/ots org delete` (#4204), over the same
  // `Onetime::Operations::Org::Delete` op. Support's actual case — "customer
  // has two orgs, delete the free one" — previously had NO operator path: the
  // customer-facing UI hides the button for a default workspace and 403s
  // without a materialised `manage_org`, and the alternative was a hand-run
  // `bin/console destroy!` that leaves the org in `Organization.instances`,
  // mails nobody, and leaves `default_org_id` pointing at a dead org.
  //
  // TWO requests, always in this order:
  //
  //   1. PREVIEW — `dry_run=true`. The endpoint already defaults to a dry run;
  //      we send it explicitly so a future default change cannot silently turn
  //      a preview into a delete. It returns the plan the operator confirms
  //      against (members + emails, invitations, domains, plan, owner, and the
  //      `default_org_id` rows the delete repairs) plus the guardrail that
  //      would block an apply.
  //   2. APPLY — `dry_run=false`, only after the operator retypes the extid.
  //
  // `record.deleted` is the ONLY thing treated as proof of deletion: the
  // preview also answers 200, and a 200 there means "here is what would
  // happen", not "it is gone".

  /** Guardrail statuses the server refuses an APPLY on (the op's vocabulary). */
  const DELETE_BLOCKING_STATUSES: readonly string[] = [
    'has_domains',
    // Domains that still point at the org but have fallen out of its
    // collection. Like `last_org` there is NO override — the repair is
    // operator-side (`bin/ots domains doctor --all --repair`), so the dialog's job is
    // to name the domains that need it.
    'drifted_domains',
    'is_default',
    'active_subscription',
    'last_org',
  ];

  const deleteDialogOpen = ref(false);
  const deletePlan = ref<ColonelDeleteOrganizationDetails | null>(null);
  const deleteStatus = ref<string | null>(null);
  /** Each override unlocks exactly ONE guard; both are operator-only. */
  const forceDefault = ref(false);
  const forceSubscription = ref(false);

  function deleteUrl(dryRun: boolean): string {
    // Query string, not a request body: DELETE bodies are not reliably parsed
    // across this stack (same reason the domain-remove call does it).
    const params = new URLSearchParams({
      dry_run: String(dryRun),
      force_default: String(forceDefault.value),
      force_subscription: String(forceSubscription.value),
    });
    return `${orgUrl()}?${params.toString()}`;
  }

  /**
   * Monotonic issue number for previews. Toggling an override re-plans while
   * the previous preview can still be in flight, and the requests carry no
   * version: without this, an earlier response arriving late would overwrite
   * the plan and verdict with answers for override state it never saw. Only
   * the newest issue may write state or surface an error.
   */
  let deletePreviewIssue = 0;

  const {
    loading: deletePreviewLoading,
    error: deletePreviewError,
    run: runDeletePreview,
  } = useAdminMutation(async () => {
    const issue = ++deletePreviewIssue;
    let response;
    try {
      response = await $api.delete(deleteUrl(true));
    } catch (err) {
      // A superseded preview's failure is moot — the newest one answers for
      // the current overrides, and its error (if any) is the one to show.
      if (issue !== deletePreviewIssue) return;
      throw err;
    }
    if (issue !== deletePreviewIssue) return; // superseded — the newest owns the state

    const parsed = gracefulParse(
      colonelDeleteOrganizationResponseSchema,
      response.data,
      'ColonelDeleteOrganizationResponse'
    );
    // Ack drift is non-fatal elsewhere, but this payload IS the confirmation:
    // refusing to open a destroy dialog we cannot describe is the whole point.
    if (!parsed.ok || !parsed.data.details) {
      throw new Error(t('web.admin.organizations.detail.delete.errors.planUnreadable'));
    }
    deletePlan.value = parsed.data.details;
    deleteStatus.value = parsed.data.record.status;
  });

  /**
   * Names when the server could load them, the raw count when it could not: a
   * stale entry in the domains collection still blocks the delete but has no
   * name to print.
   */
  const domainSummary = computed(() => {
    const plan = deletePlan.value;
    if (!plan || plan.domain_count === 0) return '';
    return plan.domains.length ? plan.domains.join(', ') : String(plan.domain_count);
  });

  /**
   * Domains that still name this org in the domain index but are MISSING from
   * its own collection, so they appear nowhere else on this screen (not in
   * `domains`, not in `domain_count`). This list is the operator's only view of
   * what `bin/ots domains doctor --all --repair` has to fix.
   */
  const driftedDomains = computed<string[]>(() => deletePlan.value?.drifted_domains ?? []);

  /**
   * Names when the server sent them. A `drifted_domains` verdict with an empty
   * list means the payload predates the field — say the delete is blocked on
   * drift and send the operator to the doctor rather than printing nothing.
   */
  const driftedSummary = computed(() =>
    driftedDomains.value.length
      ? driftedDomains.value.join(', ')
      : t('web.admin.organizations.detail.none')
  );

  /**
   * The guardrail message, or null when the delete would go through. Rendered
   * in the dialog AND enforced in the apply below, so a blocked delete cannot
   * be confirmed past the client either.
   */
  const deleteBlockedReason = computed<string | null>(() => {
    const status = deleteStatus.value;
    if (!status || !DELETE_BLOCKING_STATUSES.includes(status)) return null;
    if (status === 'has_domains') {
      return t('web.admin.organizations.detail.delete.blocked.hasDomains', {
        domains: domainSummary.value,
      });
    }
    if (status === 'drifted_domains') {
      return t('web.admin.organizations.detail.delete.blocked.driftedDomains', {
        domains: driftedSummary.value,
      });
    }
    if (status === 'is_default') {
      return t('web.admin.organizations.detail.delete.blocked.isDefault');
    }
    if (status === 'active_subscription') {
      return t('web.admin.organizations.detail.delete.blocked.activeSubscription');
    }
    return t('web.admin.organizations.detail.delete.blocked.lastOrg', {
      owner: deletePlan.value?.owner_id ?? '—',
    });
  });

  const {
    loading: deleteLoading,
    error: deleteError,
    run: runDeleteMutation,
    reset: resetDelete,
  } = useAdminMutation(async () => {
    // The server refuses these on the apply path too (4xx). Checking here means
    // the operator reads the reason instead of a generic request failure.
    if (deleteBlockedReason.value) throw new Error(deleteBlockedReason.value);

    const response = await $api.delete(deleteUrl(false));
    const parsed = gracefulParse(
      colonelDeleteOrganizationResponseSchema,
      response.data,
      'ColonelDeleteOrganizationResponse'
    );
    if (!parsed.ok) {
      // The delete may well have happened — say so rather than guessing either
      // way. The audit log and the org list are the record.
      throw new Error(t('web.admin.organizations.detail.delete.errors.unverified'));
    }
    if (!parsed.data.record.deleted || parsed.data.details?.dry_run !== false) {
      // A dry_run echo on an apply means the flag did not reach the endpoint.
      throw new Error(t('web.admin.organizations.detail.delete.errors.notApplied'));
    }
  });

  async function requestDelete(): Promise<void> {
    resetDelete();
    deletePlan.value = null;
    deleteStatus.value = null;
    forceDefault.value = false;
    forceSubscription.value = false;

    if (!(await runDeletePreview())) return; // preview failure renders inline
    // A superseded preview (double-click, race with a re-plan) resolves "ok"
    // without writing anything; never open the dialog on an empty plan.
    if (!deletePlan.value) return;
    deleteDialogOpen.value = true;
  }

  // Re-plan whenever an override is toggled: clearing one guard can reveal the
  // next one (a default workspace that is also the owner's only org), and the
  // dialog must never show a stale verdict. Deliberately not awaited — the
  // preview's issue guard makes the newest request the only writer, so rapid
  // toggles cannot land out of order.
  watch([forceDefault, forceSubscription], () => {
    if (!deleteDialogOpen.value) return;
    resetDelete();
    runDeletePreview();
  });

  async function onDeleteConfirm(): Promise<void> {
    const ok = await runDeleteMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    deleteDialogOpen.value = false;
    notifications.show(
      t('web.admin.organizations.detail.delete.success', { org: heading.value }),
      'success'
    );
    // The record is gone; the detail route would 404 on refresh.
    goBack();
  }

  function onDeleteCancel(): void {
    deleteDialogOpen.value = false;
    resetDelete();
  }

  // ---- Add an EXISTING account to this org (MUTATING — audited server-side) --
  //
  // Scoped deliberately to the one verb support actually needs: a person signed
  // up on their own, so they already have an account and the invite flow refuses
  // them, but they belong in this org. Removing a member and changing an
  // existing member's role are different endpoints and are NOT surfaced here.

  const addMemberOpen = ref(false);
  /** The account + role captured from the modal, held for the in-flight POST. */
  const pendingMember = ref<AddMembershipRequest | null>(null);

  /**
   * Turn a failed add into an operator-actionable message.
   *
   * The HTTP status is read straight off `err.response`: wrapped/mocked axios
   * errors are not reliably `instanceof AxiosError`, so the response envelope is
   * the dependable probe. The backend's own `error` string wins when present —
   * it is the only thing that separates "Organization not found" from "Customer
   * not found" on a 404, and it carries the accepted role list on a bad role.
   */
  function addMemberFailureMessage(err: unknown): string {
    const response = (err as { response?: { status?: number; data?: unknown } } | null)?.response;
    const data = response?.data;
    const serverMessage =
      typeof data === 'object' &&
      data !== null &&
      typeof (data as { error?: unknown }).error === 'string'
        ? (data as { error: string }).error
        : null;

    if (serverMessage) return serverMessage;
    if (response?.status === 404) {
      return t('web.admin.organizations.addMember.errors.notFound');
    }
    if (response?.status === 400 || response?.status === 422) {
      return t('web.admin.organizations.addMember.errors.invalidRole');
    }
    return classifyError(err).message;
  }

  const {
    loading: addMemberLoading,
    error: addMemberError,
    run: runAddMember,
    reset: resetAddMember,
  } = useAdminMutation(async () => {
    const target = pendingMember.value;
    if (!target) throw new Error(t('web.admin.organizations.addMember.errors.noSelection'));

    let response;
    try {
      response = await $api.post(`${orgUrl()}/members`, {
        // Always the EXTID, never an email address: the colonel adapter runs
        // `customer` through an identifier sanitizer, and the account picker
        // already resolved the address to a public id.
        customer: target.customer,
        role: target.role,
      });
    } catch (err) {
      throw new Error(addMemberFailureMessage(err));
    }

    const parsed = gracefulParse(
      colonelAddMembershipResponseSchema,
      response.data,
      'ColonelAddMembershipResponse'
    );
    // `no_change` is an idempotent 200: the account was ALREADY a member and the
    // op deliberately left their role untouched (add is strictly additive).
    // Surface it as an actionable failure instead of a false "added" toast. Ack
    // drift stays non-fatal — an unparseable 2xx is still treated as a success.
    if (parsed.ok && parsed.data.record.status === 'no_change') {
      throw new Error(
        t('web.admin.organizations.addMember.errors.alreadyMember', {
          role: parsed.data.record.role || target.role,
        })
      );
    }
  });

  function openAddMember(): void {
    resetAddMember();
    pendingMember.value = null;
    addMemberOpen.value = true;
  }

  async function onAddMemberSubmit(payload: AddMembershipRequest): Promise<void> {
    pendingMember.value = payload;
    const ok = await runAddMember();
    if (!ok) return; // Failure message stays in the modal for retry/cancel.

    addMemberOpen.value = false;
    notifications.show(
      t('web.admin.organizations.addMember.success', {
        account: payload.customer,
        role: t(`web.admin.organizations.addMember.roles.${payload.role}`, payload.role),
      }),
      'success'
    );
    pendingMember.value = null;
    // The roster is driven by a refreshed detail GET, never the ack — the new
    // member appears without a page reload.
    await refreshOrg().catch(() => {});
  }

  /** Dismissal (cancel / backdrop / Escape) — drop the captured target + error. */
  function onAddMemberOpenChange(value: boolean): void {
    addMemberOpen.value = value;
    if (value) return;
    pendingMember.value = null;
    resetAddMember();
  }

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
    // Plans populate the selector; a failure just leaves the current plan as
    // the only option (the selector degrades, the rest of the page is
    // unaffected).
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
        <div
          class="flex flex-wrap items-end justify-between gap-4 border-t border-gray-200 px-6 py-4 dark:border-gray-800">
          <!-- Change plan (catalog-validated server-side; reversible). Moved
               here from the customer detail page — billing lives on the org. -->
          <div class="min-w-0 grow sm:max-w-md">
            <label
              for="detail-plan-select"
              class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.actions.plan.label') }}
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
                :disabled="!pendingPlan || pendingPlan === (record.planid ?? '')"
                class="inline-flex shrink-0 items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
                @click="requestChangePlan">
                {{ t('web.admin.organizations.actions.plan.apply') }}
              </button>
            </div>
            <!-- Stripe unconfigured/unreachable: plans came from billing.yaml. -->
            <p
              v-if="plansFromLocalConfig"
              class="mt-2 text-xs text-amber-600 dark:text-amber-400"
              data-testid="plan-local-config-warning">
              {{ t('web.admin.organizations.actions.plan.localConfigWarning') }}
            </p>
          </div>
          <button
            type="button"
            data-testid="checkout-link-button"
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="checkoutLinkOpen = true">
            <OIcon
              collection="heroicons"
              name="link"
              size="4" />
            {{ t('web.admin.customers.actions.checkoutLink.button') }}
          </button>
        </div>
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
          <!--
            The resolution matrix: summary signals, per-entitlement rows
            (plan / grant / revoke → expected → materialized) and the legend.
          -->
          <EntitlementMatrix :entitlements="entitlements" />

          <!-- Grant / revoke / clear controls. -->
          <div class="border-t border-gray-200 pt-5 dark:border-gray-800">
            <!--
              Catalog dropdown first, free text as a deliberate escape hatch —
              the CLI allows out-of-catalog names and the console must not be
              less capable than it.
            -->
            <EntitlementPicker
              :key="entitlementPickerKey"
              v-model="entitlementInput"
              :options="availableEntitlements"
              :plan="entitlements.plan"
              :grants="entitlements.grants"
              :revokes="entitlements.revokes"
              :out-of-catalog="entitlementOutOfCatalog"
              :disabled="entitlementLoading" />

            <div class="mt-3 flex flex-wrap gap-2">
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
            <!-- Wipes EVERY override on the org — kept visually separate. -->
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
        <div
          class="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 px-6 py-4 dark:border-gray-800">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.organizations.detail.sections.members') }}
            <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400"
              >({{ details.members.length }})</span
            >
          </h3>
          <!-- Add an EXISTING account (the invite flow cannot cover this case). -->
          <button
            type="button"
            data-testid="org-add-member-button"
            class="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
            @click="openAddMember">
            <OIcon
              collection="heroicons"
              name="user-plus"
              size="4" />
            {{ t('web.admin.organizations.addMember.button') }}
          </button>
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
            <!-- The customer's PUBLIC id, and the way through to their record.
                 A real router-link, not a row-click handler, so middle-click and
                 open-in-new-tab work — the operator comparing several members
                 wants them side by side. GetUserDetails resolves by extid first
                 (see its #process comment), so the extid IS the route param. -->
            <router-link
              :to="{ name: 'AdminCustomerDetail', params: { id: row.extid } }"
              :data-testid="`member-detail-${row.extid}`"
              :title="t('web.admin.organizations.detail.members.openCustomer')"
              class="mt-0.5 inline-flex items-center gap-1 font-mono text-xs text-gray-500 hover:text-brand-600 hover:underline focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-brand-400">
              {{ row.extid }}
              <OIcon
                collection="heroicons"
                name="arrow-top-right-on-square"
                size="3"
                aria-hidden="true" />
              <span class="sr-only">{{
                t('web.admin.organizations.detail.members.openCustomer')
              }}</span>
            </router-link>
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
            <!-- Membership cascade (#3907 item 3): a partial cascade must be
                 operator-visible here — the applied statuses carry no reason
                 string, and nothing else in the console shows it. Translated
                 labels + raw values, same composition as the diff rows. -->
            <p
              v-if="reconcileCascade"
              class="mt-2 text-xs"
              :class="
                reconcileCascade.failed > 0
                  ? 'font-medium text-red-700 dark:text-red-300'
                  : 'text-amber-700 dark:text-amber-300'
              "
              data-testid="reconcile-memberships">
              {{ t('web.admin.organizations.detail.reconcile.memberships') }}
              <span class="font-mono"
                >{{ reconcileCascade.success }}/{{ reconcileCascade.total }}</span
              >
              <template v-if="reconcileCascade.failed > 0">
                — {{ reconcileCascade.failed }}
                {{ t('web.admin.organizations.detail.reconcile.membershipsFailed') }}
                <span class="font-mono">{{ reconcileCascade.failed_ids.join(', ') }}</span>
              </template>
            </p>
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

      <!--
        Caution zone — permanent delete (#4204). The console peer of
        `bin/ots org delete`, and the reason an operator never has to reach for
        `bin/console` (a hand-run destroy! leaves Organization.instances
        dangling, mails nobody, and strands default_org_id).

        The button only PREVIEWS: the plan it fetches is what the confirmation
        dialog is built from, and nothing is written until the extid is retyped.
      -->
      <section
        class="overflow-hidden rounded-lg border border-red-200 bg-white shadow-sm dark:border-red-900/50 dark:bg-gray-800"
        data-testid="org-danger-zone">
        <div class="border-b border-red-200 px-6 py-4 dark:border-red-900/50">
          <h2 class="text-sm font-semibold text-red-700 dark:text-red-400">
            {{ t('web.COMMON.caution_zone') }}
          </h2>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.admin.organizations.detail.delete.warning') }}
          </p>
        </div>

        <div class="space-y-3 px-6 py-5">
          <button
            type="button"
            data-testid="org-delete-button"
            :disabled="deletePreviewLoading || deleteLoading"
            class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-600 transition-colors hover:bg-red-600 hover:text-white focus:ring-2 focus:ring-red-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-700 dark:text-red-400 dark:hover:bg-red-700 dark:hover:text-white"
            @click="requestDelete">
            <OIcon
              collection="heroicons"
              :name="deletePreviewLoading ? 'arrow-path' : 'trash'"
              size="4"
              :class="deletePreviewLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
            {{
              deletePreviewLoading
                ? t('web.admin.organizations.detail.delete.previewing')
                : t('web.admin.organizations.detail.delete.button')
            }}
          </button>

          <!-- Preview failure: the dialog never opens, so report it here. -->
          <div
            v-if="deletePreviewError && !deleteDialogOpen"
            class="rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-300"
            role="alert"
            data-testid="org-delete-preview-error">
            {{ deletePreviewError }}
          </div>
        </div>
      </section>
    </div>

    <!--
      Add an existing account to this org. Kept at the root (not inside the
      loaded block) so opening/closing it never remounts the detail sections.
    -->
    <AddMemberModal
      :open="addMemberOpen"
      :org-extid="record?.extid ?? ''"
      :org-name="heading"
      :members="details?.members ?? []"
      :loading="addMemberLoading"
      :error="addMemberError"
      @update:open="onAddMemberOpenChange"
      @submit="onAddMemberSubmit" />

    <AdminCheckoutLinkModal
      v-if="record"
      v-model:open="checkoutLinkOpen"
      :endpoint="`${orgUrl()}/checkout-link`"
      :subject="heading"
      :plans="planOptions"
      :default-plan="record.planid" />

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

    <!-- Plan change (reversible, so no typed confirmation — confirm/cancel only). -->
    <AdminConfirmDialog
      v-model:open="planDialogOpen"
      :title="t('web.admin.organizations.actions.plan.confirmTitle')"
      :description="
        t('web.admin.organizations.actions.plan.confirmDescription', {
          org: heading,
          plan: pendingPlan,
        })
      "
      :confirm-text="t('web.admin.organizations.actions.plan.apply')"
      :loading="planLoading"
      :error="planError"
      @confirm="onPlanConfirm"
      @cancel="onPlanCancel" />

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

    <!--
      Guarded delete (typed-confirmation — retype the extid). The description
      slot carries the server's own plan: what is about to be destroyed, the
      guardrail that would block it, and the single override that clears that
      one guard. Toggling an override re-runs the preview.
    -->
    <AdminConfirmDialog
      v-model:open="deleteDialogOpen"
      :title="t('web.admin.organizations.detail.delete.confirmTitle')"
      :confirm-token="record?.extid"
      variant="danger"
      :confirm-text="t('web.admin.organizations.detail.delete.button')"
      :loading="deleteLoading || deletePreviewLoading"
      :error="deleteError || deletePreviewError"
      @confirm="onDeleteConfirm"
      @cancel="onDeleteCancel">
      <template #description>
        <div
          class="space-y-3 text-sm text-gray-600 dark:text-gray-300"
          data-testid="org-delete-plan">
          <p>
            {{ t('web.admin.organizations.detail.delete.confirmDescription', { org: heading }) }}
          </p>

          <!-- The guardrail verdict, when the server would refuse the apply. -->
          <p
            v-if="deleteBlockedReason"
            class="rounded-md bg-red-50 p-2 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300"
            role="alert"
            data-testid="org-delete-blocked">
            {{ deleteBlockedReason }}
          </p>

          <dl
            v-if="deletePlan"
            class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
            <dt class="text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.fields.plan') }}
            </dt>
            <dd class="font-mono text-gray-900 dark:text-white">{{ deletePlan.planid }}</dd>

            <dt class="text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.detail.delete.membersLabel') }}
            </dt>
            <dd
              class="text-gray-900 dark:text-white"
              data-testid="org-delete-member-count">
              {{ deletePlan.members.length }}
            </dd>

            <dt class="text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.detail.delete.invitationsLabel') }}
            </dt>
            <dd class="text-gray-900 dark:text-white">{{ deletePlan.pending_invitations }}</dd>

            <dt class="text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.detail.delete.domainsLabel') }}
            </dt>
            <dd class="text-gray-900 dark:text-white">
              {{ domainSummary || t('web.admin.organizations.detail.none') }}
            </dd>

            <!--
              Drifted domains are in NEITHER row above (that is what "missing
              from the collection" means), so without this the operator sees a
              refusal naming domains the screen never shows. Rendered whenever
              the server reports drift, not only on the `drifted_domains`
              verdict: `has_domains` trips first, and an org can carry both.
            -->
            <template v-if="driftedDomains.length">
              <dt class="text-gray-500 dark:text-gray-400">
                {{ t('web.admin.organizations.detail.delete.driftedDomainsLabel') }}
              </dt>
              <dd
                class="text-gray-900 dark:text-white"
                data-testid="org-delete-drifted-domains">
                {{ driftedDomains.join(', ') }}
                <span class="mt-0.5 block font-mono text-[11px] text-gray-500 dark:text-gray-400">
                  {{ t('web.admin.organizations.detail.delete.driftedDomainsRepair') }}
                </span>
              </dd>
            </template>

            <dt class="text-gray-500 dark:text-gray-400">
              {{ t('web.admin.organizations.detail.delete.defaultOrgLabel') }}
            </dt>
            <dd class="text-gray-900 dark:text-white">
              {{
                deletePlan.default_org_cleared.length
                  ? deletePlan.default_org_cleared.join(', ')
                  : t('web.admin.organizations.detail.none')
              }}
            </dd>
          </dl>

          <!-- Member roster: the operator checks they have the right org. -->
          <ul
            v-if="deletePlan?.members.length"
            class="max-h-32 space-y-0.5 overflow-y-auto rounded border border-gray-200 p-2 text-xs dark:border-gray-700">
            <li
              v-for="member in deletePlan.members"
              :key="member.extid"
              class="flex items-center justify-between gap-2">
              <span class="font-mono text-gray-500 dark:text-gray-400">{{ member.extid }}</span>
              <span class="truncate text-gray-700 dark:text-gray-200">{{ member.email }}</span>
            </li>
          </ul>

          <!-- Overrides: each clears exactly ONE guard, and only when it trips. -->
          <label
            v-if="deletePlan?.is_default"
            class="flex items-start gap-2 text-xs text-gray-700 dark:text-gray-300"
            data-testid="org-delete-force-default">
            <input
              v-model="forceDefault"
              type="checkbox"
              class="mt-0.5 rounded border-gray-300 text-red-600 focus:ring-red-500 dark:border-gray-600 dark:bg-gray-700" />
            <span>{{ t('web.admin.organizations.detail.delete.forceDefault') }}</span>
          </label>

          <label
            v-if="deletePlan?.active_subscription"
            class="flex items-start gap-2 text-xs text-gray-700 dark:text-gray-300"
            data-testid="org-delete-force-subscription">
            <input
              v-model="forceSubscription"
              type="checkbox"
              class="mt-0.5 rounded border-gray-300 text-red-600 focus:ring-red-500 dark:border-gray-600 dark:bg-gray-700" />
            <span>{{ t('web.admin.organizations.detail.delete.forceSubscription') }}</span>
          </label>
        </div>
      </template>
    </AdminConfirmDialog>
  </div>
</template>
