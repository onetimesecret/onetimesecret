<!-- src/layouts/BaseLayout.vue -->

<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { WindowService } from '@/services/window.service';
import { useBrandingStore } from '@/stores/brandingStore';
import type { LayoutProps } from '@/types/ui/layouts';
import { isColorValue } from '@/utils/color-utils';
import { computed, defineProps, ref } from 'vue';

defineProps<LayoutProps>();
const globalBanner = WindowService.get('global_banner');
const hasGlobalBanner = computed(() => { return !!globalBanner });

/* =============================== */
/* TODO: PRIMARY COLOUR  */
// const color = inject('color', ref(props.primaryColor)) as Ref<string>;
const color = ref('#dc4a22');
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
/* =============================== */


</script>

<template>
  <div>
    <!-- All along the watch tower -->
    <div class="fixed left-0 top-0 z-50 h-1 w-full"
         :class="primaryColorClass"
         :style="primaryColorStyle"></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast :show="hasGlobalBanner"
                     :content="globalBanner" />

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
