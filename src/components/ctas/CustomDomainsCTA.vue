<script setup lang="ts">
import UpgradeIdentityModal from '@/components/modals/UpgradeIdentityModal.vue';
import { ref } from 'vue';

const isUpgradeModalOpen = ref(false)

const openUpgradeModal = () => {
  isUpgradeModalOpen.value = true
}

const closeUpgradeModal = () => {
  isUpgradeModalOpen.value = false
}

const handleUpgrade = () => {
  // Handle any additional logic here when the user has clicked the upgrade button.
};
</script>

<template>
  <!-- Upgrade CTA Section -->
  <div
    class="w-full rounded-lg border border-gray-200
      bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
    <!-- Upgrade Modal Component -->
    <UpgradeIdentityModal
      :is-open="isUpgradeModalOpen"
      to="/plans/identity"
      @close="closeUpgradeModal"
      @upgrade="handleUpgrade"
    />
    <div class="flex flex-col items-center justify-between gap-6 lg:flex-row">
      <!-- Left side content -->
      <div class="flex-1 space-y-4">
        <div class="flex items-center gap-3">
          <span
            class="inline-flex items-center justify-center rounded-lg
            bg-brand-100 p-2 dark:bg-brand-900">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="size-6 text-brand-600 dark:text-brand-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"
              />
            </svg>
          </span>
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
            {{ $t('identity-plus') }}
          </h2>
        </div>

        <p class="max-w-xl text-gray-600 dark:text-gray-300">
          {{ $t('secure-your-brand-build-customer-trust-with-links-from-your-domain') }}
        </p>

        <ul class="space-y-3">
          <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
            <svg
              class="size-5 text-green-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('web.homepage.cta_feature1') }}
          </li>
          <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
            <svg
              class="size-5 text-green-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('privacy-first-design') }}
          </li>
          <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
            <svg
              class="size-5 text-green-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('full-api-access') }}
          </li>
        </ul>
      </div>

      <!-- Right side CTA -->
      <div class="flex flex-col items-center gap-4 lg:items-end">
        <div class="mb-2 text-center lg:text-right">
          <p class="text-2xl font-bold text-gray-900 dark:text-white">
            $35
          </p>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {{ $t('per-month') }}
          </p>
        </div>
        <button
          @click="openUpgradeModal"
          class="inline-flex items-center rounded-lg border border-transparent
            bg-brand-600 px-6 py-3 text-base font-medium text-white
            transition-colors duration-200
            hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          aria-label="$t('start-today-with-identity-plus')">
          <span>{{ $t('start-today') }}</span>
          <svg
            class="-mr-1 ml-2 size-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M17 8l4 4m0 0l-4 4m4-4H3"
            />
          </svg>
        </button>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {{ $t('meets-and-exceeds-compliance-standards') }}
        </p>
      </div>
    </div>
  </div>
</template>
