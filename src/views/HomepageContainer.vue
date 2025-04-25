<!-- src/views/HomepageContainer.vue -->
<script setup lang="ts">
  import { useProductIdentity } from '@/stores/identityStore';
  import { computed } from 'vue';

  import BrandedHomepage from './BrandedHomepage.vue';
  import Homepage from './Homepage.vue';

  interface Props {}
  defineProps<Props>();

  const { isCustom, displayDomain, siteHost } = useProductIdentity();

  const currentComponent = computed(() => {
    return isCustom ? BrandedHomepage : Homepage;
  });
</script>

<template>
  <Component
    :is="currentComponent"
    :display-domain="displayDomain"
    :site-host="siteHost" />
</template>
