<!-- src/apps/workspace/components/settings/SettingsSection.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';

interface IconConfig {
  collection: string;
  name: string;
}

defineProps<{
  /** Section title */
  title: string;
  /** Optional icon configuration */
  icon?: IconConfig;
  /** Optional description text */
  description?: string;
  /** Whether to show the header section (default: true) */
  showHeader?: boolean;
}>();

defineSlots<{
  /** Main content slot */
  default(): unknown;
  /** Optional header actions slot */
  actions?(): unknown;
}>();
</script>

<template>
  <section class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
    <!-- Header -->
    <div
      v-if="showHeader !== false && (title || $slots.actions)"
      class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <OIcon
            v-if="icon"
            :collection="icon.collection"
            :name="icon.name"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ title }}
            </h2>
            <p
              v-if="description"
              class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
              {{ description }}
            </p>
          </div>
        </div>
        <div v-if="$slots.actions">
          <slot name="actions" ></slot>
        </div>
      </div>
    </div>

    <!-- Content -->
    <div class="px-6 py-4">
      <slot ></slot>
    </div>
  </section>
</template>
