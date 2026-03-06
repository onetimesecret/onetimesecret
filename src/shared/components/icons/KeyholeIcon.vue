<!-- src/shared/components/icons/KeyholeIcon.vue -->

<!--
Icon from WebHostingHub Glyphs by WebHostingHub
Licensed under SIL Open Font License 1.1
Source: https://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=OFL
-->

<script setup lang="ts">
import { computed } from 'vue'

/**
 * Props for controlling keyhole icon appearance.
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
  props.ariaLabel || 'Keyhole logo'
)

const hoverTitle = computed(() =>
  props.title || 'Keyhole icon'
)
</script>

<template>
  <svg
    :width="svgSize"
    :height="svgSize"
    viewBox="0 0 512 1024"
    xmlns="http://www.w3.org/2000/svg"
    :aria-label="ariaLabel"
    :title="hoverTitle"
    role="img"
    :style="{
      opacity: svgOpacity,
      filter: `brightness(${svgBrightness})`
    }"
    class="block">
    <!-- Icon from WebHostingHub Glyphs by WebHostingHub - https://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=OFL -->
    <path
      fill="currentColor"
      d="m363 488l149 472q0 27-18.5 45.5T448 1024H64q-26 0-45-18.5T0 960l149-472q-67-31-108-93.5T0 256Q0 150 75 75T256 0t181 75t75 181q0 76-41 138.5T363 488" />
  </svg>
</template>
