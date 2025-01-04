<!-- src/App.vue -->
<script setup lang="ts">
import QuietLayout from '@/layouts/QuietLayout.vue';
import type { LayoutProps } from '@/types/ui/layouts';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import StatusBar from './components/StatusBar.vue';

const { locale } = useI18n();
const route = useRoute();

const defaultProps: LayoutProps = {
  displayMasthead: true,
  displayNavigation: true,
  displayLinks: true,
  displayFeedback: true,
  displayVersion: true,
  displayPoweredBy: true,
  displayToggles: true,
};

// Bring the layout and route together
const layout = computed(() => { return route.meta.layout || QuietLayout });
const layoutProps = computed(() => ({
  ...defaultProps,
  ...(route.meta.layoutProps ?? {})
}));
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
  <Component :is="layout"
             :lang="locale"
             v-bind="layoutProps">
    <!-- The keep-alive wrapper here preserves the state of route components
           when navigating between them. This prevents unnecessary re-rendering
           and maintains component state (like form inputs, scroll position)
           when users navigate back to previously visited routes. It's placed
           directly around router-view since that's where route components are
           rendered. -->
    <router-view v-slot="{ Component }"
                 class="rounded-md">
      <keep-alive>
        <component :is="Component" />
      </keep-alive>
    </router-view>

    <!-- StatusBar positioned independently -->
    <StatusBar position="bottom" />
  </Component>
</template>
