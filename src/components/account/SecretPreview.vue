<!-- SecretPreview.vue -->
<template>
  <div class="bg-white dark:bg-gray-800 rounded-lg p-3 sm:p-4">
    <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 mb-4">

      <!-- Logo Upload Area -->
      <div class="relative group mx-auto sm:mx-0">
        <!-- Change this to a label wrapping both the preview and input -->
        <label class="block cursor-pointer"
               for="logo-upload"
               role="button"
               aria-label="Upload logo"
               aria-describedby="logoHelp">
          <div :class="{
            'rounded-lg': brandSettings.corner_style === 'rounded',
            'rounded-full': brandSettings.corner_style === 'pill',
            'rounded-none': brandSettings.corner_style === 'square',
            'animate-wiggle': !isValidLogo
          }"
               class="w-14 h-14 sm:w-16 sm:h-16 bg-white dark:bg-gray-800 flex items-center justify-center overflow-hidden hover:ring-2 hover:ring-offset-2 hover:ring-primary-500">
            <img v-if="isValidLogo"
                 :src="logoSrc"
                 :alt="logoImage?.filename || 'Brand logo'"
                 class="w-full h-full object-cover">
            <svg v-else
                 class="w-6 h-6 text-gray-400 dark:text-gray-500"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
        </label>


        <!-- Help text -->
        <div id="logoHelp"
             class="sr-only">
          Click to upload a logo. Recommended size: 128x128 pixels. Maximum file size: 1MB. Supported formats: PNG, JPG,
          SVG
        </div>

        <!-- Update the file input -->
        <input id="logo-upload"
               type="file"
               class="hidden"
               accept="image/*"
               @change="handleLogoChange"
               aria-labelledby="logoHelp">

        <!-- Hover/Focus Controls -->
        <div v-if="isValidLogo"
             class="absolute inset-0 bg-black/70 opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity flex items-center justify-center rounded-lg"
             role="group"
             aria-label="Logo controls">
          <button @click.stop="onLogoRemove"
                  class="text-xs bg-red-600 hover:bg-red-700 focus:bg-red-700 text-white px-3 py-1 rounded-md focus:ring-2 focus:ring-offset-2 focus:ring-red-500 focus:outline-none"
                  aria-label="Remove current logo">
            <span class="flex items-center gap-1">
              <Icon icon="mdi:trash"
                    aria-hidden="true" />
              Remove
            </span>
          </button>
        </div>
      </div>

      <div class="flex-1 text-center sm:text-left">
        <!-- Fixed height container for title and instructions -->
        <div class="min-h-[4rem] sm:h-[4.5rem]">
          <h3 class="text-gray-900 dark:text-gray-200 text-base sm:text-lg font-medium mb-1 sm:mb-2 leading-normal"
              :style="{
                fontFamily: brandSettings.font_family,
                lineHeight: '1.5'
              }">
            You have a message
          </h3>
          <p class="text-gray-600 dark:text-gray-400 text-xs sm:text-sm leading-normal"
             :style="{
              fontFamily: brandSettings.font_family,
              lineHeight: '1.5'
            }">
            {{ getInstructions(isRevealed) }}
          </p>
        </div>
      </div>
    </div>

    <!-- Secret Content Area -->
    <div class="mt-3 sm:mt-4 mb-3 sm:mb-4">

      <textarea v-if="isRevealed"
                readonly
                class="w-full bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 font-mono text-xs sm:text-sm p-2 sm:p-3 border border-gray-200 dark:border-gray-600"
                rows="3"
                :class="{
                  'rounded-lg': brandSettings.corner_style === 'rounded',
                  'rounded-xl': brandSettings.corner_style === 'pill',
                  'rounded-none': brandSettings.corner_style === 'square'
                }"
                :style="{ fontFamily: 'monospace' }"
                aria-label="Sample secret content">Sample secret content
