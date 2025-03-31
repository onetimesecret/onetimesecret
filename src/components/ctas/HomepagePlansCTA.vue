<!-- src/components/ctas/HomepagePlansCTA.vue -->

<script setup lang="ts">
</script>

<template>
  <div class="mb-6 w-full border-y border-gray-200 bg-gray-100 dark:border-gray-700 dark:bg-gray-800">
    <div class="container mx-auto px-4 py-2">
      <div class="flex flex-col items-center justify-between md:flex-row">
        <div class="mb-0 flex items-center space-x-3 md:mb-0">
          <svg
            class="hidden size-12 text-brand-500 sm:block sm:size-8 md:size-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
            />
          </svg>
          <span
            class="hidden font-brand text-lg font-semibold uppercase text-gray-700 dark:text-gray-300 sm:block md:text-sm">
            {{ $t('web.homepage.cta_title') }}
          </span>
        </div>
        <div class="flex w-full font-brand sm:w-auto">
          <router-link
            to="/pricing"
            class="inline-flex w-full items-center justify-center rounded-md border border-brand-500 bg-white
              px-6 py-4 text-xl font-semibold text-brand-500 transition duration-150
              hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
              dark:bg-brand-500 dark:text-white dark:hover:bg-brand-600 sm:w-auto sm:py-2 sm:text-base
              md:px-4 md:py-1 md:text-xs">
            <span class="sm:hidden">{{ $t('now-with-custom-domains') }}</span>
            <span class="hidden sm:inline">{{ $t('web.homepage.explore_premium_plans') }}</span>
            <svg
              class="ml-2 size-5 md:size-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              width="24"
              height="24"
              xmlns="http://www.w3.org/2000/svg">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5l7 7-7 7"
              />
            </svg>
          </router-link>
        </div>
      </div>
    </div>
  </div>
</template>
