<!-- src/views/HomepageContainer.vue -->
<script setup lang="ts">
  import { useProductIdentity } from '@/stores/identityStore';
  import { computed } from 'vue';

  import BrandedHomepage from './BrandedHomepage.vue';
  import Homepage from './Homepage.vue';

  interface Props {}
  defineProps<Props>();

  const { isCustom, displayDomain, siteHost } = useProductIdentity();

  // Simple approach: use direct component with transition
  const currentComponent = computed(() => isCustom ? BrandedHomepage : Homepage);
</script>

<template>
  <div class="homepage-container">
    <Transition name="homepage-fade" mode="out-in">
      <Component
        :key="isCustom ? 'branded' : 'standard'"
        :is="currentComponent"
        :display-domain="displayDomain"
        :site-host="siteHost" />
    </Transition>
  </div>
</template>

<style scoped>
.homepage-container {
  /* Ensure container has a minimum height to prevent layout shifts */
  min-height: 500px;
  position: relative;
}

/* Transition definitions */
.homepage-fade-enter-active,
.homepage-fade-leave-active {
  transition: opacity 0.25s ease;
}

.homepage-fade-enter-from,
.homepage-fade-leave-to {
  opacity: 0;
}
</style>
