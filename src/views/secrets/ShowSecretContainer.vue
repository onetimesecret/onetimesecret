<!-- ShowSecretContainer.vue -->
<template>
  <Component
    :is="currentComponent"
    :secretKey="secretKey"
    :domainStrategy="domainStrategy"
    :displayDomain="displayDomain"
    :domainBranding="domainBranding"
    :siteHost="siteHost"

  />
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import ShowSecretCanonical from './canonical/ShowSecret.vue';
import ShowSecretBranded from './branded/ShowSecret.vue';
import { BrandSettings } from '@/types/onetime';

// Define props
interface Props {
  secretKey: string;
}
defineProps<Props>();

const route = useRoute();

// Get values from route meta
const domainStrategy = computed(() => route.meta.domain_strategy as string);
const displayDomain = computed(() => route.meta.display_domain as string);
const domainBranding = computed(() => route.meta.domain_branding as BrandSettings);
const siteHost = computed(() => route.meta.site_host as string);

const currentComponent = computed(() => {
  return domainStrategy.value === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>
