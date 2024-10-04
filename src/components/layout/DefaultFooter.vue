<template>
  <footer class="min-w-[320px] text-sm text-center space-y-2">
    <div class="container mx-auto p-4 max-w-2xl">

      <div v-if="displayFeedback">
        <FeedbackForm :showRedButton="false" />
      </div>

      <div v-if="displayLinks" class="prose dark:prose-invert text-base pt-4 font-brand">
        <template v-if="supportHost">
          <a :href="`${supportHost}/blog`" aria-label="Our blogging website" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Blog</a> |
        </template>

        <template v-if="plansEnabled">
          <router-link to="/pricing" aria-label="Onetime Secret Subscription Pricing" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
            Pricing
          </router-link> |
        </template>

        <a href="https://github.com/onetimesecret/onetimesecret" aria-label="View source code on GitHub" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">GitHub</a> |

        <template v-if="supportHost">
          <a :href="`${supportHost}/docs/rest-api`" aria-label="Our documentation site (in beta)" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">API</a> |
          <a :href="`${supportHost}/docs`" aria-label="Our documentation site (in beta)" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Docs</a>
        </template>
      </div>
      <div v-if="displayLinks" class="prose dark:prose-invert text-base font-brand">
        <router-link to="/info/privacy" aria-label="Read our Privacy Policy" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
          Privacy
        </router-link> |
        <router-link to="/info/terms" aria-label="Read our Terms and Conditions" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
          Terms
        </router-link> |
        <router-link to="/info/security" aria-label="View security information" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
          Security
        </router-link> |
        <a href="https://status.onetimesecret.com/" aria-label="Check service status" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Status</a> |
        <a :href="`${supportHost}/about`" aria-label="About Onetime Secret" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">About</a>
      </div>

      <!-- Dark mode toggle in the bottom left corner -->
      <div class="fixed bottom-4 left-4 z-50">
        <div class="mt-2 text-slate-300">
          <ThemeToggle />
        </div>
      </div>

      <!-- Languages dropdown in the bottom right corner -->
      <div class="fixed text-left bottom-4 right-4 z-50 opacity-60 hover:opacity-100" aria-label="Change language">
        <div class="relative">
          <LanguageToggle />
        </div>
      </div>

      <div v-if="displayVersion" class="text-gray-400 dark:text-gray-500 mt-4 pt-4">
        v{{onetimeVersion}}
      </div>

    </div>
  </footer>
</template>

<script setup lang="ts">
import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
import FeedbackForm from '@/components/FeedbackForm.vue';
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
</script>
