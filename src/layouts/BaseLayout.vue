<!-- src/layouts/BaseLayout.vue -->

<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { WindowService } from '@/services/window.service';
import { useBrandStore } from '@/stores/brandStore';
import type { LayoutProps } from '@/types/ui/layouts';
import { isColorValue } from '@/utils/color-utils';
import { computed, defineProps, ref } from 'vue';

defineProps<LayoutProps>();
const globalBanner = WindowService.get('global_banner') ?? null;
const hasGlobalBanner = computed(() => { return !!globalBanner });

/* =============================== */
/* TODO: PRIMARY COLOUR  */
// const color = inject('color', ref(props.primaryColor)) as Ref<string>;
const color = ref('#dc4a22');
const brandStore = useBrandStore();

// Compute primary color styles based on brand color or prop
const primaryColorClass = computed(() => {
  const currentColor = brandStore.primaryColor || color.value;
  return !isColorValue(currentColor) ? currentColor : '';
});

const primaryColorStyle = computed(() => {
  const currentColor = brandStore.primaryColor || color.value;
  return isColorValue(currentColor) ? { backgroundColor: currentColor } : {};
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
