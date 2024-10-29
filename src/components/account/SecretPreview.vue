<!-- SecretPreview.vue -->
<template>
  <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
    <div class="flex items-center gap-4 mb-4">
      <!-- Logo Upload Area -->
      <div class="relative group">
        <div
          class="w-16 h-16 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center overflow-hidden cursor-pointer"
          @click="$refs.logoInput.click()"
          role="button"
          aria-label="Upload logo"
        >
          <img
            v-if="brandSettings.image_encoded"
            :src="`data:${brandSettings.image_content_type};base64,${brandSettings.image_encoded}`"
            alt="Brand logo"
            class="w-full h-full object-cover"
          >
          <svg
            v-else
            class="w-6 h-6 text-gray-400 dark:text-gray-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
        </div>

        <!-- Hidden file input -->
        <input
          ref="logoInput"
          type="file"
          class="hidden"
          accept="image/*"
          @change="handleLogoChange"
        >

        <!-- Hover Controls -->
        <div
          v-if="brandSettings.image_encoded"
          class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center rounded-lg"
        >
          <button
            @click.stop="onLogoRemove"
            class="text-xs text-red-400 hover:text-red-300"
            aria-label="Remove logo"
          >
            Remove
          </button>
        </div>
      </div>

      <div class="flex-1">
        <h3
          class="text-gray-900 dark:text-gray-200 font-medium mb-2"
          :style="{ fontFamily: brandSettings.font_family }"
        >
          You have a message
        </h3>
        <p
          class="text-gray-600 dark:text-gray-400 text-sm italic"
          :style="{ fontFamily: brandSettings.font_family }"
        >
          {{ brandSettings.instructions_pre_reveal || 'Click the button below to reveal your secure message.' }}
        </p>
      </div>
    </div>

    <!-- Sample Secret Content -->
    <div class="mt-4 mb-4">
      <textarea
        readonly
        class="w-full bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-md p-3 font-mono text-sm border border-gray-200 dark:border-gray-600"
        rows="3"
        :style="{ fontFamily: 'monospace' }"
        aria-label="Sample secret content"
      >Sample secret content
This could be sensitive data
Or a multi-line message</textarea>
    </div>

    <button
      class="w-full py-2 px-4 text-white text-sm transition-colors"
      :class="{
        'rounded-lg': brandSettings.button_style === 'rounded',
        'rounded-full': brandSettings.button_style === 'pill',
        'rounded-none': brandSettings.button_style === 'square'
      }"
      :style="{
        backgroundColor: brandSettings.primary_color,
        fontFamily: brandSettings.font_family
      }"
      aria-label="View secret message"
    >
      View Secret
    </button>
  </div>
</template>

<script setup lang="ts">
// Script remains the same
import { ref } from 'vue'
import type { BrandSettings } from '@/types/onetime'

const props = defineProps<{
  brandSettings: BrandSettings
  secretKey: string
  onLogoUpload: (file: File) => Promise<void>
  onLogoRemove: () => Promise<void>
}>()

const logoInput = ref<HTMLInputElement | null>(null)

const handleLogoChange = (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (file) {
    props.onLogoUpload(file)
  }
  input.value = ''
}
</script>

<style scoped>
/* Styles remain the same */
button:hover {
  filter: brightness(110%);
}

textarea {
  resize: none;
}
</style>
