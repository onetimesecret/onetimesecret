<!-- src/views/account/settings/ProfileSettings.vue -->

<script setup lang="ts">
  import { ref, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  // import { useAccount } from '@/composables/useAccount';
  import { WindowService } from '@/services/window.service';
  import OIcon from '@/components/icons/OIcon.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import SettingsLayout from '@/components/layout/SettingsLayout.vue';

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
      <!-- Account Information -->
      <!-- <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="user-solid"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.auth.account.title') }}
          </h2>
        </div>
      </div>

      <div class="p-6">
        <div v-if="accountInfo" class="space-y-4">
          <div class="flex items-center justify-between py-3">
            <div>
              <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.account.email') }}
              </p>
              <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                {{ accountInfo.email }}
              </p>
            </div>
            <div class="flex items-center gap-2">
              <OIcon
                v-if="accountInfo.email_verified"
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <span
                :class="[
                  'text-sm font-medium',
                  accountInfo.email_verified
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-gray-500 dark:text-gray-400',
                ]">
                {{
                  accountInfo.email_verified
                    ? t('web.auth.account.verified')
                    : t('web.auth.account.not-verified')
                }}
              </span>
            </div>
          </div>

          <div class="border-t border-gray-200 dark:border-gray-700" ></div>

          <div class="py-3">
            <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.auth.account.created') }}
            </p>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              {{ new Date(accountInfo.created_at).toLocaleDateString() }}
            </p>
          </div>
        </div>

        <div v-else class="flex items-center justify-center py-8">
          <OIcon
            collection="heroicons"
            name="arrow-path-solid"
            class="mr-2 size-5 animate-spin text-gray-400"
            aria-hidden="true" />
          <span class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('loading_ellipses') }}
          </span>
        </div>
      </div>
    </section> -->

      <!-- Privacy Settings -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="mt-0.5 size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <div class="min-w-0 flex-1">
              <h2 class="text-lg font-semibold leading-tight text-gray-900 dark:text-white">
                {{ t('web.settings.privacy.title') }}
              </h2>
              <p class="mt-1 text-sm leading-tight text-gray-600 dark:text-gray-400">
                {{ t('web.settings.privacy.manage-privacy-settings') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <div class="space-y-4">
            <!-- No Analytics Statement -->
            <div class="flex items-center justify-between">
              <div class="flex-1">
                <div class="mb-2 flex items-center gap-2">
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ t('web.settings.privacy.your-privacy') }}
                  </p>
                  <span
                    class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/30 dark:text-green-400">
                    {{ t('web.settings.privacy.non-negotiable') }}
                  </span>
                </div>
                <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.settings.privacy.no-analytics-statement') }}
                </p>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.settings.privacy.explanation') }}
                </p>
              </div>

              <!-- Disabled Toggle (in "on" position) -->
              <div
                role="switch"
                aria-checked="true"
                aria-disabled="true"
                aria-label="Privacy protection is always enabled"
                class="relative inline-flex h-6 w-11 shrink-0 cursor-not-allowed rounded-full border-2 border-transparent bg-green-600 opacity-50 dark:bg-green-500">
                <span
                  aria-hidden="true"
                  class="pointer-events-none inline-block size-5 translate-x-5 transform rounded-full bg-white shadow ring-0"></span>
              </div>
            </div>
          </div>
        </div>
      </section>

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
