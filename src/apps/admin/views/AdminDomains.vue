<!-- src/apps/admin/views/AdminDomains.vue -->

<script setup lang="ts">

  import AddDomainForOrgModal from '@/apps/admin/components/AddDomainForOrgModal.vue';
  import AdminDomainDnsDetails from '@/apps/admin/components/AdminDomainDnsDetails.vue';
  import AdminOrgSelectorModal from '@/apps/admin/components/AdminOrgSelectorModal.vue';
  import { AdminConfirmDialog, AdminRecordPanel, KitPagination } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
  import type { ColonelCustomDomain, ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
  import {
    colonelDomainDetailResponseSchema,
    colonelDomainVerifyResponseSchema,
    type ColonelDomainCluster,
    type ColonelDomainDetailRecord,
  } from '@/schemas/api/internal/responses/colonel-domains';
  import type { ColonelDomainVerifyResponse } from '@/schemas/api/internal/responses/colonel-domains';
  import {
    colonelOrganizationDetailResponseSchema,
    type ColonelOrganizationDetailDomain,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import CardGridSkeleton from '@/shared/components/closet/CardGridSkeleton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Domains screen — card grid + per-domain verify (ticket #31, Phase-2 parity
   * port), plus the admin "attach a domain to a specific organization" flow.
   *
   * - LIST via {@link useAdminDomains} (a per-resource paginated store over the
   *   existing `GET /api/colonel/domains`) + {@link KitPagination}.
   * - The VERIFY action POSTs to `/api/colonel/domains/:extid/verify` and
   *   surfaces the op's real DNS/SSL outcome HONESTLY (never faked).
   * - The ATTACH flow: a CTA opens {@link AdminOrgSelectorModal} to pick an org
   *   by objid/extid/email; the chosen org is pinned into an
   *   {@link AdminRecordPanel} between the header rule and the list. From there
   *   the operator adds a domain ({@link AddDomainForOrgModal} →
   *   `POST /api/colonel/domains`) and inspects each domain's DNS-validation
   *   records, status, and re-verify ({@link AdminDomainDnsDetails} +
   *   `GET /api/colonel/domains/:extid`). The panel + picker are reusable kit /
   *   components so other console screens can adopt the single-record pattern.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminDomains();
  const { domains, pagination, loading, error } = storeToRefs(store);

  // ---- Status badges (parity with the legacy screen) ------------------------

  /** Verification-state badge colours, keyed by the op's state symbol. */
  function stateBadgeClass(state: string): string {
    switch (state) {
      case 'verified':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'resolving':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200';
    }
  }

  const stateLabels = computed<Record<string, string>>(() => ({
    verified: t('web.colonel.customDomains.status.verified'),
    resolving: t('web.colonel.customDomains.status.resolving'),
    pending: t('web.colonel.customDomains.status.pending'),
  }));

  function stateLabel(state: string): string {
    return stateLabels.value[state] ?? state;
  }

  /** External URL for an operator to open/test a domain in a new tab. */
  function domainUrl(displayDomain: string): string {
    return `https://${displayDomain}`;
  }

  // ---- List fetching --------------------------------------------------------

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // below handle it. Swallow so it doesn't become an unhandled rejection.
    }
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Guarded verify action (list cards) -----------------------------------

  const dialogOpen = ref(false);
  /** The domain awaiting confirmation, or currently being verified. */
  const activeDomain = ref<ColonelCustomDomain | null>(null);
  /** extid of the domain whose verify request is in flight (per-card spinner). */
  const verifyingExtid = ref<string | null>(null);
  /** The last parsed verify ack, read in onConfirm to pick an honest message. */
  const verifyResult = ref<ColonelDomainVerifyResponse | null>(null);

  const {
    loading: verifyLoading,
    error: verifyError,
    run: runVerify,
    reset: resetVerify,
  } = useAdminMutation(async (extid: string) => {
    verifyResult.value = null;
    const response = await $api.post(
      `/api/colonel/domains/${encodeURIComponent(extid)}/verify`
    );
    // Parse the ack so it stays a live tripwire. A 2xx means the verify ran
    // server-side regardless of ack shape; a mismatch is reported by
    // gracefulParse but does not fail the action (we fall back to a generic
    // success message and refresh the list).
    const parsed = gracefulParse(
      colonelDomainVerifyResponseSchema,
      response.data,
      'ColonelDomainVerifyResponse'
    );
    verifyResult.value = parsed.ok ? parsed.data : null;
  });

  const dialogDescription = computed(() =>
    activeDomain.value
      ? t('web.admin.domains.verify.confirmDescription', {
          domain: activeDomain.value.display_domain,
        })
      : undefined
  );

  function requestVerify(domain: ColonelCustomDomain): void {
    activeDomain.value = domain;
    resetVerify();
    dialogOpen.value = true;
  }

  /** Per-state operator notification. Unknown states fall back to `done`. */
  const VERIFY_MESSAGE_KEYS: Record<string, string> = {
    verified: 'web.admin.domains.verify.success.verified',
    resolving: 'web.admin.domains.verify.success.resolving',
    pending: 'web.admin.domains.verify.success.pending',
    unverified: 'web.admin.domains.verify.success.unverified',
  };

  /** Map the honest post-verify state to its operator notification. */
  function notifyOutcome(): void {
    const state = verifyResult.value?.details?.current_state ?? '';
    const domainName = activeDomain.value?.display_domain ?? '';
    const messageKey = VERIFY_MESSAGE_KEYS[state] ?? 'web.admin.domains.verify.success.done';

    notifications.show(
      t(messageKey, { domain: domainName }),
      state === 'verified' ? 'success' : 'info'
    );
  }

  async function onConfirm(): Promise<void> {
    const domain = activeDomain.value;
    if (!domain) return;

    verifyingExtid.value = domain.extid;
    const ok = await runVerify(domain.extid);
    verifyingExtid.value = null;

    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;
    notifyOutcome();
    // Re-fetch the current page so every card's badge reflects real persisted
    // state (the verify may have flipped verified/resolving).
    await fetchPage(pagination.value?.page ?? 1);
    activeDomain.value = null;
    verifyResult.value = null;
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeDomain.value = null;
    resetVerify();
  }

  // ---- Attach-domain-to-organization flow -----------------------------------

  const orgPickerOpen = ref(false);
  const addDomainOpen = ref(false);
  /** The organization pinned into the working-record panel, or null. */
  const selectedOrg = ref<ColonelOrganization | null>(null);

  // Roster of the selected org's domains (from GET /organizations/:extid).
  const orgDomains = ref<ColonelOrganizationDetailDomain[]>([]);
  const orgDomainsLoading = ref(false);
  const orgDomainsError = ref(false);

  // Per-domain DNS detail (one expanded at a time).
  const expandedExtid = ref<string | null>(null);
  const domainDetail = ref<ColonelDomainDetailRecord | null>(null);
  const domainCluster = ref<ColonelDomainCluster>(null);
  const detailLoading = ref(false);
  const detailError = ref(false);

  /** extid of a panel domain whose re-verify is in flight. */
  const panelVerifyingExtid = ref<string | null>(null);

  async function loadOrgDomains(): Promise<void> {
    const org = selectedOrg.value;
    if (!org) return;
    orgDomainsLoading.value = true;
    orgDomainsError.value = false;
    try {
      const res = await $api.get(
        `/api/colonel/organizations/${encodeURIComponent(org.extid)}`
      );
      const parsed = gracefulParse(
        colonelOrganizationDetailResponseSchema,
        res.data,
        'ColonelOrganizationDetailResponse'
      );
      orgDomains.value = parsed.ok ? parsed.data.details?.domains ?? [] : [];
    } catch {
      orgDomainsError.value = true;
      orgDomains.value = [];
    } finally {
      orgDomainsLoading.value = false;
    }
  }

  function onOrgSelected(org: ColonelOrganization): void {
    selectedOrg.value = org;
    expandedExtid.value = null;
    domainDetail.value = null;
    domainCluster.value = null;
    loadOrgDomains();
  }

  function clearSelectedOrg(): void {
    selectedOrg.value = null;
    orgDomains.value = [];
    expandedExtid.value = null;
    domainDetail.value = null;
    domainCluster.value = null;
  }

  async function loadDomainDetail(extid: string): Promise<void> {
    detailLoading.value = true;
    detailError.value = false;
    domainDetail.value = null;
    domainCluster.value = null;
    try {
      const res = await $api.get(`/api/colonel/domains/${encodeURIComponent(extid)}`);
      const parsed = gracefulParse(
        colonelDomainDetailResponseSchema,
        res.data,
        'ColonelDomainDetailResponse'
      );
      if (parsed.ok) {
        domainDetail.value = parsed.data.record;
        domainCluster.value = parsed.data.details?.cluster ?? null;
      } else {
        detailError.value = true;
      }
    } catch {
      detailError.value = true;
    } finally {
      detailLoading.value = false;
    }
  }

  function toggleDetail(extid: string): void {
    if (expandedExtid.value === extid) {
      expandedExtid.value = null;
      domainDetail.value = null;
      domainCluster.value = null;
      return;
    }
    expandedExtid.value = extid;
    loadDomainDetail(extid);
  }

  // Create-domain-for-org mutation. `createdExtid` captures the new domain's id
  // so we can reveal its DNS records immediately after creation.
  const createdExtid = ref<string | null>(null);
  const {
    loading: createLoading,
    error: createError,
    run: runCreate,
    reset: resetCreate,
  } = useAdminMutation(async (domain: string) => {
    const org = selectedOrg.value;
    if (!org) throw new Error('No organization selected');
    createdExtid.value = null;
    const res = await $api.post('/api/colonel/domains', {
      org_id: org.extid,
      domain,
    });
    const parsed = gracefulParse(
      colonelDomainDetailResponseSchema,
      res.data,
      'ColonelDomainDetailResponse'
    );
    createdExtid.value = parsed.ok ? parsed.data.record.extid : null;
  });

  function openAddDomain(): void {
    resetCreate();
    addDomainOpen.value = true;
  }

  async function onCreateDomain(domain: string): Promise<void> {
    const ok = await runCreate(domain);
    if (!ok) return; // error stays in the modal for retry.

    addDomainOpen.value = false;
    notifications.show(
      t('web.admin.domains.addDomain.created', { domain }),
      'success'
    );
    await loadOrgDomains();
    // Reveal the freshly created domain's DNS records.
    const extid = createdExtid.value;
    if (extid) {
      expandedExtid.value = extid;
      await loadDomainDetail(extid);
    }
  }

  async function reverifyPanelDomain(domain: ColonelOrganizationDetailDomain): Promise<void> {
    panelVerifyingExtid.value = domain.extid;
    try {
      const res = await $api.post(
        `/api/colonel/domains/${encodeURIComponent(domain.extid)}/verify`
      );
      const parsed = gracefulParse(
        colonelDomainVerifyResponseSchema,
        res.data,
        'ColonelDomainVerifyResponse'
      );
      const state = parsed.ok ? parsed.data.details?.current_state ?? '' : '';
      const messageKey = VERIFY_MESSAGE_KEYS[state] ?? 'web.admin.domains.verify.success.done';
      notifications.show(
        t(messageKey, { domain: domain.display_domain }),
        state === 'verified' ? 'success' : 'info'
      );
      await loadOrgDomains();
      if (expandedExtid.value === domain.extid) await loadDomainDetail(domain.extid);
    } catch {
      notifications.show(
        t('web.admin.domains.verify.failed', { domain: domain.display_domain }),
        'error'
      );
    } finally {
      panelVerifyingExtid.value = null;
    }
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header. The heavy bottom rule is the page's horizontal rule; the
         working-record panel sits between it and the list below. -->
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <div>
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ t('web.colonel.customDomains.title') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.colonel.customDomains.description') }}
        </p>
      </div>
      <button
        type="button"
        data-testid="attach-domain-cta"
        class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
        @click="orgPickerOpen = true">
        <OIcon
          collection="heroicons"
          name="building-office-2"
          size="5" />
        {{ t('web.admin.domains.attach.cta') }}
      </button>
    </header>

    <!-- Working-record panel: the selected organization, pinned for domain work. -->
    <AdminRecordPanel
      v-if="selectedOrg"
      :eyebrow="t('web.admin.domains.attach.recordEyebrow')"
      :title="selectedOrg.display_name || t('web.admin.domains.orgPicker.unnamedOrg')"
      :subtitle="selectedOrg.extid"
      testid="selected-org-panel"
      @clear="clearSelectedOrg">
      <template #actions>
        <button
          type="button"
          data-testid="panel-add-domain"
          class="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="openAddDomain">
          <OIcon
            collection="heroicons"
            name="plus"
            size="4" />
          {{ t('web.admin.domains.addDomain.button') }}
        </button>
      </template>

      <!-- Roster loading -->
      <div
        v-if="orgDomainsLoading"
        class="flex items-center gap-2 py-6 text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.processing') }}
      </div>

      <!-- Roster error -->
      <div
        v-else-if="orgDomainsError"
        class="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-200"
        role="alert">
        {{ t('web.admin.domains.attach.rosterError') }}
      </div>

      <!-- Empty roster -->
      <div
        v-else-if="orgDomains.length === 0"
        class="rounded-md border border-dashed border-gray-300 py-8 text-center text-sm text-gray-500 dark:border-gray-600 dark:text-gray-400"
        data-testid="panel-domains-empty">
        {{ t('web.admin.domains.attach.noDomains') }}
      </div>

      <!-- Domain roster -->
      <ul
        v-else
        class="divide-y divide-gray-100 dark:divide-gray-800"
        data-testid="panel-domains">
        <li
          v-for="domain in orgDomains"
          :key="domain.domain_id"
          :data-testid="`panel-domain-${domain.extid}`"
          class="py-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex min-w-0 items-center gap-2">
              <h4 class="truncate text-sm font-semibold text-gray-900 dark:text-white">
                {{ domain.display_domain }}
              </h4>
              <a
                :href="domainUrl(domain.display_domain)"
                target="_blank"
                rel="noopener noreferrer"
                :data-testid="`panel-domain-open-${domain.extid}`"
                :aria-label="t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })"
                :title="t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })"
                class="shrink-0 rounded text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-top-right-on-square"
                  size="4" />
              </a>
              <span
                :class="[
                  'inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium',
                  stateBadgeClass(domain.verification_state),
                ]"
                :data-testid="`panel-domain-state-${domain.extid}`">
                {{ stateLabel(domain.verification_state) }}
              </span>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <button
                type="button"
                :data-testid="`panel-domain-dns-${domain.extid}`"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                :aria-expanded="expandedExtid === domain.extid"
                @click="toggleDetail(domain.extid)">
                <OIcon
                  collection="heroicons"
                  :name="expandedExtid === domain.extid ? 'chevron-up' : 'chevron-down'"
                  size="4" />
                {{ t('web.admin.domains.dns.toggle') }}
              </button>
              <button
                type="button"
                :data-testid="`panel-domain-verify-${domain.extid}`"
                :disabled="panelVerifyingExtid === domain.extid"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                @click="reverifyPanelDomain(domain)">
                <OIcon
                  collection="heroicons"
                  :name="panelVerifyingExtid === domain.extid ? 'arrow-path' : 'shield-check'"
                  size="4"
                  :class="panelVerifyingExtid === domain.extid ? 'animate-spin motion-reduce:animate-none' : ''" />
                {{ t('web.admin.domains.verify.button') }}
              </button>
            </div>
          </div>

          <!-- Expanded DNS details -->
          <div
            v-if="expandedExtid === domain.extid"
            class="mt-3">
            <div
              v-if="detailLoading"
              class="flex items-center gap-2 py-4 text-sm text-gray-500 dark:text-gray-400">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                size="5"
                class="animate-spin motion-reduce:animate-none" />
              {{ t('web.COMMON.processing') }}
            </div>
            <div
              v-else-if="detailError"
              class="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-200"
              role="alert">
              {{ t('web.admin.domains.dns.loadError') }}
            </div>
            <AdminDomainDnsDetails
              v-else-if="domainDetail"
              :record="domainDetail"
              :cluster="domainCluster" />
          </div>
        </li>
      </ul>
    </AdminRecordPanel>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="domains-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.domains.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.domains.retry') }}
      </button>
    </div>

    <!-- Loading (first load) -->
    <CardGridSkeleton
      v-if="loading && domains.length === 0"
      :count="4"
      data-testid="domains-loading" />

    <!-- Empty -->
    <div
      v-else-if="domains.length === 0"
      class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-900"
      data-testid="domains-empty">
      <p class="text-gray-500 dark:text-gray-400">
        {{ t('web.colonel.customDomains.empty') }}
      </p>
    </div>

    <!-- Card grid -->
    <template v-else>
      <div
        data-testid="domains-grid"
        class="grid gap-6 sm:grid-cols-1 lg:grid-cols-2">
        <div
          v-for="domain in domains"
          :key="domain.domain_id"
          :data-testid="`domain-card-${domain.extid}`"
          class="flex flex-col rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-900">
          <!-- Header: logo + domain + verification badge -->
          <div class="mb-4 flex items-start justify-between gap-3">
            <div class="flex min-w-0 items-center gap-4">
              <!-- Logo thumbnail -->
              <div
                v-if="domain.has_logo"
                class="size-16 flex-shrink-0 overflow-hidden rounded-lg border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
                <img
                  :src="domain.logo_url ?? undefined"
                  :alt="`${domain.display_domain} logo`"
                  class="size-full object-contain"
                  loading="lazy" />
              </div>
              <div
                v-else
                class="flex size-16 flex-shrink-0 items-center justify-center rounded-lg border border-gray-200 bg-gray-100 dark:border-gray-700 dark:bg-gray-700">
                <span class="text-xs text-gray-400">{{ t('web.colonel.customDomains.noLogo') }}</span>
              </div>

              <!-- Domain info -->
              <div class="min-w-0">
                <h3 class="truncate text-lg font-semibold text-gray-900 dark:text-white">
                  {{ domain.display_domain }}
                </h3>
                <p
                  v-if="domain.brand.name"
                  class="truncate text-sm text-gray-600 dark:text-gray-400">
                  {{ domain.brand.name }}
                </p>
              </div>
            </div>

            <!-- Verification badge + external-tab link -->
            <div class="flex shrink-0 items-center gap-2">
              <a
                :href="domainUrl(domain.display_domain)"
                target="_blank"
                rel="noopener noreferrer"
                :data-testid="`domain-open-${domain.extid}`"
                :aria-label="t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })"
                :title="t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })"
                class="rounded text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-top-right-on-square"
                  size="4" />
              </a>
              <span
                :class="[
                  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                  stateBadgeClass(domain.verification_state),
                ]"
                :data-testid="`domain-state-${domain.extid}`">
                {{ stateLabel(domain.verification_state) }}
              </span>
            </div>
          </div>

          <!-- Brand details -->
          <div
            v-if="domain.brand.tagline || domain.brand.homepage_url"
            class="mb-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <p
              v-if="domain.brand.tagline"
              class="text-sm text-gray-600 dark:text-gray-400">
              {{ domain.brand.tagline }}
            </p>
            <a
              v-if="domain.brand.homepage_url"
              :href="domain.brand.homepage_url"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-1 inline-block text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400">
              {{ domain.brand.homepage_url }} ↗
            </a>
          </div>

          <!-- Domain details grid -->
          <div
            class="grid grid-cols-2 gap-4 border-t border-gray-100 pt-4 text-sm dark:border-gray-700">
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.organization') }}:</span>
              <p class="font-medium text-gray-900 dark:text-white">
                {{ domain.org_name }}
              </p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.externalId') }}:</span>
              <p class="font-mono text-xs text-gray-900 dark:text-white">
                {{ domain.extid }}
              </p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.created') }}:</span>
              <p class="text-gray-900 dark:text-white">
                {{ formatDisplayDateTime(domain.created) }}
              </p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.updated') }}:</span>
              <p class="text-gray-900 dark:text-white">
                {{ domain.updated ? formatDisplayDateTime(domain.updated) : '—' }}
              </p>
            </div>
          </div>

          <!-- Status flags -->
          <div class="mt-4 flex flex-wrap gap-2 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span
              v-if="domain.verified"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ {{ t('web.colonel.customDomains.status.verified') }}
            </span>
            <span
              v-if="domain.resolving"
              class="inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900 dark:text-blue-200">
              ✓ {{ t('web.colonel.customDomains.status.resolving') }}
            </span>
            <span
              v-if="domain.ready"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ {{ t('web.colonel.customDomains.status.ready') }}
            </span>
            <span
              v-if="domain.homepage_config?.enabled"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              {{ t('web.colonel.customDomains.status.publicHomepage') }}
            </span>
            <span
              v-if="domain.api_config?.enabled"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              {{ t('web.colonel.customDomains.status.publicApi') }}
            </span>
          </div>

          <!-- Icon preview (if available) -->
          <div
            v-if="domain.has_icon"
            class="mt-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.favicon') }}:</span>
            <div
              class="mt-2 inline-block size-8 overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
              <img
                :src="domain.icon_url ?? undefined"
                :alt="`${domain.display_domain} favicon`"
                class="size-full object-contain"
                loading="lazy" />
            </div>
          </div>

          <!-- Verify action -->
          <div class="mt-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <button
              type="button"
              :data-testid="`domain-verify-${domain.extid}`"
              :disabled="verifyingExtid === domain.extid"
              class="inline-flex w-full items-center justify-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              @click="requestVerify(domain)">
              <OIcon
                collection="heroicons"
                :name="verifyingExtid === domain.extid ? 'arrow-path' : 'shield-check'"
                size="4"
                :class="verifyingExtid === domain.extid ? 'animate-spin motion-reduce:animate-none' : ''" />
              {{ t('web.admin.domains.verify.button') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Pagination -->
      <KitPagination
        v-if="pagination"
        :pagination="pagination"
        :loading="loading"
        class="mt-6"
        @update:page="onPageChange"
        @update:per-page="onPerPageChange" />
    </template>

    <!-- Shared guarded-action dialog (one-click confirm for the low-risk verb). -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="t('web.admin.domains.verify.confirmTitle')"
      :description="dialogDescription"
      :confirm-text="t('web.admin.domains.verify.button')"
      :loading="verifyLoading"
      :error="verifyError"
      @confirm="onConfirm"
      @cancel="onCancel" />

    <!-- Attach flow: org picker + add-domain modal. -->
    <AdminOrgSelectorModal
      v-model:open="orgPickerOpen"
      @select="onOrgSelected" />
    <AddDomainForOrgModal
      v-model:open="addDomainOpen"
      :org="selectedOrg"
      :loading="createLoading"
      :error="createError"
      @submit="onCreateDomain" />
  </div>
</template>
