<!-- src/components/common/HoverTooltip.vue -->

<script setup lang="ts"></script>

<template>
  <div
    class="pointer-events-none absolute -top-10 left-1/2 -translate-x-1/2
           opacity-0 transition-opacity duration-200 z-50
           group-hover:opacity-100">
    <div class="flex flex-col items-center">
      <div
        class="min-w-[100px] rounded-md bg-gray-900 px-2 py-1
               text-center text-xs text-white shadow-lg
               dark:bg-gray-700 dark:text-gray-100">
        <slot></slot>
      </div>
      <div class="-mb-1 mt-0.5 size-2 rotate-45
                  bg-gray-900 dark:bg-gray-700"></div>
    </div>
  </div>
</template>
