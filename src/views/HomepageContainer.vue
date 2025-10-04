<!-- src/views/HomepageContainer.vue -->
<script setup lang="ts">
  import { useProductIdentity } from '@/stores/identityStore';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';

  import BrandedHomepage from './BrandedHomepage.vue';
  import Homepage from './Homepage.vue';
  import DisabledHomepage from './DisabledHomepage.vue';
  import DisabledUI from './DisabledUI.vue';

  interface Props {}
  defineProps<Props>();

  const { isCustom, displayDomain, siteHost } = useProductIdentity();
  const route = useRoute();

  // Get component state from route meta (set by beforeEnter hook)
  const componentState = computed(() => route.meta.componentState || 'normal');

  // Determine which component to show based on state
  const currentComponent = computed(() => {
    switch (componentState.value) {
      case 'disabled-ui':
        return DisabledUI;
      case 'disabled-homepage':
        return DisabledHomepage;
      case 'normal':
      default:
        return isCustom ? BrandedHomepage : Homepage;
    }
  });

  // Note: Layout props are now set in the route's beforeEnter hook
  // to ensure they're configured before the layout renders
</script>

<template>
  <div class="homepage-container">
    <Transition name="homepage-fade" mode="out-in">
      <Component
        :key="componentState + (isCustom ? '-branded' : '-standard')"
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
