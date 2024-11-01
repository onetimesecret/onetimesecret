<!-- ShowSecretContainer.vue -->
<template>
  <component :is="currentComponent" v-bind="$props" />
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import ShowSecretCanonical from './ShowSecretCanonical.vue';
import ShowSecretBranded from './ShowSecretBranded.vue';

const route = useRoute();

const currentComponent = computed(() => {
  //const initialData = route.meta.initialData;
  const domainStrategy = route.meta.domain_strategy;

  return domainStrategy === 'canonical' ? ShowSecretCanonical : ShowSecretBranded;
});
</script>
