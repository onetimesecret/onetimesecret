<!-- src/apps/admin/components/kit/SchemaIssueList.vue -->

<script setup lang="ts">
  import type { SchemaIssue } from '@/utils/schemaValidation';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The fields of an API response that failed schema validation, so an
   * operator can see the cause on the page instead of copying the payload out
   * of devtools. Paths and Zod's type-level messages only, never field values
   * (see {@link SchemaIssue}).
   */
  const props = withDefaults(
    defineProps<{
      issues: SchemaIssue[];
      /** Issues listed before collapsing the rest into a count. */
      limit?: number;
    }>(),
    { limit: 10 }
  );

  const { t } = useI18n();

  const shown = computed(() => props.issues.slice(0, props.limit));
  const hiddenCount = computed(() => props.issues.length - shown.value.length);
</script>

<template>
  <ul
    class="space-y-1 font-mono text-xs break-all"
    data-testid="schema-issues">
    <li
      v-for="(issue, index) in shown"
      :key="index">
      <span class="font-semibold">{{ issue.path }}:</span> {{ issue.message }}
    </li>
    <li
      v-if="hiddenCount > 0"
      class="font-sans italic">
      {{ t('web.admin.kit.schemaIssues.more', { count: hiddenCount }) }}
    </li>
  </ul>
</template>
