<!-- src/layouts/BaseLayout.vue -->

<script setup lang="ts">
import { computed, inject, ref, Ref } from 'vue';
import { defineProps, withDefaults } from 'vue';
import type { LayoutProps } from '@/types/ui/layouts';
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { useBrandingStore } from '@/stores/brandingStore';
import { isColorValue } from '@/utils/color-utils';
const props = withDefaults(defineProps<LayoutProps>(), {
  authenticated: false,
  colonel: false,
  cust: undefined,
  globalBanner: '',
  hasGlobalBanner: false,
  plansEnabled: false,
  primaryColor: 'bg-brand-500',
  supportHost: undefined,
});

const color = inject('color', ref(props.primaryColor)) as Ref<string>;
const brandingStore = useBrandingStore();

const primaryColorClass = computed(() => {
  if (brandingStore.isActive) return '';
  return !isColorValue(color.value) ? color.value : '';
});

const primaryColorStyle = computed(() => {
  if (brandingStore.isActive) {
    const brandColor = brandingStore.primaryColor;
    return isColorValue(brandColor) ? { backgroundColor: brandColor } : {};
  }
  return isColorValue(color.value)
    ? { backgroundColor: color.value }
    : {};
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
      :show="hasGlobalBanner"
      :content="globalBanner"
    />

    <!-- Header content, Ramos territory -->
    <slot name="header"></slot>

    <!-- Main page content, only in Japan -->
    <slot name="main"></slot>

    <!-- Footer content, Haaland maybe? -->
    <slot name="footer"></slot>

    <slot name="status">
      <div id="status-messages"></div>
    </slot>
  </div>
</template>
