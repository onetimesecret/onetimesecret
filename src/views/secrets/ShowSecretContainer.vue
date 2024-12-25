<!-- ShowSecretContainer.vue -->
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

interface RouteMeta {
  secretKey: string;
  domainId: string;
  display_domain: string;
  siteHost: string;
}

const meta = route.meta as unknown as RouteMeta;

const currentComponent = computed(() => {
  console.debug('[ShowSecretContainer] meta=', meta.secretKey)
  return domainStrategy.value === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>

<template>
  <Component
    :is="currentComponent"
    :secret-key="meta.secretKey"
    :domain-id="meta.domainId"
    :display-domain="meta.display_domain"
    :site-host="meta.siteHost"
  />
</template>
