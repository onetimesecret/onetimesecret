<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 overflow-visible w-full">
    <div class="container mx-auto px-4 max-w-2xl">
      <div v-if="displayLinks"
           class="grid grid-cols-2 gap-8 mb-8">
        <!-- Company links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300">Company</h3>
          <ul class="space-y-2">
            <li v-if="plansEnabled && authentication.enabled">
              <router-link to="/pricing"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                           aria-label="Onetime Secret Subscription Pricing">Pricing</router-link>
            </li>
            <li>
              <a href="https://github.com/onetimesecret/onetimesecret"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                 aria-label="View source code on GitHub"
                 rel="noopener noreferrer">GitHub</a>
            </li>
            <li>
              <router-link to="/about"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                           aria-label="About Onetime Secret">About</router-link>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/blog`"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                 aria-label="Our blogging website">Blog</a>
            </li>
          </ul>
        </div>

        <!-- Legal & Status links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300">Legal & Status</h3>
          <ul class="space-y-2">
            <li>
              <router-link to="/info/privacy"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                           aria-label="Read our Privacy Policy">Privacy</router-link>
            </li>
            <li>
              <router-link to="/info/terms"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                           aria-label="Read our Terms and Conditions">Terms</router-link>
            </li>
            <li>
              <router-link to="/info/security"
                           class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                           aria-label="View security information">Security</router-link>
            </li>
            <li>
              <a href="https://status.onetimesecret.com/"
                 class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
                 aria-label="Check service status"
                 rel="noopener noreferrer">Status</a>
            </li>
          </ul>
        </div>
      </div>

      <div class="flex justify-between items-center pt-4 border-t border-gray-200 dark:border-gray-700">
        <div v-if="displayVersion" class="text-sm text-gray-500 dark:text-gray-400">
          v{{ onetimeVersion }}
        </div>

        <div class="flex items-center space-x-4">
          <FeedbackToggle v-if="displayFeedback && authentication.enabled" />
          <ThemeToggle />
          <div class="relative z-50"
              :class="{ 'opacity-60 hover:opacity-100': !isLanguageMenuOpen }"
              aria-label="Change language">
            <LanguageToggle @menu-toggled="handleMenuToggled" />
          </div>
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

// Define the props for this layout, extending the DefaultLayout props
export interface Props extends DefaultProps {
  displayFeedback?: boolean
  displayLinks?: boolean
  displayVersion?: boolean
}

withDefaults(defineProps<Props>(), {
  displayFeedback: true,
  displayLinks: true,
  displayVersion: true,
});

const isLanguageMenuOpen = ref(false);

const handleMenuToggled = (isOpen: boolean) => {
  isLanguageMenuOpen.value = isOpen;
};

</script>
