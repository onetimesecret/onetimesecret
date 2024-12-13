<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { AuthenticationSettings, Customer } from '@/schemas/models';
import { useBrandingStore } from '@/stores/brandingStore';
import { computed, inject, ref, Ref } from 'vue';

export interface Props {
  authenticated: boolean
  authentication: AuthenticationSettings
  colonel?: boolean
  cust?: Customer
  onetimeVersion: string
  plansEnabled?: boolean
  supportHost?: string
  hasGlobalBanner: boolean
  globalBanner?: string
  primaryColor?: string
}

const props = withDefaults(defineProps<Props>(), {
  authenticated: false,
  colonel: false,
  cust: undefined,
  plansEnabled: false,
  hasGlobalBanner: false,
  globalBanner: '',
  primaryColor: 'bg-brand-500',
  supportHost: undefined
})

const color = inject('color', ref(props.primaryColor))as Ref<string>;
const brandingStore = useBrandingStore();

const primaryColorClass = computed(() => {
  if (brandingStore.isActive) {
    return '';
  }
  console.debug('Computing primaryColorClass with color:', color.value);
  return !isColorValue(color.value) ? color.value : '';
});

const primaryColorStyle = computed(() => {
  if (brandingStore.isActive) {
    const color = brandingStore.primaryColor;
    return isColorValue(color)
      ? { backgroundColor: color }
      : {};
  }

  return isColorValue(color.value)
    ? { backgroundColor: color.value }
    : {};
});

function isColorValue(value: string): boolean {
  return /^#|^rgb\(|^hsl\(/.test(value);
}

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
