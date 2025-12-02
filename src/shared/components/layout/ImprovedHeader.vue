<!-- src/shared/components/layout/ImprovedHeader.vue -->

<!--
  Changes from DefaultHeader:
  - Wider container (max-w-4xl instead of max-w-2xl)
  - Better spacing and structure for navigation growth
  - Cleaner separation between brand and navigation
-->

<script setup lang="ts">
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import ImprovedPrimaryNav from '@/shared/components/navigation/ImprovedPrimaryNav.vue';
  import { WindowService } from '@/services/window.service';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const authenticated = computed(() => WindowService.get('authenticated'));
</script>

<template>
  <header class="border-b border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
    <!-- Top Bar with Logo and User Menu -->
    <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
      <div class="py-4">
        <MastHead v-if="displayMasthead" v-bind="props" />
      </div>
    </div>

    <!-- Primary Navigation Bar (for authenticated users) - Hidden on mobile -->
    <div v-if="authenticated && displayNavigation" class="hidden bg-gray-100 dark:bg-gray-800 md:block">
      <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
        <ImprovedPrimaryNav />
      </div>
    </div>
  </header>
</template>
