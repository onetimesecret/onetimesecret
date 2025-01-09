<!-- src/views/HomepageContainer.vue -->
<script setup lang="ts">
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';

  import BrandedHomepage from './BrandedHomepage.vue';
  import Homepage from './Homepage.vue';

  interface Props {}
  defineProps<Props>();

  const domainStrategy = WindowService.get('domain_strategy');
  const displayDomain = WindowService.get('display_domain');
  const siteHost = WindowService.get('site_host');

  const currentComponent = computed(() => {
    console.debug('[HomepageContainer] meta=', domainStrategy);
    return domainStrategy === 'canonical' ? Homepage : BrandedHomepage;
  });
</script>

<template>
  <Component :is="currentComponent"
             :display-domain="displayDomain"
             :site-host="siteHost" />
</template>
