<!-- SecretPreview.vue -->
<template>
  <div class="border rounded-lg overflow-hidden dark:bg-gray-800">
    <!-- Header -->
    <div class="p-6 border-b border-gray-200 dark:border-gray-700">
      <div class="flex items-center space-x-4">
        <img v-if="logoSrc"
             :src="logoSrc"
             alt="Logo"
             class="h-8">
        <h1 class="text-xl font-semibold"
            :style="{ color: brandSettings.primary_color, fontFamily: brandSettings.font_family }">
          Secure Message
        </h1>
      </div>
    </div>

    <!-- Content -->
    <div class="p-6 bg-white dark:bg-gray-800">
      <div class="mb-6">
        <p class="text-gray-600 dark:text-gray-400 mb-2"
           :style="{ fontFamily: brandSettings.font_family }">
          {{ brandSettings.description || 'This message is for you' }}
        </p>
        <div class="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
          <p class="font-mono text-sm text-gray-600 dark:text-gray-300">
            This is a sample secret message that will be displayed to your recipients.
          </p>
        </div>
      </div>

      <!-- Action Button -->
      <div class="flex justify-center">
        <button
          :class="{
            'px-6 py-2.5 text-white font-medium text-sm transition-colors': true,
            'rounded': brandSettings.button_style === 'rounded',
            'rounded-full': brandSettings.button_style === 'pill'
          }"
          :style="{ backgroundColor: brandSettings.primary_color, fontFamily: brandSettings.font_family }">
          View Secret
        </button>
      </div>
    </div>
  </div>
</template>


<script setup lang="ts">
import { BrandSettings } from '@/types/onetime';
import { computed } from 'vue';

const props = defineProps<{
  brandSettings: BrandSettings;
}>();

const logoSrc = computed(() => {
  if (props.brandSettings.image_encoded && props.brandSettings.image_content_type) {
    return `data:${props.brandSettings.image_content_type};base64,${props.brandSettings.image_encoded}`;
  } else if (props.brandSettings.logo) {
    // Assuming logo is a URL or path to the image
    return props.brandSettings.logo;
  }
  return null;
});
</script>
