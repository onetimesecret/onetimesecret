<!-- src/components/dashboard/SecretPreview.vue -->

<script setup lang="ts">
import BaseSecretDisplay from '@/components/secrets/branded/BaseSecretDisplay.vue';
import { BrandSettings, ImageProps } from '@/schemas/models';
import {
  CornerStyle,
  FontFamily,
  cornerStyleClasses,
  fontFamilyClasses
} from '@/schemas/models/domain/brand';
import OIcon from '@/components/icons/OIcon.vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const props = defineProps<{
  domainBranding: BrandSettings;
  logoImage?: ImageProps | null;
  onLogoUpload: (file: File) => Promise<void>;
  onLogoRemove: () => Promise<void>;
  secretKey: string;
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
const textareaPlaceholder = t('sample-secret-content-this-could-be-sensitive-data');

// Computed property for instructions text
const instructions = computed(() => {
  if (isRevealed.value) {
    return props.domainBranding.instructions_post_reveal?.trim() ||
      t('web.shared.post_reveal_default');
  }
  return props.domainBranding.instructions_pre_reveal?.trim() ||
    t('web.shared.pre_reveal_default');
});

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

const cornerClass = computed(() => {
  const style = props.domainBranding?.corner_style as CornerStyle | undefined;
  return cornerStyleClasses[style ?? CornerStyle.ROUNDED];
});

const fontFamilyClass = computed(() => {
  const font = props.domainBranding?.font_family as FontFamily | undefined;
  return fontFamilyClasses[font ?? FontFamily.SANS];
});

</script>

<template>
  <!-- Updated -->
  <BaseSecretDisplay
    :default-title="$t('you-have-a-message')"
    :domain-branding="domainBranding"
    :instructions="instructions"
    :corner-class="cornerClass"
    :font-class="fontFamilyClass">

    <!-- Logo Upload Area -->
    <template #logo>
      <div class="group relative mx-auto sm:mx-0">
        <label
          class="block cursor-pointer"
          for="logo-upload"
          role="button">
          <div
            :class="[cornerClass, {
              'animate-wiggle': !isValidLogo
            }]"
            class="hover:ring-primary-500 flex size-14 items-center justify-center overflow-hidden bg-gray-100 hover:ring-2 hover:ring-offset-2 dark:bg-gray-700 sm:size-16">
            <img
              v-if="isValidLogo"
              :src="logoSrc"
              :alt="logoImage?.filename || $t('brand-logo')"
              class="size-16 object-contain"
              :class="{
                [cornerClass]: true,
              }"
            />
            <svg
              v-else
              class="size-8 text-gray-400 dark:text-gray-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
          </div>
        </label>

        <!-- Help text -->
        <div
          id="logoHelp"
          class="sr-only">
          {{ $t('click-to-upload-a-logo-with-recommendation') }}
        </div>

        <input
          id="logo-upload"
          type="file"
          class="hidden"
          accept="image/*"
          @change="handleLogoChange"
          aria-labelledby="logoHelp"
        />

        <!-- Hover/Focus Controls -->
        <div
          v-if="isValidLogo"
          class="absolute inset-0 flex items-center justify-center rounded-lg bg-black/70 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100"
          role="group"
          aria-label="$t('logo-controls')">
          <button
            @click.stop="onLogoRemove"
            class="rounded-md bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700 focus:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2">
            <span class="flex items-center gap-1">
              <OIcon
                collection="mdi"
                name="trash-can"
                class="size-4"
              />
              {{ $t('remove') }}
            </span>
          </button>
        </div>
      </div>
    </template>

    <template #content>
    <textarea
            v-if="isRevealed"
            readonly
            :class="[cornerClass]"
            class="w-full resize-none border-0 bg-transparent
            font-mono text-xs text-gray-700
            focus:ring-0 dark:text-gray-300 sm:text-base"
            rows="3"
            :aria-label="$t('sample-secret-content')"
            v-model="textareaPlaceholder"></textarea>

      <div
        v-else
        class="flex items-center text-gray-400 dark:text-gray-500"
        :class="[cornerClass, fontFamilyClass]">
        <OIcon
          collection="mdi"
          name="eye-off"
          class="mr-2 size-5"
        />
        <span class="text-sm">{{ $t('content-hidden') }}</span>
      </div>
    </template>

    <template #action-button>
      <!-- Action Button -->
      <button
        class="w-full py-3 text-base font-medium transition-colors sm:text-lg"
        :class="[cornerClass, fontFamilyClass]"
        :style="{
          backgroundColor: domainBranding.primary_color ??' #dc4a22',
          color: (domainBranding.button_text_light ?? true) ? '#ffffff' : '#000000',
        }"
        @click="toggleReveal"
        :aria-expanded="isRevealed"
        aria-controls="secretContent"
        :aria-label="$t('isrevealed-hide-secret-message-view-secret-message')">
        {{ isRevealed ? $t('hide-secret') : $t('web.COMMON.click_to_continue') }}
      </button>
    </template>
  </BaseSecretDisplay>
</template>

<style scoped>
.line-clamp-6 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
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
