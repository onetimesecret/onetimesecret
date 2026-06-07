<!-- src/apps/colonel/components/ColonelListPage.vue -->

<script setup lang="ts">
import ColonelFetchError from '@/apps/colonel/components/ColonelFetchError.vue';
import { useSlots } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps<{
  loading: boolean;
  title: string;
  description?: string;
  fetchError?: string | null;
  resource?: string;
}>();

const { t } = useI18n();
const slots = useSlots();
</script>

<template>
  <div>
    <!-- Back navigation (always visible) -->
    <div class="mb-4">
      <router-link
        to="/colonel"
        class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        <svg
          class="mr-1 size-4"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M15 19l-7-7 7-7" />
        </svg>
        {{ t('web.COMMON.back') }}
      </router-link>
    </div>

    <!-- Page header -->
    <div class="mb-6">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
        {{ title }}
      </h1>
      <p
        v-if="description"
        class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ description }}
      </p>
    </div>

    <!-- Header extra slot (for filter bars) -->
    <slot name="header-extra" ></slot>

    <!-- Count slot -->
    <div
      v-if="slots.count"
      class="mb-4 text-sm text-gray-600 dark:text-gray-400">
      <slot name="count" ></slot>
    </div>

    <!-- Fetch error -->
    <ColonelFetchError
      v-if="fetchError"
      :schema="fetchError"
      :resource="resource ?? 'data'" />

    <!-- Loading state -->
    <div
      v-if="loading"
      class="py-12 text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <!-- Content slot (when not loading and no error) -->
    <slot v-else-if="!fetchError" ></slot>
  </div>
</template>
