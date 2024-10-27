<template>
  <div class="border rounded-lg p-6 shadow-md dark:bg-gray-800">
    <div class="mb-4">
      <img v-if="logoSrc"
           :src="logoSrc"
           alt="Logo"
           class="h-8 mb-2">
      <h1 class="text-2xl font-bold"
          :style="{ color: brandSettings.primary_color, fontFamily: brandSettings.font_family }">
        Secret Preview
      </h1>
    </div>
    <div class="mb-4">
      <p class="text-gray-600 dark:text-gray-400"
         :style="{ fontFamily: brandSettings.font_family }">
        {{ brandSettings.description || 'This message is for you' }}
      </p>
    </div>
    <div class="mb-4">
      <textarea readonly
                class="w-full p-2 border rounded dark:bg-gray-700 dark:text-white"
                rows="3"
                :style="{ fontFamily: brandSettings.font_family }">This is a sample secret message.</textarea>
    </div>
    <button :class="{
      'px-4 py-2 text-white': true,
      'rounded': brandSettings.button_style === 'rounded',
      'rounded-full': brandSettings.button_style === 'pill'
    }"
            :style="{ backgroundColor: brandSettings.primary_color, fontFamily: brandSettings.font_family }">
      View Secret
    </button>
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
