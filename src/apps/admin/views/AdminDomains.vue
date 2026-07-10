<!-- src/apps/admin/views/AdminDomains.vue -->

<script setup lang="ts">

  import { AdminConfirmDialog, KitPagination } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
  import type { ColonelCustomDomain } from '@/schemas/api/internal/responses/colonel';
  import { colonelDomainVerifyResponseSchema } from '@/schemas/api/internal/responses/colonel-domains';
  import type { ColonelDomainVerifyResponse } from '@/schemas/api/internal/responses/colonel-domains';
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
   * port). Rebuilt fresh on the Slice-3 template; it does NOT import the retiring
   * `src/apps/colonel/ColonelDomains.vue`, but preserves its card layout and
   * status badges for parity.
   *
   * - LIST via {@link useAdminDomains} (a per-resource paginated store over the
   *   existing `GET /api/colonel/domains`) + {@link KitPagination}. One server
   *   page per request (CONTRACT 1). Loading uses the shared CardGridSkeleton;
   *   icons via OIcon.
   * - The VERIFY action is the only capability beyond a straight port: it POSTs to
   *   the new `/api/colonel/domains/:extid/verify` endpoint (which reuses the
   *   existing `VerifyDomain` op and audits the verify server-side — CONTRACT 4),
   *   guarded by a one-click {@link AdminConfirmDialog} (low-risk verb — no typed
   *   confirmation) + {@link useAdminMutation}. The result is surfaced HONESTLY
   *   from the op's real DNS/SSL outcome (verified / resolving / pending /
   *   unverified) — success is never faked.
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

  // ---- Guarded verify action ------------------------------------------------

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

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.colonel.customDomains.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.colonel.customDomains.description') }}
      </p>
    </header>

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

            <!-- Verification badge -->
            <span
              :class="[
                'inline-flex flex-shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                stateBadgeClass(domain.verification_state),
              ]"
              :data-testid="`domain-state-${domain.extid}`">
              {{ stateLabel(domain.verification_state) }}
            </span>
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
  </div>
</template>
