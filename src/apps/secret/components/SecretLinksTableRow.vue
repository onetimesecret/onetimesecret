<!-- src/apps/secret/components/SecretLinksTableRow.vue -->
<!--
  A/B Test Variant Loader for SecretLinksTableRow.

  Dynamically loads one of the available row design variants based on the
  `variant` prop. This enables A/B testing different UI approaches.

  Available variants:
    - "timeline" (default): Original design with vertical timeline connector,
                            badge-based status, icon actions
    - "console":            Monospace precision design with tree-style metadata,
                            ASCII characters, text-button actions

  Usage:
    <SecretLinksTableRow
      :record="secret"
      :index="idx"
      :is-last="idx === secrets.length - 1"
      variant="console"
      @copy="handleCopy"
      @delete="handleDelete"
      @update:memo="handleMemoUpdate"
    />
-->

<script setup lang="ts">
  import { computed, defineAsyncComponent } from 'vue';
  import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';

  /**
   * Available A/B test variants for the row design.
   */
  export type RowVariant = 'timeline' | 'console';

  const props = withDefaults(
    defineProps<{
      record: RecentSecretRecord;
      /** Row index (1-based) for visual reference */
      index: number;
      /** Whether this is the last item (affects connector/separator display) */
      isLast?: boolean;
      /** A/B test variant to render */
      variant?: RowVariant;
    }>(),
    {
      isLast: false,
      variant: 'console',
    }
  );

  defineEmits<{
    copy: [];
    delete: [record: RecentSecretRecord];
    'update:memo': [id: string, memo: string];
  }>();

  // Async component loading for code splitting
  const variantComponents = {
    timeline: defineAsyncComponent(
      () => import('./SecretLinksTableRowTimeline.vue')
    ),
    console: defineAsyncComponent(
      () => import('./SecretLinksTableRowConsole.vue')
    ),
  };

  const ActiveComponent = computed(() => variantComponents[props.variant] ?? variantComponents.timeline);
</script>

<template>
  <component
    :is="ActiveComponent"
    :record="record"
    :index="index"
    :is-last="isLast"
    @copy="$emit('copy')"
    @delete="$emit('delete', $event)"
    @update:memo="(id: string, memo: string) => $emit('update:memo', id, memo)" />
</template>
