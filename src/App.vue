<template>
  <QuietLayout v-bind="layoutProps">
    <!-- See QuietLayout.vue for named views -->
    <router-view></router-view>
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
  authenticated,
  authentication,
  cust,
  ot_version,
  plans_enabled,
  support_host,
} = useWindowProps([
  'authenticated',
  'authentication',
  'cust',
  'ot_version',
  'plans_enabled',
  'support_host',
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
