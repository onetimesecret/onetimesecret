<!-- src/views/secrets/UnknownSecretBranded.vue -->
<template>
  <div class="bg-white dark:bg-gray-800 shadow-xl w-full rounded-lg p-8"
       :class="{ 'rounded-none': brandSettings?.corner_style === 'sharp' }"
       :style="brandSettings ? {
         fontFamily: brandSettings.font_family || 'inherit'
       } : {}">
    <!-- Icon Section -->
    <div class="flex items-center space-x-4 mb-8">
      <div class="h-12 w-12 rounded-full bg-brand-100 dark:bg-brand-900 flex items-center justify-center"
           :style="brandSettings?.primary_color ? {
             backgroundColor: `${brandSettings.primary_color}15`,
           } : {}">
        <svg xmlns="http://www.w3.org/2000/svg"
             class="h-6 w-6"
             :class="brandSettings?.button_text_light ? 'text-white' : 'text-brand-600 dark:text-brand-400'"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>
      </div>
      <div>
        <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
          Not Found
        </h2>
      </div>
    </div>

    <!-- Content Section -->
    <div class="space-y-6">
      <p class="text-gray-600 dark:text-gray-300">
        {{ brandSettings?.instructions_post_reveal ||
           'Sensitive information shared through this service can only be accessed once. Once viewed, the content is permanently deleted to ensure confidentiality.' }}
      </p>

      <router-link
        to="/"
        class="inline-block border-2 rounded-lg transition duration-300 ease-in-out py-2 px-4
               bg-white dark:bg-gray-800 hover:bg-brand-100 dark:hover:bg-gray-700
               focus:outline-none focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-gray-900
               focus:ring-brand-500 dark:focus:ring-brand-400"
        :style="brandSettings?.primary_color ? {
          color: brandSettings.primary_color,
          borderColor: brandSettings.primary_color
        } : {
          color: 'var(--color-brand-500)',
          borderColor: 'var(--color-brand-500)'
        }">
        Return to Home
      </router-link>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { BrandSettings } from '@/types/onetime';

interface Props {
  brandSettings?: BrandSettings;
}

defineProps<Props>();
</script>
