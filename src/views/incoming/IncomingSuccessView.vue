<script setup lang="ts">
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

// Get the metadata key from the route params
const metadataKey = computed(() => route.params.key as string);

// Generate the receipt URL
const receiptUrl = computed(() => {
  if (!metadataKey.value) return '';
  return `/private/${metadataKey.value}`;
});

// Create the success info text with the receipt link
const endOfExperienceSuggestion = computed(() => {
  const template = t('incoming.end_of_experience_suggestion');
  return template.replace('{receiptUrl}', receiptUrl.value);
});

const handleCreateAnother = () => {
  router.push({ name: 'Incoming' });
};
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-8 sm:px-6 lg:px-8">
    <div class="space-y-6">
      <!-- Success Icon and Message -->
      <div class="text-center">
        <div
          class="mx-auto flex size-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/30">
          <svg
            class="size-8 text-green-600 dark:text-green-400"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M5 13l4 4L19 7" />
          </svg>
        </div>

        <h1
          class="mt-4 text-2xl font-bold text-gray-900 dark:text-gray-100">
          {{ t('incoming.success_title') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('incoming.success_description') }}
        </p>
      </div>

      <!-- Reference ID Card -->
      <div
        v-if="metadataKey"
        class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800">
        <div class="p-6">
          <h2
            class="text-sm font-medium text-gray-500 dark:text-gray-400">
            {{ t('incoming.reference_id') }}
          </h2>
          <p
            class="mt-1 font-mono text-lg text-gray-900 dark:text-gray-100">
            {{ metadataKey.slice(0, 8) }}
          </p>
        </div>
      </div>

      <!-- Info Section -->
      <div
        class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div class="flex">
          <div class="shrink-0">
            <svg
              class="size-5 text-blue-400"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true">
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clip-rule="evenodd" />
            </svg>
          </div>
          <div class="ml-3">
            <h3
              class="text-sm font-medium text-blue-800 dark:text-blue-200">
              {{ t('incoming.success_info_title') }}
            </h3>
            <p
              class="mt-2 text-sm text-blue-700 dark:text-blue-300">
              {{ t('incoming.success_info_description') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Receipt Link Suggestion -->
      <div class="text-center text-sm text-gray-600 dark:text-gray-400">
        <!-- eslint-disable-next-line vue/no-v-html -->
        <p v-html="endOfExperienceSuggestion"></p>
      </div>

      <!-- Actions -->
      <div class="flex justify-center">
        <button
          type="button"
          class="rounded-md bg-brand-600 px-6 py-2 text-sm font-medium text-white transition hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          @click="handleCreateAnother">
          {{ t('incoming.create_another') }}
        </button>
      </div>
    </div>
  </div>
</template>
