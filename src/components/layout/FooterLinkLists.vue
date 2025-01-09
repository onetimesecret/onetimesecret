<!-- src/components/layout/FooterLinkLists.vue -->
<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import { WindowService } from '@/services/window.service';

  const windowProps = WindowService.getMultiple([
    'plans_enabled',
    'plan',
    'support_host',
    'authentication',
  ]);
  defineProps<LayoutProps>();

</script>

<template>
  <div class="">
    <div class="mb-8 grid grid-cols-2 gap-8 py-6 pl-4 sm:pl-8 md:grid-cols-3 md:pl-16">
      <!-- Company links -->
      <div class="space-y-4">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Company
        </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <router-link to="/about"
                         class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
                         aria-label="Learn about our company">
              About
            </router-link>
          </li>
          <li v-if="windowProps.plans_enabled && windowProps.authentication.enabled">
            <router-link to="/pricing"
                         class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
                         aria-label="View our subscription pricing">
              Pricing
            </router-link>
          </li>
          <li v-if="windowProps.support_host">
            <a :href="`https://blog.onetimesecret.com`"
               class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
               aria-label="Read our latest blog posts"
               target="_blank"
               rel="noopener noreferrer">Blog</a>
          </li>
        </ul>
      </div>

      <!-- Resources links -->
      <div class="space-y-4">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Resources
        </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <a href="https://github.com/onetimesecret/onetimesecret"
               class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
               aria-label="View our source code on GitHub"
               target="_blank"
               rel="noopener noreferrer">GitHub</a>
          </li>
          <li v-if="windowProps.support_host">
            <a :href="`${windowProps.support_host}/docs`"
               aria-label="Access our documentation"
               class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
               target="_blank"
               rel="noopener noreferrer">Docs</a>
          </li>
          <li v-if="windowProps.support_host">
            <a :href="`${windowProps.support_host}/docs/rest-api`"
               aria-label="Explore our API documentation"
               class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
               target="_blank"
               rel="noopener noreferrer">API</a>
          </li>
          <li>
            <a href="https://status.onetimesecret.com/"
               class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
               aria-label="Check our service status"
               target="_blank"
               rel="noopener noreferrer">Status</a>
          </li>
        </ul>
      </div>

      <!-- Legal links -->
      <div class="col-span-2 space-y-4 md:col-span-1">
        <h3 class="text-xl font-semibold text-gray-800 dark:text-gray-200"> Legals </h3>
        <ul class="prose space-y-2 font-brand dark:prose-invert">
          <li>
            <router-link to="/info/privacy"
                         class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
                         aria-label="Read our Privacy Policy">
              Privacy
            </router-link>
          </li>
          <li>
            <router-link to="/info/terms"
                         class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
                         aria-label="View our Terms and Conditions">
              Terms
            </router-link>
          </li>
          <li>
            <router-link to="/info/security"
                         class="text-xl text-gray-600 transition-colors duration-300 hover:text-brand-500 dark:text-gray-400 dark:hover:text-brand-400 md:text-lg"
                         aria-label="Learn about our security measures">
              Security
            </router-link>
          </li>
        </ul>
      </div>
    </div>

    <!-- Border separator element -->
    <div class="my-2 border-t border-gray-200 dark:border-gray-700"></div>
  </div>
</template>
