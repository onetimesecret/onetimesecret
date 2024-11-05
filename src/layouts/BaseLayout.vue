
<template>
  <div>

    <!-- All along the watch tower -->
    <div
      class="w-full h-1 fixed top-0 left-0 z-50"
      :class="primaryColorClass"
      :style="primaryColorStyle"
    ></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast :show="hasGlobalBanner" :content="globalBanner" />

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

<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { AuthenticationSettings, Customer } from '@/types/onetime';
import { computed } from 'vue';

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
  plansEnabled: false,
  hasGlobalBanner: false,
  globalBanner: '',
  primaryColor: 'bg-brand-500'
})

const primaryColorClass = computed(() => {
  return props.primaryColor && !isColorValue(props.primaryColor)
    ? props.primaryColor
    : '';
});

const primaryColorStyle = computed(() => {
  return props.primaryColor && isColorValue(props.primaryColor)
    ? { backgroundColor: props.primaryColor }
    : {};
});

function isColorValue(value: string): boolean {
  return /^#|^rgb\(|^hsl\(/.test(value);
}
</script>
