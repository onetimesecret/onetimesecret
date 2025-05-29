<!-- src/components/logos/MonotoneJapaneseSecretButton.vue -->

<!--
emojione-monotone-japanese-secret-button.svg

Emoji artwork provided by EmojiTwo, originally released as EmojiOne 2.2
by Ranks.com with contributions from the EmojiTwo community.

Licensed under Creative Commons Attribution 4.0 International (CC-BY-4.0)
License: https://creativecommons.org/licenses/by/4.0/
Source: https://github.com/EmojiTwo/emojitwo
-->

<script setup lang="ts">
import { computed } from 'vue'

/**
 * Props for controlling logo appearance.
 * - opacity: 0 (transparent) to 1 (opaque)
 * - brightness: 0 (black) to 2 (double bright), default 1 (normal)
 * - size: pixel size for width/height (default 64)
 * - ariaLabel: accessibility label
 * - title: hover text for the icon
 */
const props = defineProps<{
  opacity?: number
  brightness?: number
  size?: number
  ariaLabel?: string
  title?: string
}>()

const svgOpacity = computed(() =>
  typeof props.opacity === 'number'
    ? Math.max(0, Math.min(1, props.opacity))
    : 1
)

const svgBrightness = computed(() =>
  typeof props.brightness === 'number'
    ? Math.max(0, props.brightness)
    : 1
)

const svgSize = computed(() =>
  typeof props.size === 'number' && props.size > 0
    ? props.size
    : 64
)

const ariaLabel = computed(() =>
  props.ariaLabel || 'Japanese secret button logo'
)

const hoverTitle = computed(() =>
  props.title || 'Japanese kanji "秘" (himitsu) meaning "secret" or "confidential"'
)
</script>

<template>
  <svg
    :width="svgSize"
    :height="svgSize"
    viewBox="0 0 64 64"
    xmlns="http://www.w3.org/2000/svg"
    :aria-label="ariaLabel"
    :title="hoverTitle"
    role="img"
    :style="{
      opacity: svgOpacity,
      filter: `brightness(${svgBrightness})`
    }"
    class="block"
  >
    <!-- Icon from Emoji One (Monotone) by Emoji One - https://creativecommons.org/licenses/by/4.0/ -->
    <path
      fill="currentColor"
      d="M32 2C15.432 2 2 15.432 2 32s13.432 30 30 30s30-13.432 30-30S48.568 2 32 2m2.723 12c2.696 1.475 5.974 3.823 7.561 5.682l-3.172 3.495c-1.482-1.802-4.652-4.369-7.402-6.009zM24.467 50h-4.389V36.508c-1.162 3.004-2.483 5.68-3.963 7.592c-.371-1.42-1.375-3.551-2.115-4.861c1.956-2.35 3.858-6.336 5.128-10.106h-4.547v-4.589h5.497v-4.097a73 73 0 0 1-4.439.655c-.212-1.093-.793-2.732-1.375-3.823c4.071-.602 8.723-1.64 11.419-3.005l3.226 3.715c-1.323.601-2.854 1.092-4.441 1.529v5.025h3.699v4.589h-3.699v.327c.898.875 3.014 3.168 3.912 4.262c.422-2.021.688-4.262.845-6.337l3.543.874c-.317 4.426-.952 9.451-2.749 12.51l-3.383-1.803c.633-1.201 1.162-2.678 1.531-4.314l-2.324 2.895c-.318-.656-.794-1.639-1.375-2.623V50zm14.273-4.697h3.172c1.004 0 1.216-.766 1.375-5.682c.95.766 2.695 1.529 3.963 1.803c-.422 6.445-1.585 8.193-4.861 8.193h-4.283c-3.331 0-4.599-.928-4.916-3.934a47 47 0 0 1-4.123 3.225c-.688-.93-2.539-2.732-3.543-3.553c2.855-1.746 5.393-3.822 7.561-6.281v-16.77h4.439v10.599c2.802-4.809 4.76-10.49 6.081-16.937l4.651.874c-.847 3.771-1.851 7.267-3.066 10.489l1.639-.437c1.639 3.551 2.908 8.248 3.172 11.363l-4.388 1.311c-.105-2.404-.846-5.736-1.85-8.797c-1.745 3.881-3.807 7.322-6.239 10.326v2.459c-.001 1.53.159 1.749 1.216 1.749"
    />
  </svg>
</template>
