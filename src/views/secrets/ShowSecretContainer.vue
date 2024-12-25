<!-- ShowSecretContainer.vue -->
<script setup lang="ts">
// import { domainStrategy } from '@/composables/useDomainBranding';
import { useValidatedWindowProp } from '@/composables/useWindowProps';
import { computed } from 'vue';
import { z } from 'zod';

import ShowSecretBranded from './branded/ShowSecret.vue';
import ShowSecretCanonical from './canonical/ShowSecret.vue';

// Define props
interface Props {
  secretKey: string;
}
const props = defineProps<Props>();

const domainStrategy = useValidatedWindowProp('domain_strategy', z.string());
const displayDomain = useValidatedWindowProp('display_domain', z.string());
const domainId = useValidatedWindowProp('domain_id', z.string());
const siteHost = useValidatedWindowProp('site_host', z.string());

const currentComponent = computed(() => {
  console.debug('[ShowSecretContainer] meta=', props.secretKey, domainStrategy)
  return domainStrategy === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>

<template>
  <Component
    :is="currentComponent"
    :secret-key="secretKey"
    :domain-id="domainId"
    :display-domain="displayDomain"
    :site-host="siteHost"
  />
</template>
