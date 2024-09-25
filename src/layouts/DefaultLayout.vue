<script setup lang="ts">
import BaseLayout from './BaseLayout.vue';
import { AuthenticationSettings, Cust } from '@/types/onetime';

interface Props {
  shrimp: string
  cust?: Cust
  onetimeVersion: string
  displayMasthead: boolean
  authenticated: boolean
  authentication: AuthenticationSettings
  colonel: boolean
  defaultLocale: string
  isDefaultLocale: boolean
  supportHost?: string
  plansEnabled?: boolean
  displayLinks: boolean
}

const props = withDefaults(defineProps<Props>(), {
  authenticated: false,
  colonel: false,
  defaultLocale: 'en',
  isDefaultLocale: true
})
</script>

<template>
  <BaseLayout v-bind="props">
    <template #main>
      <main class="container mx-auto p-4 max-w-2xl">
        <slot></slot>
      </main>
    </template>
  </BaseLayout>
</template>
