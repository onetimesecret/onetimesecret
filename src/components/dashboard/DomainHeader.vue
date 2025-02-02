<script setup lang="ts">

defineProps<{
  displayDomain: string;
}>();
</script>

<template>
  <div class="border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
    <div class="mx-auto max-w-7xl p-4 sm:px-6 lg:px-8">
      <!-- Back button section -->
      <div class="flex items-center space-x-4">
        <RouterLink to="/domains"
                    class="inline-flex items-center text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
                    aria-label="$t('return-to-domains-list')">
          <svg class="mr-2 size-5"
               fill="none"
               stroke="currentColor"
               viewBox="0 0 24 24"
               aria-hidden="true">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          {{ $t('back-to-domains') }}
        </RouterLink>
      </div>
      <!-- Title section - make text smaller on mobile -->
      <div class="mt-4 flex flex-col gap-1">
        <div class="flex flex-wrap items-baseline justify-between gap-2 space-y-2 sm:space-y-0">
          <h1
              class="flex max-w-[calc(100vw-2rem)] items-center truncate text-2xl font-bold text-gray-900 dark:text-white sm:text-3xl">
            <span class="break-all">{{ displayDomain }}</span>
            <a :href="`https://${displayDomain}`"
               target="_blank"
               rel="noopener noreferrer"
               class="ml-2 text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
               title="$t('open-domain-in-new-tab')">
              <svg xmlns="http://www.w3.org/2000/svg"
                   class="h-5 w-5"
                   viewBox="0 0 24 24"
                   fill="none"
                   stroke="currentColor">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
            </a>
          </h1>
          <span class="rounded-md bg-gray-100 px-3 py-1 font-brand text-xs text-gray-800 dark:bg-gray-700 dark:text-gray-100"
                role="status">
            {{ $t('custom-domain') }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
