<!-- src/apps/workspace/account/settings/ProfileSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useAccount } from '@/shared/composables/useAccount';
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
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { storeToRefs } from 'pinia';
  import { formatDisplayDate } from '@/utils/format';
  import { isOwnerOrAdminOf } from '@/utils/features';
  import axios from 'axios';
  import { computed, ref, onMounted, useId, watch } from 'vue';

  const { t } = useI18n();
  const { accountInfo, fetchAccountInfo } = useAccount();
  const organizationStore = useOrganizationStore();
  const notifications = useNotificationsStore();

  const bootstrapStore = useBootstrapStore();
  const { i18n_enabled, has_password } = storeToRefs(bootstrapStore);
  const canChangeEmail = computed(() => has_password.value && isOwnerOrAdminOf(bootstrapStore));
  const isOwner = computed(() => bootstrapStore.organization?.current_user_role === 'owner');

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

  /*
   * Default workspace. Here rather than only on /orgs ("Make default"),
   * which is owner-only: a user who joined by invitation or tenant SSO owns
   * nothing, yet can belong to several organizations and needs to choose
   * where a new session starts. The endpoint only requires membership.
   */
  const defaultWorkspaceId = useId();
  const defaultWorkspaceDescriptionId = useId();

  // The list endpoint already leaves out archived organizations.
  const organizations = computed(() => organizationStore.organizations);
  const showDefaultWorkspace = computed(() => organizations.value.length > 1);

  // This user's default (is_current_user_default), not the owner's
  // auto-created workspace (is_default). Empty when none is recorded, e.g.
  // an invitee who has not chosen one: the select then shows "Not set"
  // instead of implying the first organization.
  const currentDefaultObjid = computed(
    () => organizations.value.find((org) => org.is_current_user_default)?.objid ?? ''
  );
  const selectedDefaultObjid = ref('');
  const isSavingDefault = ref(false);

  watch(
    currentDefaultObjid,
    (objid) => {
      selectedDefaultObjid.value = objid;
    },
    { immediate: true }
  );

  /**
   * Save the chosen default. The server also selects the organization for
   * this session, and the store makes it current in this tab, as "Make
   * default" on /orgs does. On failure the select goes back to the stored
   * default.
   */
  const handleDefaultWorkspaceChange = async () => {
    const previous = currentDefaultObjid.value;
    const org = organizations.value.find((o) => o.objid === selectedDefaultObjid.value);
    if (!org || org.objid === previous) return;

    isSavingDefault.value = true;
    try {
      await organizationStore.setDefaultOrganization(org);
      notifications.show(
        t('web.organizations.make_default_success', { name: org.display_name }),
        'success',
        'top'
      );
    } catch (error) {
      console.error('[ProfileSettings] Error setting default organization:', error);
      selectedDefaultObjid.value = previous;
      notifications.show(
        t('web.organizations.make_default_error', { name: org.display_name }),
        'error',
        'top'
      );
    } finally {
      isSavingDefault.value = false;
    }
  };

  /**
   * Load the organization list unless it is loaded or loading. On workspace
   * pages OrganizationContextBar usually starts this fetch first; a second
   * call would cancel that one (fetchOrganizations aborts the previous list
   * fetch) and skip the bar's fallback selection.
   */
  const ensureOrganizationsLoaded = async () => {
    if (organizationStore.isListFetched || organizationStore.loading) return;
    try {
      await organizationStore.fetchOrganizations();
    } catch (error) {
      if (axios.isCancel(error)) return; // superseded by another list fetch
      console.error('[ProfileSettings] Failed to fetch organizations:', error);
    }
  };

  onMounted(async () => {
    await Promise.all([fetchAccountInfo(), ensureOrganizationsLoaded()]);
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
                  <!-- Password users: show verification status.
                       Light mode uses green-700: green-600 small text on
                       this translucent card is ~3.2:1, below WCAG AA 4.5:1. -->
                  <template v-else>
                    <OIcon
                      v-if="emailVerified"
                      collection="heroicons"
                      name="check-circle-solid"
                      class="size-4 text-green-700
                        dark:text-green-400"
                      aria-hidden="true" />
                    <span
                      :class="[
                        'text-sm',
                        emailVerified
                          ? 'text-green-700 dark:text-green-400'
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
              v-if="canChangeEmail"
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

            <div
              v-if="isOwner"
              class="mt-4 space-y-4">
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

          <!-- Default Workspace Setting -->
          <div
            v-if="showDefaultWorkspace"
            class="px-6 py-4"
            data-testid="default-workspace-setting">
            <div class="flex items-center justify-between gap-4">
              <div class="flex items-center gap-3">
                <OIcon
                  collection="heroicons"
                  name="building-office"
                  class="size-5 shrink-0 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
                <div>
                  <label
                    :for="defaultWorkspaceId"
                    class="font-medium text-gray-900 dark:text-white">
                    {{ t('web.settings.default_workspace.title') }}
                  </label>
                  <p
                    :id="defaultWorkspaceDescriptionId"
                    class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.settings.default_workspace.description') }}
                  </p>
                </div>
              </div>
              <select
                :id="defaultWorkspaceId"
                v-model="selectedDefaultObjid"
                :aria-describedby="defaultWorkspaceDescriptionId"
                :aria-busy="isSavingDefault"
                :disabled="isSavingDefault"
                data-testid="default-workspace-select"
                class="block w-40 shrink-0 rounded-md border-gray-300 shadow-sm
                  focus:border-brand-500 focus:ring-brand-500
                  disabled:cursor-not-allowed disabled:opacity-50 sm:w-64 sm:text-sm
                  dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                @change="handleDefaultWorkspaceChange">
                <option
                  v-if="!currentDefaultObjid"
                  value=""
                  disabled>
                  {{ t('web.settings.default_workspace.not_set') }}
                </option>
                <option
                  v-for="org in organizations"
                  :key="org.objid"
                  :value="org.objid">
                  {{ org.display_name }}
                </option>
              </select>
            </div>
          </div>
        </div>
      </section>

    </div>
  </SettingsLayout>
</template>
