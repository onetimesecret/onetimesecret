<!-- SecretPreview.vue -->
<template>
  <div class="bg-gray-800 rounded-lg p-6">
    <div class="flex items-center gap-4 mb-4">
      <!-- Logo Upload Area -->
      <div class="relative group">
        <div class="w-12 h-12 rounded-lg bg-gray-700 flex items-center justify-center overflow-hidden cursor-pointer"
             @click="$refs.logoInput.click()">
          <img v-if="brandSettings.image_encoded"
               :src="`data:${brandSettings.image_content_type};base64,${brandSettings.image_encoded}`"
               alt="Brand logo"
               class="w-full h-full object-cover">
          <svg v-else
               class="w-6 h-6 text-gray-400"
               fill="none"
               stroke="currentColor"
               viewBox="0 0 24 24">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
        </div>

        <!-- Hidden file input -->
        <input ref="logoInput"
               type="file"
               class="hidden"
               accept="image/*"
               @change="handleLogoChange">

        <!-- Hover Controls -->
        <div v-if="brandSettings.image_encoded"
             class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center rounded-lg">
          <button @click.stop="onLogoRemove"
                  class="text-xs text-red-400 hover:text-red-300">
            Remove
          </button>
        </div>
      </div>

      <div class="flex-1">
        <h3 class="text-gray-200 font-medium"
            :style="{ fontFamily: brandSettings.font_family }">
          Secure Message
        </h3>
        <p class="text-gray-400 text-sm"
           :style="{ fontFamily: brandSettings.font_family }">
          {{ brandSettings.description || 'This is a sample secret message that will be displayed to your recipients.' }}
        </p>
      </div>
    </div>

    <button class="w-full mt-4 py-2 px-4 text-white text-sm transition-colors"
            :class="{
              'rounded-lg': brandSettings.button_style === 'rounded',
              'rounded-full': brandSettings.button_style === 'pill',
              'rounded-none': brandSettings.button_style === 'square'
            }"
            :style="{
              backgroundColor: brandSettings.primary_color,
              fontFamily: brandSettings.font_family
            }">
      View Secret
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import type { BrandSettings } from '@/types/onetime';

const props = defineProps<{
  brandSettings: BrandSettings;
  secretKey: string;
  onLogoUpload: (file: File) => Promise<void>;
  onLogoRemove: () => Promise<void>;
}>();

const logoInput = ref<HTMLInputElement | null>(null);

const handleLogoChange = (event: Event) => {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (file) {
    props.onLogoUpload(file);
  }
  // Reset input so the same file can be selected again
  input.value = '';
};
</script>

<style scoped>
/* Add hover effect for the button */
button:hover {
  filter: brightness(110%);
}
</style>
