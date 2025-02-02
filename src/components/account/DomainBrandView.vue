<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { computed } from 'vue';

interface Props {
  heading: string;
  headingId: string;
  logoPreview?: string | null;
  defaultIcon?: string;
  loading?: boolean;
  error?: string | null;
  success?: string | null;
}

const props = withDefaults(defineProps<Props>(), {
  logoPreview: null,
  defaultIcon: 'mdi-domain',
  loading: false,
  error: null,
  success: null,
});

// Compute the background icon
const backgroundIcon = computed(() => props.defaultIcon);
</script>

<template>
  <div
    class="relative flex min-h-screen items-start justify-center overflow-hidden
              bg-gray-50 px-4
              pt-12
              dark:bg-gray-900
              sm:px-6 sm:pt-16
              lg:px-8">
    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <OIcon
        collection="heroicons"
            :name="backgroundIcon"
        class="absolute left-1/2 top-0 h-auto w-full
                   -translate-x-1/2 translate-y-0 scale-150 object-cover
                   object-center blur-sm"
        aria-hidden="true"
      />
    </div>

    <!-- Page Content -->
    <div class="relative z-10 w-full min-w-[320px] max-w-2xl space-y-8">
      <!-- Logo Preview -->
      <div class="flex flex-col items-center">
        <div class="mb-8 flex size-24 items-center justify-center">
          <img
            v-if="logoPreview"
            :src="logoPreview"
            :alt="$t('heading-logo', [heading])"
            class="max-h-full max-w-full rounded-md object-contain"
          />
          <OIcon
            v-else
            collection="heroicons"
            :name="defaultIcon"
            class="size-full text-brand-600 dark:text-brand-400"
            aria-hidden="true"
          />
          <div
            v-if="loading"
            class="absolute inset-0 flex items-center justify-center rounded-md bg-gray-200 bg-opacity-75 dark:bg-gray-800 dark:bg-opacity-75">
            <svg
              class="size-8 animate-spin text-brand-600"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24">
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
          </div>
        </div>
      </div>

      <!-- Title Text -->
      <div class="text-center">
        <h1
          :id="headingId"
          class="mb-4 text-3xl font-bold text-gray-900 dark:text-gray-100">
          {{ heading }}
        </h1>
        <p class="text-lg text-gray-600 dark:text-gray-400">
          {{ $t('customize-your-domain-branding') }}
        </p>
      </div>

      <!-- Alert Messages -->
      <div
        v-if="error || success"
        class="mx-auto max-w-md">
        <div
          v-if="error"
          class="mb-4 border-l-4 border-red-500 bg-red-100 p-4 text-red-700"
          role="alert">
          <p class="font-bold">
            {{ $t('web.COMMON.error') }}
          </p>
          <p>{{ error }}</p>
        </div>
        <div
          v-if="success"
          class="mb-4 border-l-4 border-green-500 bg-green-100 p-4 text-green-700"
          role="alert">
          <p class="font-bold">
            {{ $t('web.STATUS.success') }}
          </p>
          <p>{{ success }}</p>
        </div>
      </div>

      <!-- Form Card -->
      <div class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800">
        <div class="p-6 sm:p-8">
          <slot name="form"></slot>
        </div>
      </div>

      <!-- Footer -->
      <div class="mt-8 text-center">
        <hr class="mx-auto my-4 w-1/4 border-gray-300 dark:border-gray-700" />
        <slot name="footer"></slot>
      </div>
    </div>
  </div>
</template>
