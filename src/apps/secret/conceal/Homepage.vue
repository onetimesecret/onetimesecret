<!-- src/apps/secret/conceal/Homepage.vue -->

<script setup lang="ts">
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';

  import BrandedHomepage from './BrandedHomepage.vue';
  import DisabledHomepage from './AccessDenied.vue';
  import DisabledUI from './DisabledUI.vue';
  import HomepageContent from './HomepageContent.vue';

  interface Props {}
  defineProps<Props>();

  const { isCustom, displayDomain, siteHost } = useProductIdentity();
  const route = useRoute();

  // Get component mode from route meta (set by beforeEnter hook)
  const componentMode = computed(() => route.meta.componentMode || 'normal');

  // Determine which component to show based on mode
  const currentComponent = computed(() => {
    switch (componentMode.value) {
      case 'disabled-ui':
        return DisabledUI;
      case 'disabled-homepage':
        return DisabledHomepage;
      case 'normal':
      default:
        return isCustom ? BrandedHomepage : HomepageContent;
    }
  });

  // Note: Layout props are now set in the route's beforeEnter hook
  // to ensure they're configured before the layout renders
</script>

<template>
  <div class="homepage-container">
    <Transition name="homepage-fade" mode="out-in">
      <Component
        :key="componentMode + (isCustom ? '-branded' : '-standard')"
        :is="currentComponent"
        :display-domain="displayDomain"
        :site-host="siteHost" />
    </Transition>
  </div>
</template>

<style scoped>
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
