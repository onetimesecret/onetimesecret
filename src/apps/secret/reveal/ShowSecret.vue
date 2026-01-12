<!-- src/apps/secret/reveal/ShowSecret.vue -->

<script setup lang="ts">
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

import ShowSecretBranded from './branded/ShowSecret.vue';
import ShowSecretCanonical from './canonical/ShowSecret.vue';

// Define props
interface Props {
  secretIdentifier: string;
}
const props = defineProps<Props>();

const bootstrapStore = useBootstrapStore();
const {
  domain_strategy: domainStrategy,
  display_domain: displayDomain,
  domain_id: domainId,
  site_host: siteHost,
} = storeToRefs(bootstrapStore);

const currentComponent = computed(() => {
  console.debug('[ShowSecretContainer] meta=', props.secretIdentifier, domainStrategy.value)
  return domainStrategy.value === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>

<template>
  <Component
    :is="currentComponent"
    :secret-identifier="secretIdentifier"
    :domain-id="domainId"
    :display-domain="displayDomain"
    :site-host="siteHost" />
</template>
