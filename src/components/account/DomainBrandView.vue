<template>
  <div class="relative flex min-h-screen items-start justify-center overflow-hidden
              px-4 pt-12
              bg-gray-50
              dark:bg-gray-900
              sm:px-6 sm:pt-16
              lg:px-8">

    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <Icon :icon="backgroundIcon"
            class="absolute top-0 left-1/2 h-auto w-full
                   transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center
                   blur-sm"
            aria-hidden="true" />
    </div>

    <!-- Page Content -->
    <div class="relative z-10 w-full max-w-2xl space-y-8 min-w-[320px]">

      <!-- Logo Preview -->
      <div class="flex flex-col items-center">
        <div class="w-24 h-24 mb-8 flex items-center justify-center">
          <img v-if="logoPreview" :src="logoPreview" :alt="`${heading} Logo`"
               class="max-w-full max-h-full object-contain rounded-md" />
          <Icon v-else :icon="defaultIcon"
                class="h-full w-full text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
          <div v-if="loading" class="absolute inset-0 flex items-center justify-center bg-gray-200 bg-opacity-75 dark:bg-gray-800 dark:bg-opacity-75 rounded-md">
            <svg class="animate-spin h-8 w-8 text-brand-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </div>
        </div>
      </div>

      <!-- Title Text -->
      <div class="text-center">
        <h1 :id="headingId"
            class="text-3xl font-bold text-gray-900 dark:text-gray-100 mb-4">
          {{ heading }}
        </h1>
        <p class="text-lg text-gray-600 dark:text-gray-400">
          Customize your domain branding
        </p>
      </div>

      <!-- Alert Messages -->
      <div v-if="error || success" class="mx-auto max-w-md">
        <div v-if="error" class="bg-red-100 border-l-4 border-red-500 text-red-700 p-4 mb-4" role="alert">
          <p class="font-bold">Error</p>
          <p>{{ error }}</p>
        </div>
        <div v-if="success" class="bg-green-100 border-l-4 border-green-500 text-green-700 p-4 mb-4" role="alert">
          <p class="font-bold">Success</p>
          <p>{{ success }}</p>
        </div>
      </div>

      <!-- Form Card -->
      <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg overflow-hidden">
        <div class="p-6 sm:p-8">
          <slot name="form"></slot>
        </div>
      </div>

      <!-- Footer -->
      <div class="mt-8 text-center">
        <hr class="my-4 border-gray-300 dark:border-gray-700 mx-auto w-1/4">
        <slot name="footer"></slot>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';

// Define props for the component
const props = withDefaults(defineProps<{
  heading: string;
  headingId: string;
  logoPreview?: string | null;
  defaultIcon?: string;
  loading?: boolean;
  error?: string | null;
  success?: string | null;
}>(), {
  logoPreview: null,
  defaultIcon: 'mdi:domain',
  loading: false,
  error: null,
  success: null,
});

// Compute the background icon
const backgroundIcon = computed(() => props.defaultIcon);
</script>
