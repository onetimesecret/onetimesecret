<!-- src/apps/admin/views/AdminBanner.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { AdminConfirmDialog, StatCard } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import {
    colonelBannerResponseSchema,
    colonelBannerSetResponseSchema,
    colonelBannerClearResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-banner';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Broadcast Banner screen (ticket #41) — the Phase-3 "operating console" surface
   * for a capability that until now lived ONLY on `bin/ots banner`. It is a NEW
   * screen (there is no legacy Vue view to port), built fresh on the Slice-3
   * template; it does NOT import `src/apps/colonel/*` or `colonelInfoStore`.
   *
   * A single settings-style screen (CONTRACT 1 — useResourceFetch, not a paginated
   * store):
   *   - GET  /api/colonel/banner → current banner (content / ttl / active)
   *   - POST /api/colonel/banner → publish/update (guarded by a one-click confirm)
   *   - DELETE /api/colonel/banner → clear (guarded by TYPED-confirmation — the
   *     banner is live to every visitor, so clearing is destructive-ish, epic #41)
   *
   * Both mutations go through {@link useAdminMutation} + the frozen
   * {@link AdminConfirmDialog} and are audited SERVER-SIDE by the extracted ops
   * ({@link Onetime::Operations::SetBanner} / `ClearBanner`); nothing here logs.
   *
   * NOTE: the banner has no severity/level concept — the CLI stores a single HTML
   * string, and to preserve CLI behaviour bit-for-bit this screen sets message +
   * optional TTL only. The stored content is raw HTML; it is shown here as escaped
   * text (never v-html) — the customer site sanitizes to <a> tags on render.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const BANNER_URL = '/api/colonel/banner';

  /** Fixed token the operator retypes to confirm a destructive clear. */
  const CLEAR_CONFIRM_TOKEN = 'clear';

  // ---- Current banner (read) ------------------------------------------------

  const {
    data: bannerData,
    loading,
    error,
    validationError,
    load: loadBanner,
  } = useResourceFetch({
    url: BANNER_URL,
    schema: colonelBannerResponseSchema,
    context: 'ColonelBannerResponse',
  });

  const banner = computed(() => bannerData.value?.record ?? null);
  const isActive = computed(() => banner.value?.active ?? false);
  const currentContent = computed(() => banner.value?.content ?? '');
  const currentTtl = computed(() => banner.value?.ttl ?? null);
  const loadFailed = computed(() => error.value !== null || validationError.value !== null);

  function reloadBanner(): void {
    loadBanner().catch(() => {});
  }

  /** Human-readable TTL, mirroring the CLI's `humanize_seconds`. */
  function humanizeTtl(seconds: number): string {
    if (seconds >= 86400) return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
    if (seconds >= 3600) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    if (seconds >= 60) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    return `${seconds}s`;
  }

  const ttlLabel = computed(() =>
    currentTtl.value === null
      ? t('web.admin.banner.current.persistent')
      : t('web.admin.banner.current.expiresIn', { duration: humanizeTtl(currentTtl.value) })
  );

  // ---- Set form -------------------------------------------------------------

  const formContent = ref('');
  const formTtl = ref('');

  /** Hard cap mirroring the backend SetBanner MAX_CONTENT_LENGTH. */
  const MAX_CONTENT_LENGTH = 2000;
  const contentTooLong = computed(() => formContent.value.length > MAX_CONTENT_LENGTH);
  const canPublish = computed(() => formContent.value.trim().length > 0 && !contentTooLong.value);

  /** Prefill the form from the live banner so an operator can tweak-then-publish. */
  function editCurrent(): void {
    formContent.value = currentContent.value;
    formTtl.value = currentTtl.value === null ? '' : String(currentTtl.value);
  }

  // ---- Guarded mutations (D4) ----------------------------------------------

  type ActionKey = 'set' | 'clear';

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    if (activeAction.value === 'set') {
      const ttlNum = Number.parseInt(formTtl.value, 10);
      const response = await $api.post(BANNER_URL, {
        content: formContent.value,
        ttl: Number.isFinite(ttlNum) && ttlNum > 0 ? ttlNum : undefined,
      });
      gracefulParse(colonelBannerSetResponseSchema, response.data, 'ColonelBannerSetResponse');
    } else {
      const response = await $api.delete(BANNER_URL);
      gracefulParse(colonelBannerClearResponseSchema, response.data, 'ColonelBannerClearResponse');
    }
  });

  const dialogConfig = computed(() => {
    if (activeAction.value === 'clear') {
      return {
        title: t('web.admin.banner.clear.confirmTitle'),
        description: t('web.admin.banner.clear.confirmDescription'),
        confirmToken: CLEAR_CONFIRM_TOKEN,
        confirmText: t('web.admin.banner.clear.button'),
        variant: 'danger' as const,
      };
    }
    return {
      title: t('web.admin.banner.set.confirmTitle'),
      description: t('web.admin.banner.set.confirmDescription'),
      confirmToken: undefined,
      confirmText: t('web.admin.banner.set.confirmButton'),
      variant: 'default' as const,
    };
  });

  function requestSet(): void {
    if (!canPublish.value) return;
    activeAction.value = 'set';
    resetMutation();
    dialogOpen.value = true;
  }

  function requestClear(): void {
    activeAction.value = 'clear';
    resetMutation();
    dialogOpen.value = true;
  }

  async function onConfirm(): Promise<void> {
    const action = activeAction.value;
    if (!action) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;

    if (action === 'set') {
      notifications.show(t('web.admin.banner.set.success'), 'success');
    } else {
      notifications.show(t('web.admin.banner.clear.success'), 'success');
      // The live banner is gone; drop the form so it can't be re-published blindly.
      formContent.value = '';
      formTtl.value = '';
    }

    activeAction.value = null;
    reloadBanner();
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    resetMutation();
  }

  onMounted(reloadBanner);
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.banner.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.banner.description') }}
      </p>
    </div>

    <!-- Load error banner -->
    <div
      v-if="loadFailed"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="banner-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.banner.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="reloadBanner">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.banner.retry') }}
      </button>
    </div>

    <!-- ================= Current banner ================= -->
    <section
      class="mb-8"
      data-testid="banner-current">
      <h3 class="mb-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.banner.current.title') }}
      </h3>

      <!-- Loading -->
      <div
        v-if="loading && !banner"
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
        data-testid="banner-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>

      <!-- Active banner -->
      <div
        v-else-if="isActive"
        class="space-y-4"
        data-testid="banner-active">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <StatCard
            :label="t('web.admin.banner.current.status')"
            :value="t('web.admin.banner.current.live')"
            icon="bell"
            testid="stat-status" />
          <StatCard
            :label="t('web.admin.banner.current.expiry')"
            :value="ttlLabel"
            icon="clock"
            testid="stat-expiry" />
        </div>

        <!-- Stored content, shown as ESCAPED text (never v-html). -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <h4 class="mb-2 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.banner.current.storedContent') }}
          </h4>
          <pre
            data-testid="banner-content"
            class="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-gray-50 p-3 font-mono text-sm text-gray-900 dark:bg-gray-800 dark:text-gray-100">{{ currentContent }}</pre>
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.admin.banner.current.htmlNote') }}
          </p>
        </div>

        <!-- Actions on the live banner -->
        <div class="flex flex-wrap gap-3">
          <button
            type="button"
            data-testid="banner-edit"
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-800"
            @click="editCurrent">
            <OIcon
              collection="heroicons"
              name="pencil-square"
              size="4" />
            {{ t('web.admin.banner.current.edit') }}
          </button>
          <button
            type="button"
            data-testid="banner-clear"
            class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
            @click="requestClear">
            <OIcon
              collection="heroicons"
              name="trash"
              size="4" />
            {{ t('web.admin.banner.clear.button') }}
          </button>
        </div>
      </div>

      <!-- No banner -->
      <div
        v-else
        class="rounded-lg border border-dashed border-gray-300 bg-white px-4 py-8 text-center text-sm text-gray-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-400"
        data-testid="banner-empty">
        {{ t('web.admin.banner.current.none') }}
      </div>
    </section>

    <!-- ================= Set / update form ================= -->
    <section data-testid="banner-form">
      <h3 class="mb-3 text-lg font-medium text-gray-900 dark:text-white">
        {{ isActive ? t('web.admin.banner.set.updateTitle') : t('web.admin.banner.set.title') }}
      </h3>

      <div
        class="space-y-4 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div>
          <label
            for="banner-content-input"
            class="mb-1 block text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.banner.set.contentLabel') }}
          </label>
          <textarea
            id="banner-content-input"
            v-model="formContent"
            data-testid="banner-content-input"
            rows="4"
            spellcheck="false"
            :placeholder="t('web.admin.banner.set.contentPlaceholder')"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white"></textarea>
          <div class="mt-1 flex items-center justify-between">
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.banner.set.contentHelp') }}
            </p>
            <span
              class="text-xs"
              :class="contentTooLong ? 'text-red-600 dark:text-red-400' : 'text-gray-400 dark:text-gray-500'"
              data-testid="banner-charcount">
              {{ formContent.length }} / {{ MAX_CONTENT_LENGTH }}
            </span>
          </div>
        </div>

        <div class="sm:w-1/2">
          <label
            for="banner-ttl-input"
            class="mb-1 block text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.banner.set.ttlLabel') }}
          </label>
          <input
            id="banner-ttl-input"
            v-model="formTtl"
            type="number"
            min="0"
            inputmode="numeric"
            data-testid="banner-ttl-input"
            :placeholder="t('web.admin.banner.set.ttlPlaceholder')"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.admin.banner.set.ttlHelp') }}
          </p>
        </div>

        <div class="flex justify-end">
          <button
            type="button"
            data-testid="banner-publish"
            :disabled="!canPublish"
            class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
            @click="requestSet">
            <OIcon
              collection="heroicons"
              name="bell"
              size="4" />
            {{ isActive ? t('web.admin.banner.set.updateButton') : t('web.admin.banner.set.publishButton') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Shared guarded-action dialog: one-click for set, typed-confirm for clear. -->
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
