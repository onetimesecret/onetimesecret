<script setup lang="ts">
  import StatusBar from '@/components/StatusBar.vue';
  import type { LayoutProps } from '@/layouts/QuietLayout.vue';
  import QuietLayout from '@/layouts/QuietLayout.vue';
  import { WindowService } from '@/services/window';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';

  const { locale } = useI18n();
  const route = useRoute();

  const windowProps = WindowService.getMultiple({
    authenticated: false,
    ot_version: '',
    authentication: {},
    cust: null,
    plans_enabled: false,
    support_host: '',
    global_banner: '',
    domain_branding: {},
  });

  // const layout = computed(() => {
  //   return route.meta.layout || QuietLayout;
  // });

  // Default props without branding
  const defaultProps: LayoutProps = {
    authenticated: windowProps.authenticated,
    onetimeVersion: windowProps.ot_version,
    authentication: windowProps.authentication,
    colonel: false,
    cust: windowProps.cust,
    supportHost: windowProps.support_host,
    plansEnabled: windowProps.plans_enabled,
    hasGlobalBanner: !!windowProps.global_banner,
    globalBanner: windowProps.global_banner
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
