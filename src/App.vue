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
  <QuietLayout v-bind="layoutProps">
    <!-- Wrapper for Router View: The dynamic layout component wraps around
         the <router-view>, allowing different layouts to be applied to
         different pages or sections of your application. -->
    <router-view name="header" v-bind="layoutProps"></router-view>
    <router-view></router-view>
    <router-view name="footer" v-bind="layoutProps"></router-view>
  </QuietLayout>
</template>

<!-- App-wide setup lives here -->
<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router'
import { useWindowProps } from '@/composables/useWindowProps';
import QuietLayout from '@/layouts/QuietLayout.vue'

const { locale } = useI18n();
const route = useRoute()
const {
  ot_version,
  cust,
  authentication,
  authenticated,
  plans_enabled,
  support_host,
} = useWindowProps([
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

// Define the props you want to pass to the layouts
// and named view components (e.g. DefaultHeader).
const layoutProps = computed(() => {

  // Default props
  const defaultProps = {
    authenticated: authenticated.value,
    authentication: authentication.value,
    colonel: false,
    cust: cust.value,
    onetimeVersion: ot_version.value,
    supportHost: support_host.value,
    plansEnabled: plans_enabled.value,
    defaultLocale: locale.value,
    isDefaultLocale: true,
  };

  // Merge with route.meta.layoutProps if they exist
  if (route.meta.layoutProps) {
    const mergedProps = { ...defaultProps, ...route.meta.layoutProps };
    return mergedProps;
  }

  return defaultProps;
});

</script>
