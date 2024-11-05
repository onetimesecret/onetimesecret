<!-- SecretPreview.vue -->
<template>
  <BaseSecretDisplay
  defaultTitle="You have a message"
  :domainBranding="domainBranding"
                     :instructions="getInstructions(isRevealed)">
    <template #logo>
      <!-- Logo Upload Area -->
      <div class="relative group mx-auto sm:mx-0">
        <label class="block cursor-pointer"
               for="logo-upload"
               role="button"
               aria-label="Upload logo"
               aria-describedby="logoHelp">
          <div :class="{
            'rounded-lg': domainBranding.corner_style === 'rounded',
            'rounded-full': domainBranding.corner_style === 'pill',
            'rounded-none': domainBranding.corner_style === 'square',
            'animate-wiggle': !isValidLogo
          }"
               class="w-14 h-14 sm:w-16 sm:h-16 bg-gray-100 dark:bg-gray-700 flex items-center justify-center overflow-hidden hover:ring-2 hover:ring-offset-2 hover:ring-primary-500">
            <img v-if="isValidLogo"
                 :src="logoSrc"
                 :alt="logoImage?.filename || 'Brand logo'"
                 class="h-16 w-16 object-contain"
                 :class="{
                  'rounded-lg': domainBranding.corner_style === 'rounded',
                  'rounded-full': domainBranding.corner_style === 'pill',
                  'rounded-none': domainBranding.corner_style === 'square'
                }">
            <svg v-else
                 class="w-8 h-8 text-gray-400 dark:text-gray-500"
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
                  class="text-xs bg-red-600 hover:bg-red-700 focus:bg-red-700 text-white px-3 py-1 rounded-md focus:ring-2 focus:ring-offset-2 focus:ring-red-500 focus:outline-none">
            <span class="flex items-center gap-1">
              <Icon icon="mdi:trash"
                    aria-hidden="true" />
              Remove
            </span>
          </button>
        </div>
      </div>

    </template>

    <template #content>
      <textarea v-if="isRevealed"
                readonly
                class="w-full bg-transparent text-gray-700 dark:text-gray-300 font-mono text-xs sm:text-sm border-0 resize-none focus:ring-0"
                rows="3"
                aria-label="Sample secret content">Sample secret content
      This could be sensitive data
      Or a multi-line message</textarea>
      <div v-else
           class="text-gray-400 dark:text-gray-500 flex items-center">
        <Icon icon="mdi:eye-off"
              class="w-5 h-5 mr-2" />
        <span class="text-sm">Content hidden</span>
      </div>
    </template>

    <template #action-button>
      <!-- Action Button -->
      <button class="w-full py-3 text-base sm:text-lg font-medium transition-colors"
              :class="{
                'rounded-lg': domainBranding.corner_style === 'rounded',
                'rounded-full': domainBranding.corner_style === 'pill',
                'rounded-none': domainBranding.corner_style === 'square'
              }"
              :style="{
                backgroundColor: domainBranding.primary_color,
                color: domainBranding.button_text_light ? '#ffffff' : '#000000',
                fontFamily: domainBranding.font_family
              }"
              @click="toggleReveal"
              :aria-expanded="isRevealed"
              aria-controls="secretContent"
              :aria-label="isRevealed ? 'Hide secret message' : 'View secret message'">
        {{ isRevealed ? 'Hide Secret' : $t('web.COMMON.click_to_continue') }}
      </button>
    </template>
  </BaseSecretDisplay>
</template>

<style scoped>
.line-clamp-6 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}


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
import BaseSecretDisplay from '@/components/secrets/branded/BaseSecretDisplay.vue';
import { BrandSettings, ImageProps } from '@/types/onetime';
import { Icon } from '@iconify/vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const props = defineProps<{
  domainBranding: BrandSettings;
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

const getInstructions = (revealed: boolean): string => {
  if (revealed) {
    return props.domainBranding.instructions_post_reveal?.trim() ||
      t('web.shared.post_reveal_default');
  }
  return props.domainBranding.instructions_pre_reveal?.trim() ||
    t('web.shared.pre_reveal_default');
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
