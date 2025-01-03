<script setup lang="ts">
  import { useDomainBranding } from '@/composables/useDomainBranding';
  import { WindowService } from '@/services/window';
  import QuietLayout from '@/layouts/QuietLayout.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';
  import type { LayoutProps } from '@/layouts/QuietLayout.vue'; // Import type definition
  import StatusBar from './components/StatusBar.vue';

  const { locale } = useI18n();
  const route = useRoute();


  const authenticated = WindowService.get('authenticated', false);
  const ot_version = WindowService.get('ot_version', '');
  const {
    authentication,
    cust,
    plans_enabled,
    support_host,
    global_banner,
  } = WindowService.getMultiple([
    'authentication',
    'cust',
    'plans_enabled',
    'support_host',
    'global_banner',
  ]);

  // const layout = computed(() => {
  //   return route.meta.layout || QuietLayout;
  // });

  // Default props without branding
  const defaultProps: LayoutProps = {
    authenticated: authenticated,
    onetimeVersion: ot_version,
    authentication: authentication,
    colonel: false,
    cust: cust,
    supportHost: support_host,
    plansEnabled: plans_enabled,
    defaultLocale: locale.value,
    isDefaultLocale: true,
    hasGlobalBanner: !!global_banner,
    globalBanner: global_banner,
    // primaryColor: domainBranding?.primary_color, // TODO: Revisit
  };

  const layoutProps = computed(() => {
    // Combine default props with branding
    const props: LayoutProps = { ...defaultProps };

    if (route.meta.layoutProps) {
      return { ...props, ...route.meta.layoutProps };
    }

    return props;
  });
</script>

<!-- App-wide setup lives here -->
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
    <Component
      :is="QuietLayout"
      :lang="locale"
      v-bind="layoutProps">
      <!-- See QuietLayout.vue for named views -->
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
    </Component>

    <!-- StatusBar positioned independently -->
    <StatusBar position="bottom" />
  </div>
</template>
