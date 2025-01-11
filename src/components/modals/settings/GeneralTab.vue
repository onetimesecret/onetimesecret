<script setup lang="ts">
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import OIcon from '@/components/icons/OIcon.vue';
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

<template>
  <div class="mx-auto max-w-3xl space-y-8 p-4 sm:p-6">
    <section
      role="region"
      aria-labelledby="appearance-heading"
      class="space-y-4">
      <h3
        id="appearance-heading"
        class="mb-2 text-lg font-semibold text-gray-900 dark:text-white sm:mb-4">
        Appearance
      </h3>
      <div class="rounded-lg bg-gray-50 p-3 dark:bg-gray-800 sm:p-4">
        <div class="flex items-start justify-between gap-2 rounded p-2 sm:flex-row sm:items-center sm:gap-4">
          <div class="flex min-w-0 items-center gap-2">
            <OIcon
              icon="carbon:light-filled"
              class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true"
            />
            <span class="truncate text-sm font-medium text-gray-700 dark:text-gray-300">
              Theme
            </span>
          </div>
          <ThemeToggle
            @theme-changed="handleThemeChange"
            :disabled="isLoading"
            :aria-busy="isLoading"
            class="shrink-0"
          />
        </div>
      </div>
    </section>

    <div
      class="h-px bg-gray-200 dark:bg-gray-700"
      aria-hidden="true"></div>

    <section
      role="region"
      aria-labelledby="language-heading"
      class="space-y-4">
      <h3
        id="language-heading"
        class="mb-2 text-lg font-semibold text-gray-900 dark:text-white sm:mb-4">
        Language
      </h3>
      <div class="rounded-lg bg-gray-50 p-3 dark:bg-gray-800 sm:p-4">
        <LanguageToggle
          @menu-toggled="handleMenuToggled"
          class="w-full"
          :disabled="isLoading"
          :aria-busy="isLoading"
        />
        <div class="prose prose-sm prose-gray mt-4 max-w-none space-y-3 dark:prose-invert sm:mt-6 sm:space-y-4">
          <p class="text-sm leading-relaxed text-gray-600 dark:text-gray-300 sm:text-base">
            As we add new features, our translations gradually need updates to stay current. This affects both
            onetimesecret.com and thousands of self-hosted installations worldwide.
          </p>

          <p class="text-sm leading-relaxed text-gray-600 dark:text-gray-300 sm:text-base">
            We're grateful to the
            <router-link
              to="/translations"
              @click="$emit('close')"
              class="text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 focus-visible:ring-primary-500 -mx-2 inline-block px-2 py-1 font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2">
              25+ contributors
            </router-link>
            who've helped with translations as we continue to develop new features.
          </p>

          <p class="text-sm leading-relaxed text-gray-600 dark:text-gray-300 sm:text-base">
            If you're interested in translation,
            <a
              href="https://github.com/onetimesecret/onetimesecret"
              target="_blank"
              rel="noopener noreferrer"
              class="text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 focus-visible:ring-primary-500 -mx-2 inline-block px-2 py-1 font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2">
              our GitHub project
            </a>
            welcomes contributors for both existing and new languages.
          </p>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
/* Add any component-specific styles here */
</style>
