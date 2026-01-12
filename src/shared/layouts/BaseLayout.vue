<!-- src/shared/layouts/BaseLayout.vue -->

<script setup lang="ts">
  import GlobalBroadcast from '@/shared/components/ui/GlobalBroadcast.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { useTheme } from '@/shared/composables/useTheme';
  import { storeToRefs } from 'pinia';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { isColorValue } from '@/utils/color-utils';
  import { computed, onMounted } from 'vue';

  defineProps<LayoutProps>();

  // Initialize theme early to avoid flash of wrong theme
  const { initializeTheme } = useTheme();
  onMounted(initializeTheme);

  const bootstrapStore = useBootstrapStore();
  const { global_banner } = storeToRefs(bootstrapStore);

  // Component key cannot be null or undefined
  const globalBroadcastKey = computed(() => global_banner.value ? 'globalBroadcast' : 'noBroadcast');

  const identityStore = useProductIdentity();

  // If there's a global banner set (in redis), this will be true. The actual
  // content may not show if the feature is by displayGlobalBroadcast=false.
  // For example, custom branded pages have the feature disabled altogether.
  const hasGlobalBanner = computed(() => !!global_banner.value);

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
  <div class="flex min-h-screen flex-col">
    <!-- All along the watch tower -->
    <div
      class="fixed left-0 top-0 z-50 h-1 w-full"
      :class="primaryColorClass"
      :style="primaryColorStyle"></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast
      v-if="displayGlobalBroadcast"
      :show="hasGlobalBanner"
      :content="global_banner ?? null"
      :key="globalBroadcastKey"
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
