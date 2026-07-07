<!-- src/apps/admin/views/AdminEmailTools.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { AdminConfirmDialog } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import type {
    ColonelEmailTemplate,
    ColonelEmailTestDetails,
    ColonelRateLimiter,
    ColonelRateLimitEntry,
  } from '@/schemas/api/account/responses/colonel-emailtools';
  import {
    colonelEmailTemplatesResponseSchema,
    colonelEmailPreviewResponseSchema,
    colonelEmailTestResponseSchema,
    colonelRateLimitersResponseSchema,
    colonelRateLimitInspectResponseSchema,
    colonelRateLimitResetResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-emailtools';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Email + Rate-limit Tools (ticket #44) — the Phase-3 payoff that surfaces the
   * CLI-only email diagnostics (`bin/ots email {templates,preview,test}`) and
   * rate-limiter inspection (`bin/ots ratelimit keys`) in the browser, built fresh
   * on the Slice-3 template (no `src/apps/colonel/*` / `colonelInfoStore`).
   *
   * Three sections, all disjoint under the `emailtools` namespace:
   *  - TEMPLATE PREVIEW (read-only): pick a template + format → render sample
   *    output. HTML renders in a sandboxed iframe; text shows as escaped source.
   *  - TEST SEND (guarded, low-risk one-click confirm — CONTRACT 1): preview the
   *    exact diagnostic (dry-run, no send), then send to an operator-supplied
   *    address. The real send is audited SERVER-SIDE by the op (CONTRACT 4).
   *  - RATE-LIMIT (read + guarded reset): inspect a limiter/identifier's live
   *    counter state (read-only), then RESET behind an {@link AdminConfirmDialog}
   *    typed-confirmation (retype the subject). Reset is audited SERVER-SIDE.
   *
   * Every mutation goes through {@link useAdminMutation}; nothing here logs.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const TEMPLATES_URL = '/api/colonel/email/templates';
  const TEST_URL = '/api/colonel/email/test';
  const LIMITERS_URL = '/api/colonel/ratelimit/limiters';
  const INSPECT_URL = '/api/colonel/ratelimit/inspect';
  const RESET_URL = '/api/colonel/ratelimit/reset';

  // ---- Reference lists (templates + limiters) -------------------------------

  const templates = ref<ColonelEmailTemplate[]>([]);
  const limiters = ref<ColonelRateLimiter[]>([]);

  async function loadTemplates(): Promise<void> {
    try {
      const response = await $api.get(TEMPLATES_URL);
      const parsed = gracefulParse(
        colonelEmailTemplatesResponseSchema,
        response.data,
        'ColonelEmailTemplatesResponse'
      );
      if (parsed.ok) {
        templates.value = parsed.data.record?.templates ?? [];
        if (!selectedTemplate.value && templates.value.length) {
          selectedTemplate.value = templates.value[0].name;
        }
      }
    } catch {
      // A missing list only disables the picker; the section stays usable via
      // a manual template id. No blocking error surface.
    }
  }

  async function loadLimiters(): Promise<void> {
    try {
      const response = await $api.get(LIMITERS_URL);
      const parsed = gracefulParse(
        colonelRateLimitersResponseSchema,
        response.data,
        'ColonelRateLimitersResponse'
      );
      if (parsed.ok) {
        limiters.value = parsed.data.record?.limiters ?? [];
        if (!rlKind.value && limiters.value.length) {
          rlKind.value = limiters.value[0].kind;
        }
      }
    } catch {
      // Non-blocking, as above.
    }
  }

  // ---- Section 1: template preview (read-only) ------------------------------

  const selectedTemplate = ref('');
  const previewFormat = ref<'text' | 'html'>('text');
  const previewLocale = ref('en');
  const previewBody = ref<string | null>(null);
  const previewRenderedFormat = ref<'text' | 'html'>('text');

  const selectedTemplateMeta = computed(() =>
    templates.value.find((tpl) => tpl.name === selectedTemplate.value)
  );
  /** HTML render is only offered when the template actually ships an HTML body. */
  const htmlAvailable = computed(
    () => selectedTemplateMeta.value?.formats.includes('html') ?? true
  );

  const {
    loading: previewLoading,
    error: previewError,
    run: runPreview,
    reset: resetPreview,
  } = useAdminMutation(async () => {
    previewBody.value = null;
    const response = await $api.get(
      `${TEMPLATES_URL}/${encodeURIComponent(selectedTemplate.value)}/preview`,
      { params: { format: previewFormat.value, locale: previewLocale.value || 'en' } }
    );
    const parsed = gracefulParse(
      colonelEmailPreviewResponseSchema,
      response.data,
      'ColonelEmailPreviewResponse'
    );
    if (parsed.ok) {
      previewBody.value = parsed.data.details?.body ?? '';
      previewRenderedFormat.value = (parsed.data.record?.format as 'text' | 'html') ?? 'text';
    }
  });

  async function onPreview(): Promise<void> {
    if (!selectedTemplate.value) return;
    resetPreview();
    await runPreview();
  }

  // ---- Section 2: test send (guarded, one-click confirm) --------------------

  const testTo = ref('');
  const testEnqueue = ref(false);
  const testDiagnostic = ref<ColonelEmailTestDetails | null>(null);
  const sendDialogOpen = ref(false);

  /** A minimal e-mail sanity check so the confirm button can't send garbage. */
  const testToValid = computed(() => /.+@.+\..+/.test(testTo.value.trim()));

  // Dry-run preview: shows the EXACT email that would be sent, sends nothing.
  const {
    loading: testPreviewLoading,
    error: testPreviewError,
    run: runTestPreview,
    reset: resetTestPreview,
  } = useAdminMutation(async () => {
    testDiagnostic.value = null;
    const response = await $api.post(TEST_URL, {
      to: testTo.value.trim(),
      enqueue: testEnqueue.value,
      dry_run: true,
    });
    const parsed = gracefulParse(
      colonelEmailTestResponseSchema,
      response.data,
      'ColonelEmailTestResponse'
    );
    if (parsed.ok) testDiagnostic.value = parsed.data.details ?? null;
  });

  // Real send: dispatches a live email (audited server-side).
  const {
    loading: sendLoading,
    error: sendError,
    run: runSend,
    reset: resetSend,
  } = useAdminMutation(async () => {
    const response = await $api.post(TEST_URL, {
      to: testTo.value.trim(),
      enqueue: testEnqueue.value,
      dry_run: false,
    });
    gracefulParse(colonelEmailTestResponseSchema, response.data, 'ColonelEmailTestResponse');
  });

  async function onTestPreview(): Promise<void> {
    if (!testToValid.value) return;
    resetTestPreview();
    await runTestPreview();
  }

  function requestSend(): void {
    if (!testToValid.value) return;
    resetSend();
    sendDialogOpen.value = true;
  }

  async function onSendConfirm(): Promise<void> {
    const ok = await runSend();
    if (!ok) return;
    sendDialogOpen.value = false;
    notifications.show(t('web.admin.emailtools.test.success', { to: testTo.value.trim() }), 'success');
  }

  function onSendCancel(): void {
    sendDialogOpen.value = false;
    resetSend();
  }

  // ---- Section 3: rate-limit inspect (read) + reset (guarded) ---------------

  const rlKind = ref('');
  const rlSubject = ref('');
  const rlEntries = ref<ColonelRateLimitEntry[] | null>(null);
  const resetDialogOpen = ref(false);

  const rlReady = computed(() => rlKind.value.trim() !== '' && rlSubject.value.trim() !== '');
  /** Reset is only meaningful once at least one key is known to exist. */
  const rlHasState = computed(() => (rlEntries.value ?? []).some((e) => e.exists));

  const {
    loading: inspectLoading,
    error: inspectError,
    run: runInspect,
    reset: resetInspect,
  } = useAdminMutation(async () => {
    rlEntries.value = null;
    const response = await $api.get(INSPECT_URL, {
      params: { kind: rlKind.value.trim(), subject: rlSubject.value.trim() },
    });
    const parsed = gracefulParse(
      colonelRateLimitInspectResponseSchema,
      response.data,
      'ColonelRateLimitInspectResponse'
    );
    if (parsed.ok) rlEntries.value = parsed.data.details?.entries ?? [];
  });

  const {
    loading: rlResetLoading,
    error: rlResetError,
    run: runReset,
    reset: resetResetMutation,
  } = useAdminMutation(async () => {
    const response = await $api.post(RESET_URL, {
      kind: rlKind.value.trim(),
      subject: rlSubject.value.trim(),
    });
    gracefulParse(colonelRateLimitResetResponseSchema, response.data, 'ColonelRateLimitResetResponse');
  });

  async function onInspect(): Promise<void> {
    if (!rlReady.value) return;
    resetInspect();
    await runInspect();
  }

  function requestReset(): void {
    resetResetMutation();
    resetDialogOpen.value = true;
  }

  async function onResetConfirm(): Promise<void> {
    const ok = await runReset();
    if (!ok) return;
    resetDialogOpen.value = false;
    notifications.show(t('web.admin.emailtools.ratelimit.resetSuccess'), 'success');
    // Re-inspect so the operator sees the cleared state immediately.
    await onInspect();
  }

  function onResetCancel(): void {
    resetDialogOpen.value = false;
    resetResetMutation();
  }

  function ttlLabel(entry: ColonelRateLimitEntry): string {
    if (!entry.exists) return t('web.admin.emailtools.ratelimit.absent');
    if (entry.ttl === null) return t('web.admin.emailtools.ratelimit.noExpiry');
    return `${entry.ttl}s`;
  }

  onMounted(() => {
    loadTemplates();
    loadLimiters();
  });
</script>

<template>
  <div class="mx-auto max-w-5xl space-y-8">
    <!-- Page header -->
    <div>
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.description') }}
      </p>
    </div>

    <!-- ===== Section 1: template preview (read-only) ====================== -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="preview-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.preview.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.preview.description') }}
      </p>

      <div class="flex flex-wrap items-end gap-3">
        <div class="min-w-[16rem] flex-1">
          <label
            for="preview-template"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.preview.templateLabel') }}
          </label>
          <select
            id="preview-template"
            v-model="selectedTemplate"
            data-testid="preview-template-select"
            class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
            <option
              v-for="tpl in templates"
              :key="tpl.name"
              :value="tpl.name">
              {{ tpl.name }}
            </option>
          </select>
        </div>

        <div>
          <label
            for="preview-format"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.preview.formatLabel') }}
          </label>
          <select
            id="preview-format"
            v-model="previewFormat"
            data-testid="preview-format-select"
            class="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
            <option value="text">text</option>
            <option
              value="html"
              :disabled="!htmlAvailable">
              html
            </option>
          </select>
        </div>

        <div class="w-24">
          <label
            for="preview-locale"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.preview.localeLabel') }}
          </label>
          <input
            id="preview-locale"
            v-model="previewLocale"
            type="text"
            data-testid="preview-locale-input"
            class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>

        <button
          type="button"
          data-testid="preview-run"
          :disabled="!selectedTemplate || previewLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="onPreview">
          <OIcon
            collection="heroicons"
            :name="previewLoading ? 'arrow-path' : 'eye'"
            size="4"
            :class="previewLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.emailtools.preview.button') }}
        </button>
      </div>

      <p
        v-if="previewError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="preview-error">
        {{ previewError }}
      </p>

      <!-- Rendered output -->
      <div
        v-if="previewBody !== null"
        class="mt-5 border-t border-gray-100 pt-4 dark:border-gray-800"
        data-testid="preview-result">
        <!-- HTML renders in a sandboxed iframe (no scripts, no same-origin) so
             the admin never executes template markup in the console context. -->
        <iframe
          v-if="previewRenderedFormat === 'html'"
          :srcdoc="previewBody"
          sandbox=""
          data-testid="preview-iframe"
          class="h-96 w-full rounded border border-gray-200 bg-white dark:border-gray-700"
          :title="t('web.admin.emailtools.preview.title')"></iframe>
        <!-- Text shows as ESCAPED source (never v-html). -->
        <pre
          v-else
          data-testid="preview-body"
          class="max-h-96 overflow-auto whitespace-pre-wrap break-words rounded bg-gray-50 p-4 font-mono text-sm text-gray-900 dark:bg-gray-800 dark:text-gray-100">{{ previewBody }}</pre>
      </div>
    </section>

    <!-- ===== Section 2: test send (guarded) ============================== -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="test-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.test.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.test.description') }}
      </p>

      <div class="flex flex-wrap items-end gap-3">
        <div class="min-w-[18rem] flex-1">
          <label
            for="test-to"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.test.toLabel') }}
          </label>
          <input
            id="test-to"
            v-model="testTo"
            type="email"
            data-testid="test-to-input"
            :placeholder="t('web.admin.emailtools.test.toPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <label class="inline-flex items-center gap-2 pb-2 text-sm text-gray-700 dark:text-gray-300">
          <input
            v-model="testEnqueue"
            type="checkbox"
            data-testid="test-enqueue-checkbox"
            class="rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800" />
          {{ t('web.admin.emailtools.test.enqueueLabel') }}
        </label>
        <button
          type="button"
          data-testid="test-preview"
          :disabled="!testToValid || testPreviewLoading"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="onTestPreview">
          {{ t('web.admin.emailtools.test.previewButton') }}
        </button>
        <button
          type="button"
          data-testid="test-send"
          :disabled="!testToValid || sendLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="requestSend">
          <OIcon
            collection="heroicons"
            name="paper-airplane"
            size="4" />
          {{ t('web.admin.emailtools.test.sendButton') }}
        </button>
      </div>

      <p
        v-if="testPreviewError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="test-preview-error">
        {{ testPreviewError }}
      </p>

      <!-- Dry-run diagnostic (exactly what would be sent) -->
      <div
        v-if="testDiagnostic"
        class="mt-5 space-y-2 border-t border-gray-100 pt-4 text-sm dark:border-gray-800"
        data-testid="test-diagnostic">
        <div class="grid grid-cols-1 gap-1 sm:grid-cols-2">
          <div><span class="text-gray-500 dark:text-gray-400">{{ t('web.admin.emailtools.test.provider') }}:</span> <span class="font-mono">{{ testDiagnostic.provider }}</span></div>
          <div><span class="text-gray-500 dark:text-gray-400">{{ t('web.admin.emailtools.test.host') }}:</span> <span class="font-mono">{{ testDiagnostic.host }}</span></div>
          <div><span class="text-gray-500 dark:text-gray-400">{{ t('web.admin.emailtools.test.from') }}:</span> <span class="font-mono">{{ testDiagnostic.from }}</span></div>
          <div class="sm:col-span-2"><span class="text-gray-500 dark:text-gray-400">{{ t('web.admin.emailtools.test.subject') }}:</span> <span class="font-mono">{{ testDiagnostic.subject }}</span></div>
        </div>
        <pre
          data-testid="test-body"
          class="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-gray-50 p-3 font-mono text-xs text-gray-900 dark:bg-gray-800 dark:text-gray-100">{{ testDiagnostic.text_body }}</pre>
      </div>
    </section>

    <!-- ===== Section 3: rate-limit inspect + reset ======================= -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="ratelimit-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.ratelimit.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.ratelimit.description') }}
      </p>

      <div class="flex flex-wrap items-end gap-3">
        <div class="min-w-[12rem]">
          <label
            for="rl-kind"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.ratelimit.kindLabel') }}
          </label>
          <select
            id="rl-kind"
            v-model="rlKind"
            data-testid="rl-kind-select"
            class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
            <option
              v-for="lim in limiters"
              :key="lim.kind"
              :value="lim.kind">
              {{ lim.kind }} — {{ lim.subject }}
            </option>
          </select>
        </div>
        <div class="min-w-[16rem] flex-1">
          <label
            for="rl-subject"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.ratelimit.subjectLabel') }}
          </label>
          <input
            id="rl-subject"
            v-model="rlSubject"
            type="text"
            data-testid="rl-subject-input"
            :placeholder="t('web.admin.emailtools.ratelimit.subjectPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="button"
          data-testid="rl-inspect"
          :disabled="!rlReady || inspectLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="onInspect">
          <OIcon
            collection="heroicons"
            :name="inspectLoading ? 'arrow-path' : 'magnifying-glass'"
            size="4"
            :class="inspectLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.emailtools.ratelimit.inspectButton') }}
        </button>
      </div>

      <p
        v-if="inspectError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="rl-inspect-error">
        {{ inspectError }}
      </p>

      <!-- Inspect result -->
      <div
        v-if="rlEntries"
        class="mt-5 border-t border-gray-100 pt-4 dark:border-gray-800"
        data-testid="rl-result">
        <table class="w-full text-left text-sm">
          <thead>
            <tr class="border-b border-gray-100 text-xs uppercase tracking-wider text-gray-500 dark:border-gray-800 dark:text-gray-400">
              <th class="py-2 pr-4 font-medium">{{ t('web.admin.emailtools.ratelimit.columns.key') }}</th>
              <th class="py-2 pr-4 font-medium">{{ t('web.admin.emailtools.ratelimit.columns.value') }}</th>
              <th class="py-2 font-medium">{{ t('web.admin.emailtools.ratelimit.columns.ttl') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="entry in rlEntries"
              :key="entry.key"
              class="border-b border-gray-50 last:border-0 dark:border-gray-800/50"
              :data-testid="`rl-entry-${entry.key}`">
              <td class="py-2 pr-4 font-mono text-gray-900 dark:text-white">{{ entry.key }}</td>
              <td class="py-2 pr-4 font-mono">
                <span v-if="entry.exists">{{ entry.value }}</span>
                <span v-else class="text-gray-400 dark:text-gray-600">—</span>
              </td>
              <td class="py-2 font-mono text-gray-600 dark:text-gray-400">{{ ttlLabel(entry) }}</td>
            </tr>
          </tbody>
        </table>

        <div
          v-if="!rlHasState"
          class="mt-3 text-sm text-gray-500 dark:text-gray-400"
          data-testid="rl-empty">
          {{ t('web.admin.emailtools.ratelimit.noState') }}
        </div>

        <button
          v-if="rlHasState"
          type="button"
          data-testid="rl-reset"
          class="mt-4 inline-flex items-center gap-1 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500"
          @click="requestReset">
          <OIcon
            collection="heroicons"
            name="trash"
            size="4" />
          {{ t('web.admin.emailtools.ratelimit.resetButton') }}
        </button>
      </div>
    </section>

    <!-- Test send: one-click confirm (low-risk verb — CONTRACT 1). -->
    <AdminConfirmDialog
      v-model:open="sendDialogOpen"
      :title="t('web.admin.emailtools.test.confirmTitle')"
      :description="t('web.admin.emailtools.test.confirmDescription', { to: testTo.trim() })"
      :confirm-token="undefined"
      variant="default"
      :confirm-text="t('web.admin.emailtools.test.sendButton')"
      :loading="sendLoading"
      :error="sendError"
      @confirm="onSendConfirm"
      @cancel="onSendCancel" />

    <!-- Rate-limit reset: typed-confirmation (retype the subject). -->
    <AdminConfirmDialog
      v-model:open="resetDialogOpen"
      :title="t('web.admin.emailtools.ratelimit.confirmTitle')"
      :description="t('web.admin.emailtools.ratelimit.confirmDescription', { subject: rlSubject.trim() })"
      :confirm-token="rlSubject.trim()"
      variant="danger"
      :confirm-text="t('web.admin.emailtools.ratelimit.resetButton')"
      :loading="rlResetLoading"
      :error="rlResetError"
      @confirm="onResetConfirm"
      @cancel="onResetCancel" />
  </div>
</template>
