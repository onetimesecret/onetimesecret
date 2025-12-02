<!-- src/components/ctas/FancyIconLinkSpinning.vue -->

<script setup lang="ts">
/**
 * Props for FancyIconLink component
 */
defineProps<{
  text?: string;
  to: string;
  ariaLabel: string;
}>();
</script>

<template>
  <router-link
    :to="to"
    :aria-label="ariaLabel"
    class="inline-flex items-center rounded-md px-2 py-1 text-sm font-medium
           text-gray-700 transition-colors
           duration-150 ease-in-out hover:text-gray-900
           focus:outline-none focus:ring-2
           focus:ring-brandcomp-500 dark:text-gray-300 dark:hover:text-gray-100">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="icon-glow mr-1 size-5"
      viewBox="0 0 20 20"
      fill="url(#gradientAnimation)">
      <defs>
        <linearGradient
          id="gradient"
          x1="0%"
          y1="0%"
          x2="100%"
          y2="100%">
          <stop
            offset="0%"
            stop-color="#ff0000" />
          <stop
            offset="25%"
            stop-color="#ff69b4" />
          <stop
            offset="50%"
            stop-color="#ffff00" />
          <stop
            offset="75%"
            stop-color="#ff4500" />
          <stop
            offset="100%"
            stop-color="#ff0000" />
        </linearGradient>
        <linearGradient
          id="gradientAnimation"
          x1="0%"
          y1="0%"
          x2="100%"
          y2="100%">
          <animateTransform
            attributeName="gradientTransform"
            type="rotate"
            from="0 .5 .5"
            to="360 .5 .5"
            dur="5s"
            repeatCount="indefinite" />
          <stop
            offset="0%"
            stop-color="#ff0000" />
          <stop
            offset="25%"
            stop-color="#ff69b4" />
          <stop
            offset="50%"
            stop-color="#ffff00" />
          <stop
            offset="75%"
            stop-color="#ff4500" />
          <stop
            offset="100%"
            stop-color="#ff0000" />
        </linearGradient>
        <filter id="glow">
          <feGaussianBlur
            stdDeviation="2.5"
            result="coloredBlur" />
          <feMerge>
            <feMergeNode in="coloredBlur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <path
        fill-rule="evenodd"
        d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
        clip-rule="evenodd"
        filter="url(#glow)" />
    </svg>
    <span v-if="text">{{ text }}</span>
  </router-link>
</template>

<style scoped>
.icon-glow {
  filter: drop-shadow(0 0 2px rgba(255, 255, 255, 0.7));
}
</style>
