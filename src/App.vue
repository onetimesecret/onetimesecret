<template>
  <div>
    <!-- Dynamic Component: The <component> element is a built-in Vue
        component that allows you to dynamically render different components.
        :is Binding: The :is attribute is bound to the layout computed
        property. This binding determines which component should be rendered.
        This approach allows for flexible layout management in a Vue
        application, where you can easily switch between different layouts
        (like DefaultLayout and QuietLayout) based on the requirements of
        each route, without having to manually manage this in each individual
        page component. -->
    <Component :is="layout"
              :lang="locale"
              v-bind="layoutProps">
      <!-- See QuietLayout.vue for named views -->
      <router-view class="rounded-md"></router-view>
    </Component>

    <!-- StatusBar positioned independently -->
    <StatusBar />
  </div>
</template>

<!-- App-wide setup lives here -->
<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router'
import { useWindowProps } from '@/composables/useWindowProps';
import QuietLayout from '@/layouts/QuietLayout.vue'
import StatusBar from './components/StatusBar.vue';

const { locale } = useI18n();
const route = useRoute()
const {
  authenticated,
  authentication,
  cust,
  ot_version,
  plans_enabled,
  support_host,
  global_banner,
} = useWindowProps([
  'authenticated',
  'authentication',
  'cust',
  'ot_version',
  'plans_enabled',
  'support_host',
  'global_banner',
]);

// Layout Switching: In the script section, the layout computed property
// determines which layout component should be used based on the current
// route's metadata:
const layout = computed(() => {
  return route.meta.layout || QuietLayout;
})

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
    hasGlobalBanner: !!global_banner.value, // not null or undefined
    globalBanner: global_banner.value,
  };

  // Merge with route.meta.layoutProps if they exist
  if (route.meta.layoutProps) {
    const mergedProps = { ...defaultProps, ...route.meta.layoutProps };
    return mergedProps;
  }

  return defaultProps;
});

</script>
