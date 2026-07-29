<!-- src/apps/admin/components/domains/DomainConfigsHeader.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Section header for {@link DomainConfigsSection}: title, description, and
   * the "Create missing configs" (ensure) entry point with its preview error.
   *
   * Presentational only — the parent owns the ensure orchestration (dry-run
   * preview mutation → confirm dialog) and passes its loading/error state in;
   * this just renders the button when a materializable kind is missing and
   * surfaces a failed/degraded preview under it (instead of a dead dialog).
   */
  defineProps<{
    /** Show the ensure button (some materializable kind is missing). */
    ensureVisible: boolean;
    /** True while the dry-run preview is in flight. */
    ensureLoading: boolean;
    /** Preview failure/degrade message, or null. */
    ensureError: string | null;
  }>();

  const emit = defineEmits<{
    /** Operator asked to preview + apply the missing configs. */
    ensure: [];
  }>();

  const { t } = useI18n();
</script>

<template>
  <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.domains.configs.title') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.domains.configs.description') }}
        </p>
      </div>
      <button
        v-if="ensureVisible"
        type="button"
        data-testid="config-ensure"
        :disabled="ensureLoading"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="emit('ensure')">
        <OIcon
          collection="heroicons"
          :name="ensureLoading ? 'arrow-path' : 'plus-circle'"
          size="4"
          :class="ensureLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
        {{ t('web.admin.domains.configs.ensure.button') }}
      </button>
    </div>
    <p
      v-if="ensureError"
      class="mt-2 text-sm text-red-700 dark:text-red-300"
      role="alert"
      data-testid="config-ensure-error">
      {{ ensureError }}
    </p>
  </div>
</template>
