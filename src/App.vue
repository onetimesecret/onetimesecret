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
  <component :is="layout" v-bind="layoutProps">
    <!-- Wrapper for Router View: The dynamic layout component wraps around
         the <router-view>, allowing different layouts to be applied to
         different pages or sections of your application. -->
    <router-view></router-view>
  </component>
</template>

<!-- App-wide setup lives here -->
<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router'
import { useWindowProps } from '@/composables/useWindowProps';
import DefaultLayout from '@/layouts/DefaultLayout.vue'
import QuietLayout from '@/layouts/QuietLayout.vue'

const { locale } = useI18n();
const route = useRoute()
const { cust, is_default_locale, authentication, authenticated } = useWindowProps(['cust', 'is_default_locale', 'authentication', 'authenticated']);

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

// Define the props you want to pass to the layouts
const layoutProps = computed(() => ({
  authenticated: authenticated.value,
  authentication: authentication.value,
  colonel: false, // This might also be computed based on user role
  cust: cust,
  defaultLocale: locale.value, // You might want to get this from your i18n setup
  displayMasthead: true,
  isDefaultLocale: is_default_locale.value, // This might be computed based on current locale
  // Add any other props your layouts need
}))
</script>
