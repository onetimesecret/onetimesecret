<!-- src/apps/workspace/account/settings/ProfileSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useAccount } from '@/shared/composables/useAccount';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import LanguageToggle
    from '@/shared/components/ui/LanguageToggle.vue';
  import SettingsLayout
    from '@/apps/workspace/layouts/SettingsLayout.vue';
  import ThemeToggle
    from '@/shared/components/ui/ThemeToggle.vue';
  import {
    useBootstrapStore,
  } from '@/shared/stores/bootstrapStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { storeToRefs } from 'pinia';
  import { formatDisplayDate } from '@/utils/format';
  import { computed, ref, onMounted } from 'vue';

  const { t } = useI18n();
  const { accountInfo, fetchAccountInfo } = useAccount();

  const bootstrapStore = useBootstrapStore();
  const { i18n_enabled, has_password } = storeToRefs(bootstrapStore);

  const organizationStore = useOrganizationStore();
  const { organizations } = storeToRefs(organizationStore);

  const currentEmail = computed(
    () => bootstrapStore.email
  );

  const emailVerified = computed(
    () => accountInfo.value?.email_verified ?? false
  );

  const accountCreatedDate = computed(() => {
    if (!accountInfo.value?.created_at) return '';
    return formatDisplayDate(new Date(accountInfo.value.created_at));
  });

  const isLoading = ref(false);
  const isLoadingEntitlements = ref(false);

  const defaultOrg = computed(
    () =>
      organizations.value.find((o) => o.is_default) ??
      organizations.value[0] ??
      null
  );

  const { entitlements, formatEntitlement, isStandaloneMode, initDefinitions } =
    useEntitlements(defaultOrg);

  const handleThemeChange = async (
    _isDark: boolean
  ) => {
    isLoading.value = true;
    try {
      // TODO: Persist theme preference to user settings
    } catch (error) {
      console.error('Error changing theme:', error);
    } finally {
      isLoading.value = false;
    }
  };

  onMounted(async () => {
    await fetchAccountInfo();

    isLoadingEntitlements.value = true;
    try {
      await Promise.all([
        organizationStore.fetchOrganizations(),
        initDefinitions(),
      ]);

      const org = defaultOrg.value;
      if (!isStandaloneMode.value && org && (!org.entitlements || org.entitlements.length === 0)) {
        await organizationStore.fetchEntitlements(org.extid);
      }
    } catch (error) {
      console.error('Error loading entitlements:', error);
    } finally {
      isLoadingEntitlements.value = false;
    }
  });
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Email Address -->
      <section
        class="rounded-lg border border-gray-200/60
          bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60
          dark:bg-gray-800/60">
        <div
          class="border-b border-gray-200 px-6 py-4
            dark:border-gray-700">
          <h2 class="flex items-center gap-3 text-lg font-semibold text-gray-900 dark:text-white">
            <OIcon
              collection="heroicons"
              name="envelope"
              class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            {{ t('web.auth.account.email') }}
          </h2>
        </div>

        <div class="px-6 py-4">
          <div
            class="flex items-center
              justify-between">
            <div class="flex items-center gap-3">
              <div>
                <p
                  class="font-medium text-gray-900
                    dark:text-white">
                  {{ currentEmail }}
                </p>
                <div
                  class="mt-1 flex items-center
                    gap-1.5">
                  <!-- SSO users: show linked status -->
                  <template v-if="!has_password">
                    <OIcon
                      collection="heroicons"
                      name="link-solid"
                      class="size-4 text-brand-600
                        dark:text-brand-400"
                      aria-hidden="true" />
                    <span
                      class="text-sm text-brand-600
                        dark:text-brand-400">
                      {{ t('web.auth.account.sso_linked') }}
                    </span>
                  </template>
                  <!-- Password users: show verification status -->
                  <template v-else>
                    <OIcon
                      v-if="emailVerified"
                      collection="heroicons"
                      name="check-circle-solid"
                      class="size-4 text-green-600
                        dark:text-green-400"
                      aria-hidden="true" />
                    <span
                      :class="[
                        'text-sm',
                        emailVerified
                          ? 'text-green-600 dark:text-green-400'
                          : 'text-gray-500 dark:text-gray-400',
                      ]">
                      {{
                        emailVerified
                          ? t('web.auth.account.verified')
                          : t(
                            'web.auth.account.not_verified'
                          )
                      }}
                    </span>
                  </template>
                </div>
              </div>
            </div>
            <router-link
              v-if="has_password"
              to="/account/settings/profile/email"
              class="inline-flex items-center gap-2
                text-sm font-medium text-brand-600
                hover:text-brand-700
                dark:text-brand-400
                dark:hover:text-brand-300">
              {{
                t('web.settings.profile.change_email')
              }}
              <OIcon
                collection="heroicons"
                name="arrow-right-solid"
                class="size-4"
                aria-hidden="true" />
            </router-link>
          </div>

          <div
            v-if="accountCreatedDate"
            class="mt-4 border-t border-gray-200 pt-4 dark:border-gray-700">
            <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.auth.account.created') }}
            </p>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              {{ accountCreatedDate }}
            </p>
          </div>
        </div>
      </section>

      <!-- Preferences -->
      <section
        class="rounded-lg border border-gray-200/60
          bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60
          dark:bg-gray-800/60">
        <div
          class="border-b border-gray-200 px-6 py-4
            dark:border-gray-700">
          <h2 class="flex items-center gap-3 text-lg font-semibold text-gray-900 dark:text-white">
            <OIcon
              collection="heroicons"
              name="adjustments-horizontal-solid"
              class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            {{ t('web.settings.preferences') }}
          </h2>
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
                    {{ t('web.COMMON.appearance') }}
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
            v-if="i18n_enabled"
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
                    {{ t('web.COMMON.language') }}
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
                    {{ t('web.translations.as_we_add_new_features_our_translations_graduall') }}
                  </p>
                  <p class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('web.translations.were_grateful_to_the') }}
                    <a
                      href="https://docs.onetimesecret.com/en/translations/"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-medium underline hover:no-underline">
                      {{ t('web.translations.25_contributors') }}
                    </a>
                    {{ t('web.translations.whove_helped_with_translations_as_we_continue_to') }}
                  </p>
                  <p class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('web.translations.if_youre_interested_in_translation') }}
                    <a
                      href="https://github.com/onetimesecret/onetimesecret"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-medium underline hover:no-underline">
                      {{ t('web.translations.our_github_project') }}
                    </a>
                    {{ t('web.translations.welcomes_contributors_for_both_existing_and_new_') }}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Entitlements -->
      <section
        v-if="!isStandaloneMode && defaultOrg"
        class="rounded-lg border border-gray-200/60
          bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60
          dark:bg-gray-800/60">
        <div
          class="border-b border-gray-200 px-6 py-4
            dark:border-gray-700">
          <h2 class="flex items-center gap-3 text-lg font-semibold text-gray-900 dark:text-white">
            <OIcon
              collection="heroicons"
              name="puzzle-piece"
              class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            {{ t('web.billing.overview.plan_features') }}
          </h2>
        </div>

        <div class="p-6">
          <!-- Loading skeleton -->
          <div
            v-if="isLoadingEntitlements"
            class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div
              v-for="i in 4"
              :key="i"
              class="flex animate-pulse items-center gap-2">
              <div class="size-5 rounded-full bg-gray-200 dark:bg-gray-700"></div>
              <div class="h-4 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
            </div>
          </div>

          <!-- Entitlements list -->
          <div
            v-else-if="entitlements.length > 0"
            class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div
              v-for="ent in entitlements"
              :key="ent"
              class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
              <OIcon
                collection="heroicons"
                name="check-circle"
                class="size-5 text-green-500 dark:text-green-400"
                aria-hidden="true" />
              {{ formatEntitlement(ent) }}
            </div>
          </div>

          <!-- Empty state -->
          <div
            v-else
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.billing.overview.no_entitlements') }}
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
