<template>
  <div class="max-w-3xl mx-auto space-y-8 p-4 sm:p-6">
    <section role="region" aria-labelledby="appearance-heading" class="space-y-4">
      <h3 id="appearance-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white mb-2 sm:mb-4">
        Appearance
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-3 sm:p-4">
        <div class="flex sm:flex-row items-start sm:items-center justify-between gap-2 sm:gap-4 rounded p-2">

            <div class="flex items-center gap-2 min-w-0">
            <Icon icon="carbon:light-filled"
                  class="h-5 w-5 shrink-0 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">
              Theme
            </span>
          </div>
          <ThemeToggle
            @theme-changed="handleThemeChange"
            :disabled="isLoading"
            :aria-busy="isLoading"
            class="shrink-0" />
        </div>
      </div>
    </section>

    <div class="h-px bg-gray-200 dark:bg-gray-700" aria-hidden="true"></div>

    <section role="region" aria-labelledby="language-heading" class="space-y-4">
      <h3 id="language-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white mb-2 sm:mb-4">
        Language
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-3 sm:p-4">
        <LanguageToggle
          @menuToggled="handleMenuToggled"
          class="w-full"
          :disabled="isLoading"
          :aria-busy="isLoading" />
        <div class="prose prose-sm dark:prose-invert prose-gray mt-4 sm:mt-6 max-w-none space-y-3 sm:space-y-4">
          <p class="text-sm sm:text-base text-gray-600 dark:text-gray-300 leading-relaxed">
            As we add new features, our translations gradually need updates to stay current. This affects both
            onetimesecret.com and thousands of self-hosted installations worldwide.
          </p>

          <p class="text-sm sm:text-base text-gray-600 dark:text-gray-300 leading-relaxed">
            We're grateful to the
            <router-link
              to="/translations"
              @click="$emit('close')"
              class="inline-block py-1 px-2 -mx-2 text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 font-medium transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:outline-none">
              25+ contributors
            </router-link>
            who've helped with translations as we continue to develop new features.
          </p>

          <p class="text-sm sm:text-base text-gray-600 dark:text-gray-300 leading-relaxed">
            If you're interested in translation,
            <a href="https://github.com/onetimesecret/onetimesecret"
               target="_blank"
               rel="noopener noreferrer"
               class="inline-block py-1 px-2 -mx-2 text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 font-medium transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:outline-none">
              our GitHub project
            </a>
            welcomes contributors for both existing and new languages.
          </p>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { Icon } from '@iconify/vue';
import { ref } from 'vue';

const isLoading = ref(false);

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'menuToggled'): void;
}>();

const handleMenuToggled = () => {
  emit('menuToggled');
};

const handleThemeChange = async (isDark: boolean) => {
  isLoading.value = true;
  try {
    console.log('Theme changed:', isDark);
    // Add theme change logic here
  } catch (error) {
    console.error('Error changing theme:', error);
  } finally {
    isLoading.value = false;
  }
};
</script>

<style scoped>
/* Add any component-specific styles here */
</style>
