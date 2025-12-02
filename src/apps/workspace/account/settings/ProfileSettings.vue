<!-- src/views/account/settings/ProfileSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  // import { useAccount } from '@/composables/useAccount';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import SettingsLayout from '@/shared/components/layout/SettingsLayout.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
  import { WindowService } from '@/services/window.service';
  import { ref, onMounted } from 'vue';

  const { t } = useI18n();
  // const { accountInfo, fetchAccountInfo } = useAccount();

  const windowProps = WindowService.getMultiple(['i18n_enabled']);

  const isLoading = ref(false);

  const handleThemeChange = async (isDark: boolean) => {
    isLoading.value = true;
    try {
      console.log('Theme changed:', isDark);
    } catch (error) {
      console.error('Error changing theme:', error);
    } finally {
      isLoading.value = false;
    }
  };

  onMounted(async () => {
    // await fetchAccountInfo();
  });
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Preferences -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="adjustments-horizontal-solid"
              class="size-5 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.settings.preferences') }}
            </h2>
          </div>
        </div>

        <div class="divide-y divide-gray-200 dark:divide-gray-700">
          <!-- Theme Setting -->
          <div class="px-6 py-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <OIcon
                  collection="carbon"
                  name="light-filled"
                  class="size-5 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ t('appearance') }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.settings.theme.choose_light_or_dark_theme') }}
                  </p>
                </div>
              </div>
              <ThemeToggle
                @theme-changed="handleThemeChange"
                :disabled="isLoading"
                :aria-busy="isLoading" />
            </div>
          </div>

          <!-- Language Setting -->
          <div
            v-if="windowProps.i18n_enabled"
            class="px-6 py-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <OIcon
                  collection="heroicons"
                  name="language"
                  class="size-5 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ t('language') }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.settings.language.select_your_preferred_language') }}
                  </p>
                </div>
              </div>
              <LanguageToggle />
            </div>

            <div class="mt-4 space-y-4">
              <!-- Translation Notice -->
              <div class="rounded-lg bg-blue-50 p-4 dark:bg-blue-900/20">
                <div class="prose prose-sm prose-blue max-w-none dark:prose-invert">
                  <p class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('as-we-add-new-features-our-translations-graduall') }}
                  </p>
                  <p class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('were-grateful-to-the') }}
                    <router-link
                      to="/translations"
                      class="font-medium underline hover:no-underline">
                      {{ t('25-contributors') }}
                    </router-link>
                    {{ t('whove-helped-with-translations-as-we-continue-to') }}
                  </p>
                  <p class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('if-youre-interested-in-translation') }}
                    <a
                      href="https://github.com/onetimesecret/onetimesecret"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-medium underline hover:no-underline">
                      {{ t('our-github-project') }}
                    </a>
                    {{ t('welcomes-contributors-for-both-existing-and-new-') }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