This could be sensitive data
Or a multi-line message</textarea>
      <div v-else
           class="w-full h-[86px] bg-gray-100 dark:bg-gray-700 flex items-center justify-center"
           :class="{
            'rounded-lg': brandSettings.corner_style === 'rounded',
            'rounded-xl': brandSettings.corner_style === 'pill',
            'rounded-none': brandSettings.corner_style === 'square'
          }">
        <div class="text-gray-400 dark:text-gray-500 flex items-center">
          <Icon icon="mdi:eye-off"
                class="w-5 h-5 mr-2" />
          <span class="text-sm">Content hidden</span>
        </div>
      </div>

    </div>


    <!-- Action button - Adjust padding for mobile -->
    <button class="w-full py-1.5 sm:py-2 px-3 sm:px-4 text-xs sm:text-sm text-white transition-colors"
            :class="{
              'rounded-lg': brandSettings.corner_style === 'rounded',
              'rounded-full': brandSettings.corner_style === 'pill',
              'rounded-none': brandSettings.corner_style === 'square'
            }"
            :style="{
              backgroundColor: brandSettings.primary_color,
              color: brandSettings.button_text_light ? '#ffffff' : '#000000',
              fontFamily: brandSettings.font_family
            }"
            @click="toggleReveal"
            :aria-expanded="isRevealed"
            aria-controls="secretContent"
            :aria-label="isRevealed ? 'Hide secret message' : 'View secret message'">
      {{ isRevealed ? 'Hide Secret' : 'View Secret' }}
    </button>

    <div class="flex justify-between items-baseline p-3 sm:p-6">
      <div class="text-xs sm:text-sm text-gray-600 dark:text-gray-400">
        <span class="inline-flex items-center">
          <Icon icon="mdi:alert-circle-outline"
                class="mr-1"
                aria-hidden="true" />
          This message will only be shown once.
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Styles remain the same */
button:hover {
  filter: brightness(110%);
}

textarea {
  resize: none;
}

@media (prefers-reduced-motion: no-preference) {
  .animate-wiggle {
    animation: wiggle 2s ease-in-out infinite;
  }
}

@keyframes wiggle {

  0%,
  100% {
    transform: rotate(-5deg);
  }

  50% {
    transform: rotate(5deg);
  }
}
</style>


<script setup lang="ts">
// Script remains the same
import { ref, computed } from 'vue';
import type { BrandSettings, ImageProps } from '@/types/onetime';
import { Icon } from '@iconify/vue';

const props = defineProps<{
  brandSettings: BrandSettings;
  secretKey: string;
  logoImage?: ImageProps | null; // Add new prop for logo data
  onLogoUpload: (file: File) => Promise<void>;
  onLogoRemove: () => Promise<void>;
}>();

// Computed property to validate logo data
const isValidLogo = computed(() => {
  return props.logoImage &&
    typeof props.logoImage === 'object' &&
    props.logoImage.encoded &&
    props.logoImage.content_type;
});

// Computed property to generate the logo source URL
const logoSrc = computed(() => {
  if (!isValidLogo.value) return '';
  return `data:${props.logoImage?.content_type};base64,${props.logoImage?.encoded}`;
});

const isRevealed = ref(false);

const DEFAULT_PRE_REVEAL = 'Click the button below to reveal your secure message.';
const DEFAULT_POST_REVEAL = 'Your secure message is shown below.';

const getInstructions = (revealed: boolean): string => {
  if (revealed) {
    return props.brandSettings.instructions_post_reveal?.trim() || DEFAULT_POST_REVEAL;
  }
  return props.brandSettings.instructions_pre_reveal?.trim() || DEFAULT_PRE_REVEAL;
};

const handleLogoChange = (event: Event) => {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (file) {
    props.onLogoUpload(file);
  }
  input.value = '';
};

const toggleReveal = () => {
  isRevealed.value = !isRevealed.value;
};
</script>
