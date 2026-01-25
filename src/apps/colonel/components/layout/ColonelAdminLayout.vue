<!-- src/apps/colonel/components/layout/ColonelAdminLayout.vue -->

<!--
  Simplified Colonel Admin Layout.
  Provides full-width content area without fixed sidebar.
  Navigation is handled via quick actions on dashboard and header menu.
-->

<script setup lang="ts">
// Layout component - no script logic needed
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      <slot></slot>
    </div>
  </div>
</template>
