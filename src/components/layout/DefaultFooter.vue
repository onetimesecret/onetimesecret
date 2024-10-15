<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 overflow-visible w-full transition-colors duration-75">
    <div class="container my-4 mx-auto px-4 max-w-2xl">
      <div v-if="displayLinks"
           class="grid grid-cols-2 md:grid-cols-3 gap-8 mb-8 py-10 pl-4 sm:pl-8 md:pl-16">

        <!-- Company links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300 text-2xl md:text-xl">Company</h3>
          <ul class="prose dark:prose-invert font-brand">
            <li>
              <router-link to="/about"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                           aria-label="About Onetime Secret">About</router-link>
            </li>
            <li v-if="plansEnabled && authentication.enabled">
              <router-link to="/pricing"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                           aria-label="Onetime Secret Subscription Pricing">Pricing</router-link>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/blog`"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                 aria-label="Our blogging website">Blog</a>
            </li>
          </ul>
        </div>

        <!-- Resources links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300 text-2xl md:text-xl">Resources</h3>
          <ul class="prose dark:prose-invert font-brand">
            <li>
              <a href="https://github.com/onetimesecret/onetimesecret"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                 aria-label="View source code on GitHub"
                 rel="noopener noreferrer">GitHub</a>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/docs`"
                 aria-label="Our documentation site"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                 rel="noopener noreferrer">Docs</a>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/docs/rest-api`"
                 aria-label="Our API documentation"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                 rel="noopener noreferrer">API</a>
            </li>
            <li>
              <a href="https://status.onetimesecret.com/"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                 aria-label="Check service status"
                 rel="noopener noreferrer">Status</a>
            </li>
          </ul>
        </div>

        <!-- Legal links -->
        <div class="space-y-4 col-span-2 md:col-span-1">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300 text-2xl md:text-xl">Legals</h3>
          <ul class="prose dark:prose-invert font-brand">
            <li>
              <router-link to="/info/privacy"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                           aria-label="Read our Privacy Policy">Privacy</router-link>
            </li>
            <li>
              <router-link to="/info/terms"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                           aria-label="Read our Terms and Conditions">Terms</router-link>
            </li>
            <li>
              <router-link to="/info/security"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors text-xl md:text-lg"
                           aria-label="View security information">Security</router-link>
            </li>
          </ul>
        </div>
      </div>

      <div class="flex flex-col sm:flex-row justify-between items-center pt-4
                  border-t border-gray-200 dark:border-gray-700">
        <div v-if="displayVersion"
             class="text-sm text-center sm:text-left mb-4 sm:mb-0 order-2 sm:order-1
                  text-gray-500 dark:text-gray-400">
          &copy; {{ new Date().getFullYear() }} OnetimeSecret.com
        </div>
        <div v-if="displayToggles"
             class="flex items-center space-x-4 mb-4 sm:mb-0 order-1 sm:order-2">
          <JurisdictionToggle />
          <FeedbackToggle v-if="displayFeedback && authentication.enabled" />
          <ThemeToggle />
          <LanguageToggle @menu-toggled="handleMenuToggled" />
        </div>
      </div>
    </div>
  </footer>
</template>

<script setup lang="ts">
import { ref } from 'vue';

import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
import FeedbackToggle from '@/components/FeedbackToggle.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import JurisdictionToggle from '@/components/JurisdictionToggle.vue';

// Define the props for this layout, extending the DefaultLayout props
export interface Props extends DefaultProps {
  displayFeedback?: boolean
  displayLinks?: boolean
  displayVersion?: boolean
  displayToggles?: boolean
}

withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayVersion: true,
  displayToggles: true,
});

const isLanguageMenuOpen = ref(false);

const handleMenuToggled = (isOpen: boolean) => {
  isLanguageMenuOpen.value = isOpen;
};

</script>
