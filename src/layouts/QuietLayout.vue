<!-- src/layouts/QuietLayout.vue -->
<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import BaseLayout from './BaseLayout.vue';
  import { WindowService } from '@/services/window.service';

  const sitHost = WindowService.get('site_host') ?? null;
  const props = withDefaults(defineProps<LayoutProps>(), {});
</script>

<template>
  <!-- Router View Structure:
    - Named views allow multiple <router-view> components in a single layout.
    - The unnamed <router-view> is the default view for each route.
    - Named views ("header" and "footer") can display different components
      based on the current route configuration.
    - layoutProps are passed to each view for consistent styling and behavior.
  -->
  <BaseLayout v-bind="props">
    <template #header>
      <router-view
        name="header"
        v-bind="props" />
    </template>
    <template #main>
      <main
        class="container mx-auto max-w-2xl p-4"
        name="QuietLayout">
        <slot></slot>
      </main>
    </template>
    <template #footer>
      <router-view
        name="footer"
        v-bind="props" />

      <!-- Powered By Link -->
      <div
        v-if="displayPoweredBy"
        class="mt-8 mb-4 text-center">
        <a
          :href="`https://${sitHost}`"
          class="text-[0.7rem] text-gray-300 transition-colors duration-200 hover:text-gray-400 dark:text-gray-600 dark:hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          rel="noopener noreferrer"
          :aria-label="$t('web.homepage.visit-onetime-secret-home')">
          {{$t('powered-by-onetime-secret')}}
        </a>
      </div>
    </template>
  </BaseLayout>
</template>
