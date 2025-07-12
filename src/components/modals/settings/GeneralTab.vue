<script setup lang="ts">
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { WindowService } from '@/services/window.service';
import { ref } from 'vue';

const isLoading = ref(false);

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'menuToggled'): void;
}>();

const handleMenuToggled = () => {
  emit('menuToggled');
};

const windowProps = WindowService.getMultiple([
  'i18n_enabled',
]);

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
      role="theme"
      aria-labelledby="appearance-heading"
      class="space-y-4">
      <h3
        id="appearance-heading"
        class="mb-2 text-lg font-semibold text-gray-900 dark:text-white sm:mb-4">
        {{ $t('appearance') }}
      </h3>
      <div class="rounded-lg bg-gray-50 p-3 dark:bg-gray-800 sm:p-4">
        <div class="flex items-start justify-between gap-2 rounded p-2 sm:flex-row sm:items-center sm:gap-4">
          <div class="flex min-w-0 items-center gap-2">
            <OIcon
              collection="carbon"
              name="light-filled"
              class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true"
            />
            <span class="truncate text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('theme') }}
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
      v-if="windowProps.i18n_enabled"
      role="language"
      aria-labelledby="language-heading"
      class="space-y-4">
      <h3
        id="language-heading"
        class="mb-2 text-lg font-semibold text-gray-900 dark:text-white sm:mb-4">
        {{ $t('language') }}
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
            {{ $t('as-we-add-new-features-our-translations-graduall') }}
          </p>

          <p class="text-sm leading-relaxed text-gray-600 dark:text-gray-300 sm:text-base">
            {{ $t('were-grateful-to-the') }}
            <router-link
              to="/translations"
              @click="$emit('close')"
              class="text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 focus-visible:ring-primary-500 -mx-2 inline-block px-2 py-1 font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2">
              {{ $t('25-contributors') }}
            </router-link>
            {{ $t('whove-helped-with-translations-as-we-continue-to') }}
          </p>

          <p class="text-sm leading-relaxed text-gray-600 dark:text-gray-300 sm:text-base">
            {{ $t('if-youre-interested-in-translation') }}
            <a
              href="https://github.com/onetimesecret/onetimesecret"
              target="_blank"
              rel="noopener noreferrer"
              class="text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300 focus-visible:ring-primary-500 -mx-2 inline-block px-2 py-1 font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2">
              {{ $t('our-github-project') }}
            </a>
            {{ $t('welcomes-contributors-for-both-existing-and-new-') }}
          </p>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
/* Add any component-specific styles here */
</style>
