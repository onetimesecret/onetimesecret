<!-- src/apps/workspace/account/settings/SecurityOverview.vue -->

<script setup lang="ts">
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useAccount } from '@/shared/composables/useAccount';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { AccountInfo } from '@/types/auth';
  import { hasPasswordOf, isMfaEnabledOf, isSsoEnabledOf, isWebAuthnEnabledOf } from '@/utils/features';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();

  // Feature toggles — derived from the reactive bootstrap store so they reflect
  // post-login state without re-mounting (e.g. after checkWindowStatus refresh).
  const showSessionsCard = ref(false);
  const mfaFeatureEnabled = computed(() => isMfaEnabledOf(bootstrapStore));
  const webAuthnEnabled = computed(() => isWebAuthnEnabledOf(bootstrapStore));
  const ssoEnabled = computed(() => isSsoEnabledOf(bootstrapStore));
  const hasPw = computed(() => hasPasswordOf(bootstrapStore));
  const { accountInfo, fetchAccountInfo } = useAccount();

  interface SecurityCard {
    id: string;
    icon: { collection: string; name: string };
    title: string;
    description: string;
    status: 'active' | 'inactive' | 'warning';
    statusText: string;
    action: {
      label: string;
      to: string;
    };
  }

  // Helper to build core security cards
  function buildCoreCards(info: AccountInfo): SecurityCard[] {
    return [
      {
        id: 'password',
        icon: { collection: 'heroicons', name: 'lock-closed-solid' },
        title: t('web.auth.change_password.title'),
        description: t('web.settings.password.update_account_password'),
        status: 'active',
        statusText: t('web.settings.security.configured'),
        action: {
          label: t('web.settings.security.change'),
          to: '/account/settings/security/password',
        },
      },
      {
        id: 'mfa',
        icon: { collection: 'heroicons', name: 'key-solid' },
        title: t('web.auth.mfa.title'),
        description: t('web.auth.mfa.setup_description'),
        status: info.mfa_enabled ? 'active' : 'warning',
        statusText: info.mfa_enabled
          ? t('web.auth.account.mfa_enabled')
          : t('web.auth.account.mfa_disabled'),
        action: {
          label: info.mfa_enabled ? t('web.settings.security.manage') : t('web.settings.security.enable'),
          to: '/account/settings/security/mfa',
        },
      },
      {
        id: 'recovery-codes',
        icon: { collection: 'heroicons', name: 'document-text-solid' },
        title: t('web.auth.recovery_codes.title'),
        description: t('web.auth.recovery_codes.description'),
        status: info.recovery_codes_count > 0 ? 'active' : 'inactive',
        statusText:
          info.recovery_codes_count > 0
            ? t('web.settings.security.codes_available', [info.recovery_codes_count])
            : t('web.settings.security.no_codes'),
        action: {
          label: t('web.settings.security.manage'),
          to: '/account/settings/security/recovery-codes',
        },
      },
    ];
  }

  // Helper to build passkey card
  function buildPasskeyCard(info: AccountInfo): SecurityCard {
    const passkeyCount = info.passkeys_count ?? 0;
    return {
      id: 'passkeys',
      icon: { collection: 'heroicons', name: 'finger-print-solid' },
      title: t('web.auth.passkeys.title'),
      description: t('web.auth.passkeys.description'),
      status: passkeyCount > 0 ? 'active' : 'inactive',
      statusText:
        passkeyCount > 0
          ? t('web.auth.passkeys.count', { count: passkeyCount }, passkeyCount)
          : t('web.auth.passkeys.not_configured'),
      action: {
        label: passkeyCount > 0 ? t('web.settings.security.manage') : t('web.settings.security.enable'),
        to: '/account/settings/security/passkeys',
      },
    };
  }

  // Helper to build connected-identities card (SSO account-linking, #3840).
  // NOT password-dependent — SSO-only accounts are the primary audience.
  function buildConnectionsCard(): SecurityCard {
    return {
      id: 'connections',
      icon: { collection: 'heroicons', name: 'globe-alt-solid' },
      title: t('web.auth.connections.title'),
      description: t('web.auth.connections.description'),
      status: 'active',
      statusText: t('web.auth.connections.overview_status'),
      action: {
        label: t('web.settings.security.manage'),
        to: '/account/settings/security/connections',
      },
    };
  }

  // Helper to build sessions card
  function buildSessionsCard(info: AccountInfo): SecurityCard {
    return {
      id: 'sessions',
      icon: { collection: 'heroicons', name: 'computer-desktop-solid' },
      title: t('web.auth.sessions.title'),
      description: t('web.settings.sessions.manage_active_sessions'),
      status: 'active',
      statusText: t('web.settings.security.active_sessions', [info.active_sessions_count || 1]),
      action: {
        label: t('web.settings.security.manage'),
        to: '/account/settings/security/sessions',
      },
    };
  }

  const PASSWORD_DEPENDENT_CARDS = new Set(['password', 'mfa', 'recovery-codes']);

  const securityCards = computed<SecurityCard[]>(() => {
    if (!accountInfo.value) return [];

    let cards = buildCoreCards(accountInfo.value);

    if (!hasPw.value) {
      cards = cards.filter((c) => !PASSWORD_DEPENDENT_CARDS.has(c.id));
    }

    // Hide MFA and recovery codes cards when MFA feature is disabled
    if (!mfaFeatureEnabled.value) {
      cards = cards.filter((c) => c.id !== 'mfa' && c.id !== 'recovery-codes');
    }

    if (webAuthnEnabled.value) {
      cards.push(buildPasskeyCard(accountInfo.value));
    }

    // Connected identities card — not password-dependent, so it is added after
    // the SSO-only card filter above and shown whenever SSO is enabled.
    if (ssoEnabled.value) {
      cards.push(buildConnectionsCard());
    }

    if (showSessionsCard.value) {
      cards.push(buildSessionsCard(accountInfo.value));
    }

    return cards;
  });

  const statusColorClasses = {
    active: 'bg-green-50 text-green-700 ring-green-600/20 dark:bg-green-900/20 dark:text-green-400',
    inactive: 'bg-gray-50 text-gray-600 ring-gray-500/20 dark:bg-gray-900/20 dark:text-gray-400',
    warning:
      'bg-yellow-50 text-yellow-800 ring-yellow-600/20 dark:bg-yellow-900/20 dark:text-yellow-400',
  };

  onMounted(async () => {
    await fetchAccountInfo();
  });
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- SSO empty state — shown when all cards are filtered out -->
      <!-- prettier-ignore-attribute class -->
      <div
        v-if="!hasPw && securityCards.length === 0"
        class="
          rounded-lg border border-gray-200/60 bg-white/60 p-6 shadow-sm backdrop-blur-sm
          dark:border-gray-700/60 dark:bg-gray-800/60">
        <div class="flex items-start gap-4">
          <!-- prettier-ignore-attribute class -->
          <div
            class="
              flex size-12 shrink-0 items-center justify-center rounded-lg
              bg-brand-50 dark:bg-brand-900/20">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-6 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </div>
          <div>
            <h3 class="text-base font-medium text-gray-900 dark:text-white">
              {{ t('web.settings.security.sso_managed_title') }}
            </h3>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.settings.security.sso_managed_description') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Security Settings Cards -->
      <div
        v-if="securityCards.length > 0"
        class="grid gap-6 sm:grid-cols-2">
        <!-- prettier-ignore-attribute class -->
        <div
          v-for="card in securityCards"
          :key="card.id"
          class="
            rounded-lg border border-gray-200/60 bg-white/60 p-6 shadow-sm backdrop-blur-sm
            dark:border-gray-700/60 dark:bg-gray-800/60">
          <div class="flex items-start gap-4">
            <!-- prettier-ignore-attribute class -->
            <div
              class="
                flex size-12 shrink-0 items-center justify-center rounded-lg
                bg-gray-100 dark:bg-gray-700">
              <OIcon
                :collection="card.icon.collection"
                :name="card.icon.name"
                class="size-6 text-gray-600 dark:text-gray-400"
                aria-hidden="true" />
            </div>
            <div class="flex-1">
              <h3 class="text-base font-medium text-gray-900 dark:text-white">
                {{ card.title }}
              </h3>
              <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                {{ card.description }}
              </p>

              <!-- Status Badge -->
              <div class="mt-3">
                <span
                  :class="[
                    'inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset',
                    statusColorClasses[card.status],
                  ]">
                  {{ card.statusText }}
                </span>
              </div>

              <!-- Action Button -->
              <div class="mt-4">
                <!-- prettier-ignore-attribute class -->
                <router-link
                  :to="card.action.to"
                  class="
                    inline-flex items-center gap-2 text-sm font-medium text-brand-600
                    hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
                  {{ card.action.label }}
                  <OIcon
                    collection="heroicons"
                    name="arrow-right-solid"
                    class="size-4"
                    aria-hidden="true" />
                </router-link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
