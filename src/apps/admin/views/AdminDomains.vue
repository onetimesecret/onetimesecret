<!-- src/apps/admin/views/AdminDomains.vue -->

<script setup lang="ts">
  import AddDomainForOrgModal from '@/apps/admin/components/AddDomainForOrgModal.vue';
  import AdminDomainDnsDetails from '@/apps/admin/components/AdminDomainDnsDetails.vue';
  import AdminOrgSelectorModal from '@/apps/admin/components/AdminOrgSelectorModal.vue';
  import DomainStateBadge from '@/apps/admin/components/domains/DomainStateBadge.vue';
  import {
    AdminConfirmDialog,
    AdminRecordPanel,
    DataTable,
    DetailDrawer,
    FilterBar,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
  import type {
    ColonelCustomDomain,
    ColonelOrganization,
  } from '@/schemas/api/internal/responses/colonel';
  import type {
    ColonelDomainCluster,
    ColonelDomainDetailRecord,
    ColonelDomainVerifyDetails,
  } from '@/schemas/api/internal/responses/colonel-domains';
  import { colonelDomainDetailResponseSchema } from '@/schemas/api/internal/responses/colonel-domains';
  import {
    colonelOrganizationDetailResponseSchema,
    type ColonelOrganizationDetailDomain,
  } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { storeToRefs } from 'pinia';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Domains list — the User-Management-grade console surface for custom domains.
   *
   * Structure mirrors AdminCustomers.vue so a row behaves the same everywhere in
   * the console: FilterBar + {@link DataTable} + {@link KitPagination} over the
   * {@link useAdminDomains} store, a row click opens a read-only
   * {@link DetailDrawer} rendered from data already in hand (no second fetch),
   * and the drawer escalates to the full page (AdminDomainDetail) for the deep,
   * mutating verbs (probe / repair / transfer / remove).
   *
   * Filters are SERVER-SIDE (`search` + `status` on GET /api/colonel/domains,
   * applied before pagination) with the same 300 ms debounce and no-op guard
   * AdminCustomers uses. `search` matches display_domain / base_domain plus an
   * exact extid / domain_id — NOT the organization name.
   *
   * One deliberate difference from the customers list: VERIFY stays on the row.
   * It is the one high-frequency, low-risk domain verb, so keeping it inline
   * preserves the capability the previous card grid had and saves a round trip
   * through the detail page.
   *
   * The admin "attach a domain to a specific organization" flow is unchanged: a
   * CTA opens {@link AdminOrgSelectorModal}, the chosen org is pinned into an
   * {@link AdminRecordPanel}, and from there the operator adds a domain
   * ({@link AddDomainForOrgModal}) and inspects each domain's DNS records
   * ({@link AdminDomainDnsDetails}).
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminDomains();
  const { domains, pagination, loading, error } = storeToRefs(store);

  /** External URL for an operator to open/test a domain in a new tab. */
  function domainUrl(displayDomain: string): string {
    return `https://${displayDomain}`;
  }

  // ---- Filters + list fetching ----------------------------------------------
  //
  // Both filters are SERVER-SIDE (`search` / `status` on
  // GET /api/colonel/domains) and are applied before pagination, so the pager's
  // total_count always describes the filtered population.

  const searchTerm = ref('');
  const activeSearch = ref('');
  const stateFilter = ref('');

  /** States the backend emits (CustomDomain#verification_state). */
  const STATE_OPTIONS = ['verified', 'resolving', 'pending'] as const;

  const filters = computed<FilterConfig[]>(() => [
    {
      key: 'state',
      label: t('web.admin.domains.list.stateFilter'),
      value: stateFilter.value,
      options: STATE_OPTIONS.map((state) => ({
        value: state,
        label: t(`web.colonel.customDomains.status.${state}`, state),
      })),
    },
  ]);

  const hasActiveFilters = computed(() => searchTerm.value !== '' || stateFilter.value !== '');

  /** Fetch one server page with the active filters. Errors surface via the store. */
  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage, {
        search: activeSearch.value || undefined,
        status: stateFilter.value || undefined,
      });
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // below handle it. Swallow so it doesn't become an unhandled rejection.
    }
  }

  // Debounce search input so we issue one request per pause, not per keystroke
  // (the fixed AdminCustomers wiring, including the no-op guard).
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  watch(searchTerm, (value) => {
    if (searchTimer) clearTimeout(searchTimer);
    // Skip no-op changes (e.g. the programmatic reset in onClear(), which
    // already issues its own fetch) so clearing doesn't double-fetch.
    if (value.trim() === activeSearch.value) return;
    searchTimer = setTimeout(() => {
      activeSearch.value = value.trim();
      fetchPage(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (searchTimer) clearTimeout(searchTimer);
  });

  function onFilterChange(key: string, value: string): void {
    if (key === 'state') {
      stateFilter.value = value;
      fetchPage(1);
    }
  }

  function onClear(): void {
    // Cancel any in-flight debounce so the reset below doesn't fire a second,
    // late request on top of this one.
    if (searchTimer) clearTimeout(searchTimer);
    searchTerm.value = '';
    activeSearch.value = '';
    stateFilter.value = '';
    fetchPage(1);
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    // The composable owns perPage (reconciled from the server echo); set it then
    // re-fetch the first page at the new size.
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Columns --------------------------------------------------------------
  //
  // Non-sortable on purpose: the endpoint returns a FIXED ordering and takes no
  // `sort` param, so a sortable header would promise a re-fetch we cannot make.

  const columns = computed<DataTableColumn<ColonelCustomDomain>[]>(() => [
    { key: 'domain', label: t('web.admin.domains.columns.domain') },
    { key: 'organization', label: t('web.admin.domains.columns.organization') },
    { key: 'state', label: t('web.admin.domains.columns.state') },
    { key: 'tls', label: t('web.admin.domains.columns.tls') },
    { key: 'created', label: t('web.admin.domains.columns.created') },
    { key: 'actions', label: t('web.admin.domains.columns.actions'), align: 'right' },
  ]);

  // ---- Guarded verify action (row + drawer) ---------------------------------

  const dialogOpen = ref(false);
  /** The domain awaiting confirmation, or currently being verified. */
  const activeDomain = ref<ColonelCustomDomain | null>(null);
  /** extid of the domain whose verify request is in flight (per-row spinner). */
  const verifyingExtid = ref<string | null>(null);
  /** The last verify outcome, read in onConfirm to pick an honest message. */
  const verifyResult = ref<ColonelDomainVerifyDetails | null>(null);

  const {
    loading: verifyLoading,
    error: verifyError,
    run: runVerify,
    reset: resetVerify,
  } = useAdminMutation(async (extid: string) => {
    // The store owns the request + ack parsing so the list, the drawer and the
    // detail page all drive the same endpoint. A 2xx means the verify ran
    // server-side regardless of ack shape; a mismatch resolves null and we fall
    // back to the generic success message.
    verifyResult.value = await store.verify(extid);
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
    const state = verifyResult.value?.current_state ?? '';
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
    // The drawer renders a row SNAPSHOT, so remember which one before the page
    // is replaced and re-point it at the refreshed row afterwards.
    const openExtid = selectedDomain.value?.extid ?? null;

    // Re-fetch the current page so every badge reflects real persisted state
    // (the verify may have flipped verified/resolving).
    await fetchPage(pagination.value?.page ?? 1);
    activeDomain.value = null;
    verifyResult.value = null;

    if (openExtid) {
      const refreshed = domains.value.find((row) => row.extid === openExtid) ?? null;
      selectedDomain.value = refreshed;
      if (!refreshed) drawerOpen.value = false;
    }
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeDomain.value = null;
    resetVerify();
  }

  // ---- Detail drawer (read-only summary + escalation) -----------------------

  const drawerOpen = ref(false);
  const selectedDomain = ref<ColonelCustomDomain | null>(null);

  /** Read-only summary rows for the drawer's field grid. */
  const drawerFields = computed(() => {
    const d = selectedDomain.value;
    if (!d) return [];
    return [
      {
        key: 'publicId',
        label: t('web.admin.domains.fields.publicId'),
        value: d.extid,
        mono: true,
      },
      {
        key: 'organization',
        label: t('web.admin.domains.fields.organization'),
        value: d.org_name || t('web.admin.domains.detail.none'),
        mono: false,
      },
      {
        key: 'baseDomain',
        label: t('web.admin.domains.fields.baseDomain'),
        value: d.base_domain || t('web.admin.domains.detail.none'),
        mono: true,
      },
      {
        key: 'subdomain',
        label: t('web.admin.domains.fields.subdomain'),
        value: d.subdomain || t('web.admin.domains.detail.none'),
        mono: true,
      },
      {
        key: 'created',
        label: t('web.admin.domains.fields.created'),
        value: formatDisplayDateTime(d.created),
        mono: false,
      },
      {
        key: 'updated',
        label: t('web.admin.domains.fields.updated'),
        value: d.updated ? formatDisplayDateTime(d.updated) : t('web.admin.domains.detail.never'),
        mono: false,
      },
    ];
  });

  function openDetail(row: ColonelCustomDomain): void {
    selectedDomain.value = row;
    drawerOpen.value = true;
  }

  /** Yes/no label for the drawer's boolean stat tiles. */
  function yesNo(value: boolean): string {
    return value ? t('web.admin.domains.detail.yes') : t('web.admin.domains.detail.no');
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
      const res = await $api.get(`/api/colonel/organizations/${encodeURIComponent(org.extid)}`);
      const parsed = gracefulParse(
        colonelOrganizationDetailResponseSchema,
        res.data,
        'ColonelOrganizationDetailResponse'
      );
      orgDomains.value = parsed.ok ? (parsed.data.details?.domains ?? []) : [];
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
      const detail = await store.fetchDetail(extid);
      if (detail) {
        domainDetail.value = detail.record;
        domainCluster.value = detail.cluster;
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
    notifications.show(t('web.admin.domains.addDomain.created', { domain }), 'success');
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
      const outcome = await store.verify(domain.extid);
      const state = outcome?.current_state ?? '';
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
    <header
      class="mb-6 flex flex-wrap items-end justify-between gap-4 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
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
                :aria-label="
                  t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })
                "
                :title="
                  t('web.admin.domains.attach.openExternal', { domain: domain.display_domain })
                "
                class="shrink-0 rounded text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-top-right-on-square"
                  size="4" />
              </a>
              <DomainStateBadge
                :state="domain.verification_state"
                :testid="`panel-domain-state-${domain.extid}`"
                class="shrink-0" />
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <router-link
                :to="{ name: 'AdminDomainDetail', params: { id: domain.extid } }"
                :data-testid="`panel-domain-detail-${domain.extid}`"
                class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
                <OIcon
                  collection="heroicons"
                  name="arrow-right"
                  size="4" />
                {{ t('web.admin.domains.detail.openFullPage') }}
              </router-link>
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
                  :class="
                    panelVerifyingExtid === domain.extid
                      ? 'animate-spin motion-reduce:animate-none'
                      : ''
                  " />
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

    <!-- Filters (server-side: `search` + `status`, applied before pagination). -->
    <div class="mb-4">
      <FilterBar
        v-model:search="searchTerm"
        :filters="filters"
        :search-placeholder="t('web.admin.domains.list.searchPlaceholder')"
        :has-active-filters="hasActiveFilters"
        testid="domains-filterbar"
        @filter-change="onFilterChange"
        @clear="onClear" />
    </div>

    <!-- Table. `domains-grid` is the list container (kept stable for tooling);
         the DataTable inside owns loading + empty rendering. -->
    <div
      data-testid="domains-grid"
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="domains"
        row-key="domain_id"
        :loading="loading"
        clickable-rows
        testid="domains-table"
        @row-click="openDetail">
        <template #empty>
          <div
            class="px-6 py-12 text-center"
            data-testid="domains-empty">
            <OIcon
              collection="heroicons"
              name="globe-alt"
              size="8"
              class="mx-auto text-gray-300 dark:text-gray-600" />
            <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
              {{
                hasActiveFilters
                  ? t('web.admin.domains.list.emptyFilter')
                  : t('web.colonel.customDomains.empty')
              }}
            </p>
          </div>
        </template>

        <!-- Identity: logo + name + extid. The testid is the row handle. -->
        <template #cell-domain="{ row }">
          <div
            class="flex items-center gap-3"
            :data-testid="`domain-row-${row.extid}`">
            <div
              v-if="row.has_logo"
              class="size-8 shrink-0 overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
              <img
                :src="row.logo_url ?? undefined"
                :alt="`${row.display_domain} logo`"
                class="size-full object-contain"
                loading="lazy" />
            </div>
            <div
              v-else
              class="flex size-8 shrink-0 items-center justify-center rounded border border-gray-200 bg-gray-100 dark:border-gray-700 dark:bg-gray-700">
              <OIcon
                collection="heroicons"
                name="globe-alt"
                size="4"
                class="text-gray-400" />
            </div>
            <div class="min-w-0">
              <div class="truncate font-medium text-gray-900 dark:text-white">
                {{ row.display_domain }}
              </div>
              <div class="truncate font-mono text-xs text-gray-400 dark:text-gray-500">
                {{ row.extid }}
              </div>
            </div>
          </div>
        </template>

        <template #cell-organization="{ row }">
          <span class="block max-w-[16rem] truncate">
            {{ row.org_name || t('web.admin.domains.detail.none') }}
          </span>
        </template>

        <!-- Verification state + the non-redundant capability flags. -->
        <template #cell-state="{ row }">
          <div class="flex items-center gap-1.5">
            <DomainStateBadge
              :state="row.verification_state"
              :testid="`domain-state-${row.extid}`" />
            <OIcon
              v-if="row.homepage_config?.enabled"
              collection="heroicons"
              name="home"
              size="4"
              class="text-purple-600 dark:text-purple-400"
              :title="t('web.colonel.customDomains.status.publicHomepage')" />
            <OIcon
              v-if="row.api_config?.enabled"
              collection="heroicons"
              name="code-bracket"
              size="4"
              class="text-purple-600 dark:text-purple-400"
              :title="t('web.colonel.customDomains.status.publicApi')" />
          </div>
        </template>

        <!-- Serving / TLS readiness. `ready` is the server's own answer to "is
             this domain resolving AND certificate-ready"; we never re-derive it. -->
        <template #cell-tls="{ row }">
          <span
            v-if="row.ready"
            class="inline-flex items-center gap-1 text-xs font-medium text-green-700 dark:text-green-400"
            :data-testid="`domain-tls-${row.extid}`">
            <OIcon
              collection="heroicons"
              name="check-badge"
              size="4" />
            {{ t('web.admin.domains.tls.serving') }}
          </span>
          <span
            v-else-if="row.resolving"
            class="inline-flex items-center gap-1 text-xs font-medium text-amber-700 dark:text-amber-400"
            :data-testid="`domain-tls-${row.extid}`">
            <OIcon
              collection="heroicons"
              name="clock"
              size="4" />
            {{ t('web.admin.domains.tls.resolving') }}
          </span>
          <span
            v-else
            class="text-xs text-gray-400 dark:text-gray-600"
            :data-testid="`domain-tls-${row.extid}`">
            {{ t('web.admin.domains.tls.none') }}
          </span>
        </template>

        <template #cell-created="{ row }">
          <span class="text-gray-500 tabular-nums dark:text-gray-400">
            {{ formatDisplayDateTime(row.created) }}
          </span>
        </template>

        <!-- Row actions. Every one stops propagation so it never also opens the
             drawer behind the click. -->
        <template #cell-actions="{ row }">
          <div class="flex items-center justify-end gap-1">
            <a
              :href="domainUrl(row.display_domain)"
              target="_blank"
              rel="noopener noreferrer"
              :data-testid="`domain-open-${row.extid}`"
              :aria-label="
                t('web.admin.domains.attach.openExternal', { domain: row.display_domain })
              "
              :title="t('web.admin.domains.attach.openExternal', { domain: row.display_domain })"
              class="rounded p-1.5 text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400"
              @click.stop>
              <OIcon
                collection="heroicons"
                name="arrow-top-right-on-square"
                size="4" />
            </a>
            <button
              type="button"
              :data-testid="`domain-verify-${row.extid}`"
              :disabled="verifyingExtid === row.extid"
              class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              @click.stop="requestVerify(row)">
              <OIcon
                collection="heroicons"
                :name="verifyingExtid === row.extid ? 'arrow-path' : 'shield-check'"
                size="4"
                :class="
                  verifyingExtid === row.extid ? 'animate-spin motion-reduce:animate-none' : ''
                " />
              {{ t('web.admin.domains.verify.button') }}
            </button>
            <router-link
              :to="{ name: 'AdminDomainDetail', params: { id: row.extid } }"
              :data-testid="`domain-detail-${row.extid}`"
              :aria-label="t('web.admin.domains.detail.openFullPage')"
              :title="t('web.admin.domains.detail.openFullPage')"
              class="rounded p-1.5 text-gray-400 hover:text-brand-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-brand-400"
              @click.stop>
              <OIcon
                collection="heroicons"
                name="arrow-right"
                size="4" />
            </router-link>
          </div>
        </template>
      </DataTable>
    </div>

    <!-- Pagination -->
    <KitPagination
      v-if="pagination"
      :pagination="pagination"
      :loading="loading"
      class="mt-4"
      @update:page="onPageChange"
      @update:per-page="onPerPageChange" />

    <!-- Detail drawer: read-only summary + escalation to the full page. Mirrors
         the customers / organizations drawers so every row click behaves alike. -->
    <DetailDrawer
      v-model:open="drawerOpen"
      width-class="max-w-2xl"
      :title="selectedDomain?.display_domain"
      :subtitle="selectedDomain?.extid"
      testid="domains-drawer">
      <div
        v-if="selectedDomain"
        class="space-y-8">
        <section>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatCard
              :label="t('web.admin.domains.columns.state')"
              :value="
                t(
                  `web.colonel.customDomains.status.${selectedDomain.verification_state}`,
                  selectedDomain.verification_state
                )
              "
              icon="shield-check"
              testid="domain-stat-state" />
            <StatCard
              :label="t('web.admin.domains.fields.verified')"
              :value="yesNo(selectedDomain.verified)"
              icon="check-circle"
              testid="domain-stat-verified" />
            <StatCard
              :label="t('web.admin.domains.fields.resolving')"
              :value="yesNo(selectedDomain.resolving)"
              icon="signal"
              testid="domain-stat-resolving" />
            <StatCard
              :label="t('web.admin.domains.fields.ready')"
              :value="yesNo(selectedDomain.ready)"
              icon="check-badge"
              testid="domain-stat-ready" />
          </div>

          <dl class="mt-5 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
            <div
              v-for="field in drawerFields"
              :key="field.key"
              :data-testid="`domain-field-${field.key}`">
              <dt
                class="font-brand text-[11px] font-semibold tracking-[0.1em] text-gray-500 uppercase dark:text-gray-400">
                {{ field.label }}
              </dt>
              <dd
                v-if="field.mono"
                class="mt-1 inline-block rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs break-all text-gray-700 tabular-nums dark:bg-gray-800 dark:text-gray-300">
                {{ field.value }}
              </dd>
              <dd
                v-else
                class="mt-1 text-sm break-words text-gray-900 tabular-nums dark:text-gray-100">
                {{ field.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Escalation: probe / repair / transfer / remove live on the full page. -->
        <section class="flex flex-wrap gap-3 border-t border-gray-200 pt-6 dark:border-gray-800">
          <router-link
            :to="{ name: 'AdminDomainDetail', params: { id: selectedDomain.extid } }"
            class="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
            data-testid="domain-open-full-page">
            {{ t('web.admin.domains.detail.openFullPage') }}
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              size="4" />
          </router-link>
          <button
            type="button"
            data-testid="domain-drawer-verify"
            class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="selectedDomain && requestVerify(selectedDomain)">
            <OIcon
              collection="heroicons"
              name="shield-check"
              size="4" />
            {{ t('web.admin.domains.verify.button') }}
          </button>
        </section>
      </div>
    </DetailDrawer>

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
