<!-- src/components/layout/MicroFooter.vue -->

<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import { WindowService } from '@/services/window.service';
  import FooterControls from '@/components/layout/SecretFooterControls.vue';
  import FooterAttribution from '@/components/layout/SecretFooterAttribution.vue';

  withDefaults(defineProps<LayoutProps>(), {});

  const siteHost = WindowService.get('site_host');
</script>
<template>
  <footer
    class="w-full min-w-[320px] bg-gray-100 py-8 transition-colors duration-300 dark:bg-gray-800"
    :aria-label="$t('site-footer')">
    <div class="flex flex-col items-center space-y-8 py-8">
      <div class="flex items-center justify-center">
        <FooterControls :show-language="true" />
      </div>
      <FooterAttribution
        :site-host="siteHost"
        :show-nav="false"
        :show-terms="false" />
    </div>
  </footer>
</template>
