
<template>
  <div>

    <!-- All along the watch tower -->
    <div class="w-full h-1 bg-brand-500 fixed top-0 left-0 z-50"></div>

    <!-- Good morning Vietnam -->
    <GlobalBroadcast :show="false" content="" />

    <!-- Header content, Ramos territory -->
    <slot name="header"></slot>

    <!-- Main page content, only in Japan -->
    <slot name="main"></slot>

    <!-- Footer content, Haaland maybe? -->
    <slot name="footer"></slot>

  </div>
</template>

<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import { AuthenticationSettings, Customer } from '@/types/onetime';

export interface Props {
  authentication: AuthenticationSettings
  cust?: Customer
  onetimeVersion: string
  supportHost?: string
  colonel: boolean
  authenticated: boolean
  plansEnabled?: boolean
}

withDefaults(defineProps<Props>(), {
  colonel: false,
  authenticated: false,
  plansEnabled: false,
})

</script>
