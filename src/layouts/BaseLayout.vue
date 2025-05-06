<!-- src/layouts/BaseLayout.vue -->

<script setup lang="ts">
  import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
  import { WindowService } from '@/services/window.service';
  import { useProductIdentity } from '@/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { isColorValue } from '@/utils/color-utils';
  import { computed, defineProps } from 'vue';

  defineProps<LayoutProps>();

  const globalBanner = WindowService.get('global_banner') ?? null;
  const identityStore = useProductIdentity();

  // If there's a global banner set (in redis), this will be true. The actual
  // content may not show if the feature is by displayGlobalBroadcast=false.
  // For example, custom branded pages have the feature disabled altogether.
  const hasGlobalBanner = computed(() => {
    return !!globalBanner;
  });

  // Generate a unique ID for this banner based on content to ensure new banners are shown
  const bannerContentId = computed(() => {
    // Use the first 10 chars of content as part of ID so new content always shows
    const contentPrefix = globalBanner ?
      globalBanner.substring(0, 10).replace(/[^a-z0-9]/gi, '') : '';
    return `global-banner-${contentPrefix}`;
  });

  // Compute primary color styles based on brand color or prop
  const primaryColorClass = computed(() => {
    const currentColor = identityStore.primaryColor;
    return !isColorValue(currentColor) ? currentColor : '';
  });

  const primaryColorStyle = computed(() => {
    const currentColor = identityStore.primaryColor;
    return isColorValue(currentColor) ? { backgroundColor: currentColor } : {};
  });
</script>

<template>
  <div>
    <!-- All along the watch tower -->
    <div
      class="fixed left-0 top-0 z-50 h-1 w-full"
      :class="primaryColorClass"
      :style="primaryColorStyle"></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast
      v-if="displayGlobalBroadcast"
      :show="hasGlobalBanner"
      :content="globalBanner"
      :banner-id="bannerContentId"
      :expiration-days="7" />

    <!-- Rest of the owl -->
    <slot name="header"></slot>
    <slot name="main"></slot>
    <slot name="footer"></slot>
    <slot name="status">
      <div id="status-messages"></div>
    </slot>
  </div>
</template>
