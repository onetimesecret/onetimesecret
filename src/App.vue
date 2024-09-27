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
  <component :is="layout"
             v-bind="layoutProps">
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

const { locale } = useI18n();
const route = useRoute()
const {
  shrimp,
  ot_version,
  cust,
  authentication,
  authenticated,
  plans_enabled,
  support_host,
} = useWindowProps([
  'shrimp',
  'ot_version',
  'cust',
  'is_default_locale',
  'authentication',
  'authenticated',
  'display_links',
  'plans_enabled',
  'support_host',
  'display_masthead',
]);

// Layout Switching: In the script section, the layout computed property
// determines which layout component should be used based on the current
// route's metadata:
const layout = computed(() => {
  // Check if the route has a specific layout defined
  if (route.meta.layout) {
    return route.meta.layout;
  }

  // Default to DefaultLayout if no specific layout is defined
  return DefaultLayout;
});

// Define the props you want to pass to the layouts
const layoutProps = computed(() => {
  // Default props
  const defaultProps = {
    authenticated: authenticated.value,
    authentication: authentication.value,
    colonel: false,
    cust: cust.value,
    shrimp: shrimp.value,
    onetimeVersion: ot_version.value,
    supportHost: support_host.value,
    plansEnabled: plans_enabled.value,
    defaultLocale: locale.value,
    displayMasthead: true,
    displayLinks: true,
    displayVersion: true,
    displayFeedback: true,
    isDefaultLocale: true,
  };

  // Merge with route.meta.layoutProps if they exist
  if (route.meta.layoutProps) {
    return { ...defaultProps, ...route.meta.layoutProps };
  }

  return defaultProps;
});

</script>
