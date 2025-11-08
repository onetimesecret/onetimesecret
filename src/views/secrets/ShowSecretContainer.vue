<!-- ShowSecretContainer.vue -->

<script setup lang="ts">
// import { domainStrategy } from '@/composables/useBranding';
import { WindowService } from '@/services/window.service';
import { computed } from 'vue';

import ShowSecretBranded from './branded/ShowSecret.vue';
import ShowSecretCanonical from './canonical/ShowSecret.vue';

// Define props
interface Props {
  secretIdentifier: string;
}
const props = defineProps<Props>();

const domainStrategy = WindowService.get('domain_strategy');
const displayDomain = WindowService.get('display_domain');
const domainId = WindowService.get('domain_id');
const siteHost = WindowService.get('site_host');

const currentComponent = computed(() => {
  console.debug('[ShowSecretContainer] meta=', props.secretIdentifier, domainStrategy)
  return domainStrategy === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>

<template>
  <Component
    :is="currentComponent"
    :secret-identifier="secretIdentifier"
    :domain-id="domainId"
    :display-domain="displayDomain"
    :site-host="siteHost"
  />
</template>
