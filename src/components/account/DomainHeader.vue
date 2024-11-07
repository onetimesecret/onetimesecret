<template>
  <div class="border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
      <!-- Back button section -->
      <div class="flex items-center space-x-4">
        <RouterLink
          to="/account/domains"
          class="inline-flex items-center text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 transition-colors"
          aria-label="Return to domains list">
          <svg
            class="w-5 h-5 mr-2"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          Back to Domains
        </RouterLink>
      </div>
      <!-- Title section - make text smaller on mobile -->
      <div class="mt-4 flex flex-col gap-1">
        <div class="flex items-baseline justify-between flex-wrap gap-2 space-y-2 sm:space-y-0">
          <h1 class="text-2xl sm:text-3xl font-bold text-gray-900 dark:text-white flex items-center truncate max-w-[calc(100vw-2rem)]">
            <span class="break-all">{{ domainId }}</span>

            <DomainVerificationInfo v-if="domain" mode="icon" :domain="domain" class="ml-2" /> <!-- Added ml-2 for spacing -->
          </h1>
          <span
            class="px-3 py-1 text-xs rounded-md font-brand bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-100"
            role="status">
            Custom Domain
          </span>
        </div>

      </div>

    </div>
  </div>
</template>

<script setup lang="ts">
import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
import { CustomDomain } from '@/types/onetime.d';
defineProps<{
  domainId: string;
  domain: CustomDomain | null;
}>();
</script>
