<!-- src/apps/admin/components/kit/JsonViewer.vue -->

<script setup lang="ts">
  import { computed, reactive } from 'vue';
  import { useI18n } from 'vue-i18n';

  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';

  import JsonViewerNode from './JsonViewerNode.vue';
  import type { JsonViewerSignal } from './jsonViewerKeys';

  /**
   * Pretty, collapsible JSON inspector for raw admin record inspection
   * (ticket #11). Renders a syntax-coloured, keyboard-toggleable tree via the
   * recursive {@link JsonViewerNode}, with a toolbar to expand/collapse the whole
   * tree and copy the pretty-printed source (reusing the shared `CopyButton`).
   *
   * This is a READ-only inspector: it never mutates or transmits the value. The
   * kit deliberately does not redact here — callers that inspect sensitive
   * records must strip secrets/tokens before passing them in (the audit-log
   * redaction rule, CONTRACT 6, governs what is ever persisted).
   */
  const props = withDefaults(
    defineProps<{
      /** The value to render. Any JSON-serialisable shape. */
      data: unknown;
      /** Depth (exclusive) that starts expanded. Defaults to 1 (top level). */
      expandDepth?: number;
      /** Show the toolbar (copy + expand/collapse all). Defaults to true. */
      showToolbar?: boolean;
      /** Test id applied to the root. */
      testid?: string;
    }>(),
    {
      expandDepth: 1,
      showToolbar: true,
      testid: undefined,
    }
  );

  const { t } = useI18n();

  // Shared object reference threaded down the tree; nodes watch `version`.
  const signal = reactive<JsonViewerSignal>({ version: 0, expanded: true });

  const isEmpty = computed(() => props.data === null || props.data === undefined);

  const prettyJson = computed(() => {
    try {
      return JSON.stringify(props.data, null, 2);
    } catch {
      return '';
    }
  });

  function expandAll(): void {
    signal.expanded = true;
    signal.version += 1;
  }

  function collapseAll(): void {
    signal.expanded = false;
    signal.version += 1;
  }
</script>

<template>
  <div
    :data-testid="testid"
    class="rounded-md border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
    <!-- Toolbar -->
    <div
      v-if="showToolbar && !isEmpty"
      class="flex items-center justify-end gap-1 border-b border-gray-200 px-2 py-1 dark:border-gray-700">
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-200 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:text-gray-400 dark:hover:bg-gray-800"
        @click="expandAll">
        <OIcon
          collection="heroicons"
          name="chevron-down"
          size="4" />
        {{ t('web.admin.kit.jsonViewer.expandAll') }}
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-200 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:text-gray-400 dark:hover:bg-gray-800"
        @click="collapseAll">
        <OIcon
          collection="heroicons"
          name="chevron-right"
          size="4" />
        {{ t('web.admin.kit.jsonViewer.collapseAll') }}
      </button>
      <CopyButton
        :text="prettyJson"
        :tooltip="t('web.admin.kit.jsonViewer.copyLabel')"
        :testid="testid ? `${testid}-copy` : undefined" />
    </div>

    <!-- Tree -->
    <div class="overflow-x-auto p-3 font-mono text-sm">
      <p
        v-if="isEmpty"
        class="text-gray-400 dark:text-gray-500">
        {{ t('web.admin.kit.jsonViewer.empty') }}
      </p>
      <JsonViewerNode
        v-else
        :value="data"
        :depth="0"
        :expand-depth="expandDepth"
        :signal="signal" />
    </div>
  </div>
</template>
