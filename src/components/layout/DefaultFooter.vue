<template>
  <footer class="min-w-[320px] bg-gray-100 dark:bg-gray-800 py-8 overflow-visible w-full">
    <div class="container mx-auto px-4 max-w-2xl">
      <div v-if="displayLinks" class="grid grid-cols-2 gap-8 mb-8">
        <!-- Company links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300">Company</h3>
          <ul class="space-y-2">
            <li v-if="plansEnabled && authentication.enabled">
              <router-link to="/pricing" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="Onetime Secret Subscription Pricing">Pricing</router-link>
            </li>
            <li>
              <a href="https://github.com/onetimesecret/onetimesecret" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="View source code on GitHub" rel="noopener noreferrer">GitHub</a>
            </li>
            <li>
              <router-link to="/about" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="About Onetime Secret">About</router-link>
            </li>
            <li v-if="supportHost">
              <a :href="`${supportHost}/blog`" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="Our blogging website">Blog</a>
            </li>
          </ul>
        </div>

        <!-- Legal & Status links -->
        <div class="space-y-4">
          <h3 class="font-semibold text-gray-700 dark:text-gray-300">Legal & Status</h3>
          <ul class="space-y-2">
            <li>
              <router-link to="/info/privacy" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="Read our Privacy Policy">Privacy</router-link>
            </li>
            <li>
              <router-link to="/info/terms" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="Read our Terms and Conditions">Terms</router-link>
            </li>
            <li>
              <router-link to="/info/security" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="View security information">Security</router-link>
            </li>
            <li>
              <a href="https://status.onetimesecret.com/" class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors" aria-label="Check service status" rel="noopener noreferrer">Status</a>
            </li>
          </ul>
        </div>
      </div>

      <div class="flex justify-between items-center pt-4 border-t border-gray-200 dark:border-gray-700">
        <div v-if="displayVersion" class="text-sm text-gray-500 dark:text-gray-400">
          v{{ onetimeVersion }}
        </div>

        <div class="flex items-center space-x-4">
          <button
            v-if="displayFeedback && authentication.enabled"
            @click="openFeedbackModal"
            class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
            aria-label="Open feedback form"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
            </svg>
          </button>
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

  <!-- Feedback Modal -->
  <teleport to="body">
    <div v-if="isFeedbackModalOpen" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white dark:bg-gray-800 p-6 rounded-lg max-w-md w-full">
        <h2 class="text-xl font-bold mb-4 text-gray-900 dark:text-gray-100">Feedback</h2>
        <FeedbackForm :showRedButton="false" @submitted="closeFeedbackModal" />
        <button @click="closeFeedbackModal" class="mt-4 text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors">
          Close
        </button>
      </div>
    </div>
  </teleport>
</template>


<script setup lang="ts">
import { ref } from 'vue';

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

const isLanguageMenuOpen = ref(false);

const handleMenuToggled = (isOpen: boolean) => {
  isLanguageMenuOpen.value = isOpen;
};

const isFeedbackModalOpen = ref(false)

const openFeedbackModal = () => {
  isFeedbackModalOpen.value = true
}

const closeFeedbackModal = () => {
  isFeedbackModalOpen.value = false
}

</script>
