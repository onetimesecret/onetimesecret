<!-- src/apps/admin/views/AdminEmailTools.vue -->

<script setup lang="ts">

  import EmailDeliverabilitySection from '@/apps/admin/components/EmailDeliverabilitySection.vue';
  import { AdminConfirmDialog, StatCard } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelEmailTemplate,
    ColonelEmailTestDetails,
  } from '@/schemas/api/internal/responses/colonel-emailtools';
  import {
    colonelEmailConfigResponseSchema,
    colonelEmailTemplatesResponseSchema,
    colonelEmailPreviewResponseSchema,
    colonelEmailTestResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-emailtools';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Email Tools (ticket #44) — the Phase-3 payoff that surfaces the CLI-only
   * email diagnostics (`bin/ots email {templates,preview,test}`) in the browser,
   * built fresh on the Slice-3 template (no `src/apps/colonel/*` /
   * `colonelInfoStore`).
   *
   * Three sections, all disjoint under the `emailtools` namespace:
   *  - TEMPLATE PREVIEW (read-only): pick a template + format → render sample
   *    output. HTML renders in a sandboxed iframe; text shows as escaped source.
   *  - TEST SEND (guarded, low-risk one-click confirm — CONTRACT 1): preview the
   *    exact diagnostic (dry-run, no send), then send to an operator-supplied
   *    address. The real send is audited SERVER-SIDE by the op (CONTRACT 4).
   *  - DELIVERABILITY (the receiving side — bounces, complaints, suppression
   *    list): self-contained in {@link EmailDeliverabilitySection}, which owns
   *    its own fetches and guarded remove.
   *
   * The rate-limit inspect/reset half was removed by design review (YAGNI —
   * the endpoints and `bin/ots ratelimit` CLI remain the operator surface).
   *
   * Every mutation goes through {@link useAdminMutation}; nothing here logs.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const CONFIG_URL = '/api/colonel/email/config';
  const TEMPLATES_URL = '/api/colonel/email/templates';
  const TEST_URL = '/api/colonel/email/test';

  // ---- Mailer configuration (ITEM 1) + safety banner (ITEM 4) ---------------
  // A single read-only fetch feeds the top-of-page config panel AND the
  // logger/dropped safety banner (banner reads `details.provider === 'logger'`).

  const {
    data: configData,
    loading: configLoading,
    load: loadConfig,
  } = useResourceFetch({
    url: CONFIG_URL,
    schema: colonelEmailConfigResponseSchema,
    context: 'ColonelEmailConfigResponse',
  });

  const config = computed(() => configData.value?.details ?? null);
  /**
   * ITEM 4: mail is not delivered. `logger` writes to the app log; `disabled`
   * and `none` succeed silently with no side effects (see
   * lib/onetime/mail/delivery/disabled.rb). All three are silent-drop modes an
   * operator needs warned about, so the banner covers the whole set.
   */
  const NON_DELIVERING_MODES = ['logger', 'disabled', 'none'];
  const isLoggerMode = computed(() =>
    NON_DELIVERING_MODES.includes(config.value?.provider ?? '')
  );

  function reloadConfig(): void {
    loadConfig().catch(() => {}); // read-only; a failure just hides the panel
  }

  // ---- Reference lists (templates) ------------------------------------------

  const templates = ref<ColonelEmailTemplate[]>([]);

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

  onMounted(() => {
    reloadConfig();
    loadTemplates();
  });
</script>

<template>
  <div class="mx-auto max-w-5xl space-y-8">
    <!-- ITEM 4: send-mode / safety banner. Prominent amber alert shown ONLY when
         the resolved transport is 'logger' (mail is logged/dropped, not sent).
         Driven entirely off the ITEM-1 config response. -->
    <div
      v-if="isLoggerMode"
      class="flex items-start gap-3 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 dark:border-amber-900/50 dark:bg-amber-900/20"
      role="alert"
      data-testid="emailtools-logger-banner">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        size="5"
        class="mt-0.5 shrink-0 text-amber-600 dark:text-amber-400" />
      <p class="text-sm font-medium text-amber-800 dark:text-amber-200">
        {{ t('web.admin.emailtools.config.loggerWarning') }}
      </p>
    </div>

    <!-- Page header -->
    <header class="border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.description') }}
      </p>
    </header>

    <!-- ===== Mailer configuration (ITEM 1, read-only) ==================== -->
    <section
      class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="config-section">
      <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.config.title') }}
      </h3>
      <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.config.description') }}
      </p>

      <div
        v-if="config || configLoading"
        class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
        data-testid="config-grid">
        <StatCard
          :label="t('web.admin.emailtools.config.provider')"
          :value="config?.provider ?? '—'"
          icon="server-stack"
          :loading="configLoading"
          testid="config-stat-provider" />
        <StatCard
          :label="t('web.admin.emailtools.config.senderProvider')"
          :value="config?.sender_provider ?? '—'"
          icon="paper-airplane"
          :loading="configLoading"
          testid="config-stat-sender-provider" />
        <StatCard
          :label="t('web.admin.emailtools.config.senderDiffers')"
          icon="arrows-right-left"
          :loading="configLoading"
          testid="config-stat-sender-differs">
          <span :class="config?.sender_differs ? 'text-amber-600 dark:text-amber-400' : ''">
            {{
              config?.sender_differs
                ? t('web.admin.emailtools.config.yes')
                : t('web.admin.emailtools.config.no')
            }}
          </span>
        </StatCard>
        <StatCard
          :label="t('web.admin.emailtools.config.fromAddress')"
          :value="config?.from_address || '—'"
          icon="at-symbol"
          :loading="configLoading"
          testid="config-stat-from-address" />
        <StatCard
          :label="t('web.admin.emailtools.config.fromName')"
          :value="config?.from_name || '—'"
          icon="identification"
          :loading="configLoading"
          testid="config-stat-from-name" />
        <StatCard
          :label="t('web.admin.emailtools.config.autoDetected')"
          :value="
            config?.auto_detected
              ? t('web.admin.emailtools.config.yes')
              : t('web.admin.emailtools.config.no')
          "
          icon="sparkles"
          :loading="configLoading"
          testid="config-stat-auto-detected" />
        <StatCard
          :label="t('web.admin.emailtools.config.host')"
          :value="config?.provider_config.host ?? '—'"
          icon="globe-alt"
          :loading="configLoading"
          testid="config-stat-host" />
        <StatCard
          :label="t('web.admin.emailtools.config.port')"
          :value="config?.provider_config.port ?? '—'"
          icon="hashtag"
          :loading="configLoading"
          testid="config-stat-port" />
        <StatCard
          :label="t('web.admin.emailtools.config.region')"
          :value="config?.provider_config.region ?? '—'"
          icon="map-pin"
          :loading="configLoading"
          testid="config-stat-region" />
        <StatCard
          :label="t('web.admin.emailtools.config.hasCredentials')"
          :value="
            config?.provider_config.has_credentials
              ? t('web.admin.emailtools.config.yes')
              : t('web.admin.emailtools.config.no')
          "
          icon="key"
          :loading="configLoading"
          testid="config-stat-has-credentials" />
      </div>
    </section>

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
            <option value="text">
              text
            </option>
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
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
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
          class="max-h-96 overflow-auto rounded bg-gray-50 p-4 font-mono text-sm break-words whitespace-pre-wrap text-gray-900 dark:bg-gray-800 dark:text-gray-100">{{ previewBody }}</pre>
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
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="onTestPreview">
          {{ t('web.admin.emailtools.test.previewButton') }}
        </button>
        <button
          type="button"
          data-testid="test-send"
          :disabled="!testToValid || sendLoading"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
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
          <div class="sm:col-span-2">
            <span class="text-gray-500 dark:text-gray-400">{{ t('web.admin.emailtools.test.subject') }}:</span> <span class="font-mono">{{ testDiagnostic.subject }}</span>
          </div>
        </div>
        <pre
          data-testid="test-body"
          class="max-h-48 overflow-auto rounded bg-gray-50 p-3 font-mono text-xs break-words whitespace-pre-wrap text-gray-900 dark:bg-gray-800 dark:text-gray-100">{{ testDiagnostic.text_body }}</pre>
      </div>
    </section>

    <!-- ===== Section 3: deliverability (bounces / complaints / suppressions) -->
    <EmailDeliverabilitySection />

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
  </div>
</template>
