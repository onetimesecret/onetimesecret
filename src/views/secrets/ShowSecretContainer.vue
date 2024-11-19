<!-- ShowSecretContainer.vue -->
<template>
  <Component
    :is="currentComponent"
    :secret-key="secretKey"
    :domain-id="domainId"
    :display-domain="displayDomain"
    :site-host="siteHost"
  />
</template>

<script setup lang="ts">
import { domainStrategy } from '@/composables/useDomainBranding';
import { computed } from 'vue';
import { useRoute } from 'vue-router';

import ShowSecretBranded from './branded/ShowSecret.vue';
import ShowSecretCanonical from './canonical/ShowSecret.vue';

// Define props
interface Props {
  secretKey: string;
}
defineProps<Props>();

const route = useRoute();

// Get values from route meta
const displayDomain = computed(() => route.meta.display_domain as string);
const domainId = computed(() => route.meta.domain_id as string);
const siteHost = computed(() => route.meta.site_host as string);

const currentComponent = computed(() => {
  return domainStrategy.value === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>
