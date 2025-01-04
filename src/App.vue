<!-- src/App.vue -->
<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { WindowService } from '@/services/window.service';
import QuietLayout from '@/layouts/QuietLayout.vue';
import type { LayoutProps } from '@/types/ui/layouts';
import StatusBar from './components/StatusBar.vue';

const { locale } = useI18n();
const route = useRoute();

const windowProps = WindowService.getMultiple({
  authenticated: false,
  ot_version: '',
  authentication: null,
  cust: null,
  plans_enabled: false,
  support_host: '',
  global_banner: '',
});

const defaultProps: LayoutProps = {
  authentication: windowProps.authentication ?? null,
  cust: windowProps.cust,
  authenticated: windowProps.authenticated,
  onetimeVersion: windowProps.ot_version,
  colonel: false,
  supportHost: windowProps.support_host,
  plansEnabled: windowProps.plans_enabled,
  hasGlobalBanner: !!windowProps.global_banner,
  globalBanner: windowProps.global_banner,
};

const layoutProps = computed(() => {
  // Merge defaults with any per-route overrides
  return {
    ...defaultProps,
     ...(route.meta.layoutProps || {}),
  } as LayoutProps;
});
</script>

<!-- App-wide setup lives here -->
<template>
  <!-- Dynamic Components: The <component> element is a built-in Vue
    component that allows you to dynamically render different components.
    :is Binding: The :is attribute is bound to the layout computed
    property. This binding determines which component should be rendered.
    This approach allows for flexible layout management in a Vue
    application, where you can easily switch between different layouts
    (like DefaultLayout and QuietLayout) based on the requirements of
    each route, without having to manually manage this in each individual
    page component. -->
  <Component
  :is="QuietLayout"
  :lang="locale"
  v-bind="layoutProps">
      <!-- The keep-alive wrapper here preserves the state of route components
           when navigating between them. This prevents unnecessary re-rendering
           and maintains component state (like form inputs, scroll position)
           when users navigate back to previously visited routes. It's placed
           directly around router-view since that's where route components are
           rendered. -->
      <router-view v-slot="{ Component }" class="rounded-md">
        <keep-alive>
          <component :is="Component" />
        </keep-alive>
      </router-view>

    <!-- StatusBar positioned independently -->
    <StatusBar position="bottom" />
    </Component>
</template>
