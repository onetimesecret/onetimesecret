<!-- src/apps/admin/views/AdminOverview.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';

  import OIcon from '@/shared/components/icons/OIcon.vue';

  import { CONSOLE_SECTIONS } from '../console-sections';

  const { t } = useI18n();
</script>

<!--
  Phase-0 landing screen for the rebuilt Colonel admin console.

  This is deliberately a skeleton: it renders the console map (the same
  sections as the sidebar) so the operator can see what the console will
  become, with only the live sections navigable. Real dashboards, stat tiles
  and per-resource screens arrive in later phases (docs/specs/colonel-ui/).
-->
<template>
  <div class="mx-auto max-w-6xl">
    <div class="mb-6 flex items-center gap-3">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.colonel.titles.index') }}
      </h2>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <component
        :is="section.to ? 'router-link' : 'div'"
        v-for="section in CONSOLE_SECTIONS"
        :key="section.key"
        :to="section.to"
        class="flex items-center gap-4 rounded-lg border p-4 transition-shadow"
        :class="
          section.to
            ? 'border-gray-200 bg-white shadow-sm hover:shadow-md dark:border-gray-800 dark:bg-gray-800'
            : 'cursor-not-allowed border-dashed border-gray-200 bg-gray-50 dark:border-gray-800 dark:bg-gray-900'
        "
        :aria-disabled="section.to ? undefined : 'true'">
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-lg"
          :class="
            section.to
              ? 'bg-brand-50 text-brand-600 dark:bg-brand-900/20 dark:text-brand-400'
              : 'bg-gray-100 text-gray-400 dark:bg-gray-800 dark:text-gray-600'
          ">
          <OIcon
            collection="heroicons"
            :name="section.icon"
            size="6" />
        </span>
        <span
          class="font-medium"
          :class="
            section.to ? 'text-gray-900 dark:text-white' : 'text-gray-400 dark:text-gray-600'
          ">
          {{ t(section.labelKey) }}
        </span>
      </component>
    </div>
  </div>
</template>
