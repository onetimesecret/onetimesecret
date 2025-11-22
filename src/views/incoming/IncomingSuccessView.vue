<!-- src/views/incoming/IncomingSuccessView.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import { useRoute, useRouter } from 'vue-router';

  const route = useRoute();
  const router = useRouter();

  const metadataKey = computed(() => route.params.metadataKey as string);

  const handleCreateAnother = () => {
    router.push({ name: 'IncomingSecretForm' });
  };

  const handleViewRecent = () => {
    router.push({ name: 'Recent' });
  };
</script>

<template>
  <div class="min-h-screen bg-gray-50 py-8 dark:bg-slate-900">
    <div class="mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
      <div class="rounded-lg bg-white p-8 shadow-sm dark:bg-slate-800">
        <!-- Success Icon -->
        <div class="mb-6 flex justify-center">
          <div class="flex size-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-900/30">
            <svg
              class="size-8 text-green-600 dark:text-green-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7" />
            </svg>
          </div>
        </div>

        <!-- Success Message -->
        <div class="text-center">
          <h1 class="mb-2 text-2xl font-bold text-gray-900 dark:text-white">
            {{ $t('web.incoming.success_title') }}
          </h1>
          <p class="mb-6 text-gray-600 dark:text-gray-400">
            {{ $t('web.incoming.success_description') }}
          </p>

          <!-- Metadata Key Display (optional, for reference) -->
          <div
            v-if="metadataKey"
            class="mb-6 rounded-lg bg-gray-50 p-4 dark:bg-slate-700">
            <p class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.incoming.reference_id') }}
            </p>
            <code class="break-all text-sm text-gray-900 dark:text-white">
              {{ metadataKey }}
            </code>
          </div>

          <!-- Information Box -->
          <div class="mb-6 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/30">
            <div class="flex items-start">
              <svg
                class="mr-3 size-5 flex-shrink-0 text-blue-600 dark:text-blue-400"
                fill="currentColor"
                viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                  clip-rule="evenodd" />
              </svg>
              <div class="text-left text-sm text-blue-800 dark:text-blue-200">
                <p class="font-medium">
                  {{ $t('web.incoming.success_info_title') }}
                </p>
                <p class="mt-1">
                  {{ $t('web.incoming.success_info_description') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex flex-col gap-3 sm:flex-row sm:justify-center">
            <button
              type="button"
              class="rounded-lg bg-blue-600 px-6 py-3 text-base font-medium text-white transition-colors duration-200 hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600"
              @click="handleCreateAnother">
              {{ $t('web.incoming.create_another') }}
            </button>

            <button
              type="button"
              class="rounded-lg border border-gray-300 px-6 py-3 text-base font-medium text-gray-700 transition-colors duration-200 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-slate-700"
              @click="handleViewRecent">
              {{ $t('web.incoming.view_recent_secrets') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
