<!-- src/apps/admin/components/domains/DomainConfigStatusBadge.vue -->

<script setup lang="ts">
  import type { DomainConfigStatus } from '@/apps/admin/components/domains/domainConfigTypes';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Status pill for one per-domain config row (the {@link DomainStateBadge}
   * shape, specialised to config lifecycle states).
   *
   * Presentational only: the parent derives the honest status — including the
   * "exists but failed to hydrate" case that still reads `missing` — and this
   * renders it with one colour map and one label family
   * (`web.admin.domains.configs.status.*`).
   */
  const props = withDefaults(
    defineProps<{
      /** Derived lifecycle state for the record. */
      status: DomainConfigStatus;
      /** Optional test id for the pill (`config-status-<kind>`). */
      testid?: string;
    }>(),
    { testid: undefined }
  );

  const { t } = useI18n();

  const STATUS_BADGE_CLASSES: Record<DomainConfigStatus, string> = {
    missing: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
    disabled: 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300',
    enabled: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200',
    enabledNotReady: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200',
  };

  const badgeClass = computed(() => STATUS_BADGE_CLASSES[props.status]);
  const label = computed(() => t(`web.admin.domains.configs.status.${props.status}`));
</script>

<template>
  <span
    :class="['inline-flex items-center rounded px-2 py-0.5 text-xs font-medium', badgeClass]"
    :data-testid="testid">
    {{ label }}
  </span>
</template>
