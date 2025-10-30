<!-- src/views/account/AccountSettingsIndex.vue -->

<script setup lang="ts">
import { computed, ref } from 'vue';
import { WindowService } from '@/services/window.service';
import OIcon from '@/components/icons/OIcon.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import JurisdictionInfo from '@/components/modals/settings/JurisdictionInfo.vue';
import JurisdictionList from '@/components/modals/settings/JurisdictionList.vue';
import { useI18n } from 'vue-i18n';

const windowProps = WindowService.getMultiple([
  'i18n_enabled',
  'regions_enabled',
  'cust',
]);

const { t } = useI18n();

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);

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

// Settings sections organized by category
const sections = computed(() => {
  const list = [
    {
      id: 'security',
      icon: { collection: 'heroicons', name: 'shield-check-solid' },
      title: 'web.COMMON.security',
      description: 'web.settings.security_settings_description',
      items: [
        {
          to: '/account/settings/mfa',
          icon: { collection: 'heroicons', name: 'key-solid' },
          label: 'web.auth.mfa.title',
          description: 'web.auth.mfa.setup-description',
          badge: undefined as string | undefined, // TODO: Add MFA status badge
        },
        {
          to: '/account/settings/recovery-codes',
          icon: { collection: 'heroicons', name: 'document-text-solid' },
          label: 'web.auth.recovery-codes.title',
          description: 'web.auth.recovery-codes.description',
          badge: undefined as string | undefined, // TODO: Add recovery codes count
        },
        {
          to: '/account/settings/sessions',
          icon: { collection: 'heroicons', name: 'computer-desktop-solid' },
          label: 'web.auth.sessions.title',
          description: 'web.settings.sessions.manage_active_sessions',
          badge: undefined as string | undefined, // TODO: Add session count
        },
      ],
    },
    {
      id: 'profile',
      icon: { collection: 'heroicons', name: 'user-solid' },
      title: 'web.settings.profile',
      description: 'web.settings.profile_settings_description',
      items: [
        {
          to: '/account/settings/password',
          icon: { collection: 'heroicons', name: 'lock-closed-solid' },
          label: 'web.auth.change-password.title',
          description: 'web.settings.password.update_account_password',
          badge: undefined as string | undefined,
        },
      ],
    },
  ];

  return list;
});
</script>

<template>
  <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Page Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ t('web.account.settings') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.settings.manage_your_account_settings_and_preferences') }}
        </p>
      </div>

      <div class="space-y-8">
        <!-- General Settings Section -->
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
                {{ t('general') }}
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
              <div class="space-y-4">
                <div class="flex items-center gap-3">
                  <OIcon
                    collection="heroicons"
                    name="language-solid"
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

                <LanguageToggle class="w-full max-w-xs" />

                <!-- Translation Notice -->
                <div
                  class="rounded-lg bg-blue-50 p-4 dark:bg-blue-900/20">
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

        <!-- Data Region Section -->
        <section
          v-if="windowProps.regions_enabled"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center gap-3">
              <OIcon
                collection="heroicons"
                name="globe-americas-solid"
                class="size-5 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('data-region') }}
              </h2>
            </div>
          </div>

          <div class="p-6">
            <!-- Current Region -->
            <div class="mb-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-900">
              <div class="flex items-center gap-4">
                <div
                  class="flex size-12 shrink-0 items-center justify-center
                    rounded-full bg-brand-100 dark:bg-brand-900/30">
                  <OIcon
                    v-if="currentJurisdiction?.icon"
                    :collection="currentJurisdiction.icon.collection"
                    :name="currentJurisdiction.icon.name"
                    class="size-6 text-brand-600 dark:text-brand-400"
                    aria-hidden="true" />
                </div>
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ currentJurisdiction?.display_name }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('data-center-location-currentjurisdiction-identif',
                      [currentJurisdiction?.identifier]) }}
                  </p>
                </div>
              </div>
            </div>

            <!-- Jurisdiction Info -->
            <div
              v-if="currentJurisdiction"
              class="mb-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-900">
              <JurisdictionInfo :jurisdiction="currentJurisdiction" />
            </div>

            <!-- Available Regions -->
            <div>
              <h3
                class="mb-3 text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('available-regions') }}
              </h3>
              <JurisdictionList
                :jurisdictions="jurisdictions"
                :currentJurisdiction="currentJurisdiction" />
            </div>
          </div>
        </section>

        <!-- Security Settings Sections -->
        <section
          v-for="section in sections"
          :key="section.id"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center gap-3">
              <OIcon
                :collection="section.icon.collection"
                :name="section.icon.name"
                class="size-5 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <div>
                <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                  {{ t(section.title) }}
                </h2>
                <p class="text-sm text-gray-600 dark:text-gray-400">
                  {{ t(section.description) }}
                </p>
              </div>
            </div>
          </div>

          <div class="divide-y divide-gray-200 dark:divide-gray-700">
            <router-link
              v-for="item in section.items"
              :key="item.to"
              :to="item.to"
              class="block px-6 py-4 transition-colors hover:bg-gray-50
                dark:hover:bg-gray-700/50">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <OIcon
                    :collection="item.icon.collection"
                    :name="item.icon.name"
                    class="size-5 text-gray-400 dark:text-gray-500"
                    aria-hidden="true" />
                  <div>
                    <p class="font-medium text-gray-900 dark:text-white">
                      {{ t(item.label) }}
                    </p>
                    <p class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t(item.description) }}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <span
                    v-if="item.badge"
                    class="rounded-full bg-gray-100 px-2.5 py-0.5
                      text-xs font-medium text-gray-600
                      dark:bg-gray-700 dark:text-gray-300">
                    {{ item.badge }}
                  </span>
                  <OIcon
                    collection="heroicons"
                    name="chevron-right-solid"
                    class="size-5 text-gray-400 dark:text-gray-500"
                    aria-hidden="true" />
                </div>
              </div>
            </router-link>
          </div>
        </section>

        <!-- Danger Zone -->
        <section
          class="rounded-lg border-2 border-red-200 bg-white
            dark:border-red-800 dark:bg-gray-800">
          <div class="border-b-2 border-red-200 px-6 py-4 dark:border-red-800">
            <div class="flex items-center gap-3">
              <OIcon
                collection="heroicons"
                name="exclamation-triangle-solid"
                class="size-5 text-red-600 dark:text-red-400"
                aria-hidden="true" />
              <h2
                class="text-lg font-semibold text-red-600 dark:text-red-400">
                {{ t('web.COMMON.danger_zone') }}
              </h2>
            </div>
          </div>

          <div class="p-6">
            <router-link
              to="/account/settings/close"
              class="flex items-center justify-between rounded-lg border
                border-red-200 p-4 transition-colors hover:bg-red-50
                dark:border-red-800 dark:hover:bg-red-900/20">
              <div class="flex items-center gap-3">
                <OIcon
                  collection="heroicons"
                  name="trash-solid"
                  class="size-5 text-red-500 dark:text-red-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-red-600 dark:text-red-400">
                    {{ t('web.auth.close-account.title') }}
                  </p>
                  <p class="text-sm text-red-500 dark:text-red-400">
                    {{ t('web.settings.delete_account.permanently_delete_your_account') }}
                  </p>
                </div>
              </div>
              <OIcon
                collection="heroicons"
                name="chevron-right-solid"
                class="size-5 text-red-400 dark:text-red-500"
                aria-hidden="true" />
            </router-link>
          </div>
        </section>
      </div>
    </div>
</template>
