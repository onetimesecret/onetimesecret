<template>
  <!-- Dynamic Component: The <component> element is a built-in Vue
       component that allows you to dynamically render different components.
       :is Binding: The :is attribute is bound to the layout computed
       property. This binding determines which component should be rendered.
       This approach allows for flexible layout management in a Vue
       application, where you can easily switch between different layouts
       (like DefaultLayout and QuietLayout) based on the requirements of
       each route, without having to manually manage this in each individual
       page component. -->
  <component :is="layout">
    <!-- Wrapper for Router View: The dynamic layout component wraps around
         the <router-view>, allowing different layouts to be applied to
         different pages or sections of your application. -->
    <router-view></router-view>
  </component>
</template>

<!-- App-wide setup lives here -->
<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import DefaultLayout from '@/layouts/DefaultLayout.vue'
import QuietLayout from '@/layouts/QuietLayout.vue'

const route = useRoute()

// Layout Switching: In the script section, the layout computed property
// determines which layout component should be used based on the current
// route's metadata:
const layout = computed(() => {
  // Layout switching logic based on route meta
  if (route.meta.requiresAuth) {
    // Use DefaultLayout for routes that require authentication
    return DefaultLayout

  } else if (route.meta.quiet) {
    // Use QuietLayout for routes marked as 'quiet'
    return QuietLayout
  }

  // Default to DefaultLayout if no specific conditions are met
  return DefaultLayout
})
</script>
