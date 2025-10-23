<!-- src/views/account/settings/SecurityOverview.vue -->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from '@/composables/useAccount';
import OIcon from '@/components/icons/OIcon.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';


const { t } = useI18n();
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

const securityScore = computed(() => {
  if (!accountInfo.value) return 0;

  let score = 0;
  if (accountInfo.value.email_verified) score += 25;
  if (accountInfo.value.mfa_enabled) score += 50;
  if (accountInfo.value.recovery_codes_count > 0) score += 25;

  return score;
});

const securityLevel = computed(() => {
  const score = securityScore.value;
  if (score >= 90) return { label: t('web.settings.security.excellent'), color: 'green' };
  if (score >= 70) return { label: t('web.settings.security.good'), color: 'blue' };
  if (score >= 50) return { label: t('web.settings.security.fair'), color: 'yellow' };
  return { label: t('web.settings.security.weak'), color: 'red' };
});

const securityCards = computed<SecurityCard[]>(() => {
  if (!accountInfo.value) return [];

  return [
    {
      id: 'password',
      icon: { collection: 'heroicons', name: 'lock-closed-solid' },
      title: t('web.auth.change-password.title'),
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
      description: t('web.auth.mfa.setup-description'),
      status: accountInfo.value.mfa_enabled ? 'active' : 'warning',
      statusText: accountInfo.value.mfa_enabled
        ? t('web.auth.account.mfa-enabled')
        : t('web.auth.account.mfa-disabled'),
      action: {
        label: accountInfo.value.mfa_enabled
          ? t('web.settings.security.manage')
          : t('web.settings.security.enable'),
        to: '/account/settings/security/mfa',
      },
    },
    {
      id: 'recovery-codes',
      icon: { collection: 'heroicons', name: 'document-text-solid' },
      title: t('web.auth.recovery-codes.title'),
      description: t('web.auth.recovery-codes.description'),
      status:
        accountInfo.value.recovery_codes_count > 0 ? 'active' : 'inactive',
      statusText:
        accountInfo.value.recovery_codes_count > 0
          ? t('web.settings.security.codes-available', [
              accountInfo.value.recovery_codes_count,
            ])
          : t('web.settings.security.no-codes'),
      action: {
        label: t('web.settings.security.manage'),
        to: '/account/settings/security/recovery-codes',
      },
    },
    {
      id: 'sessions',
      icon: { collection: 'heroicons', name: 'computer-desktop-solid' },
      title: t('web.auth.sessions.title'),
      description: t('web.settings.sessions.manage_active_sessions'),
      status: 'active',
      statusText: t('web.settings.security.active-sessions', [
        accountInfo.value.active_sessions_count || 1,
      ]),
      action: {
        label: t('web.settings.security.manage'),
        to: '/account/settings/security/sessions',
      },
    },
  ];
});

const statusColorClasses = {
  active: 'bg-green-50 text-green-700 ring-green-600/20 dark:bg-green-900/20 dark:text-green-400',
  inactive: 'bg-gray-50 text-gray-600 ring-gray-500/20 dark:bg-gray-900/20 dark:text-gray-400',
  warning: 'bg-yellow-50 text-yellow-800 ring-yellow-600/20 dark:bg-yellow-900/20 dark:text-yellow-400',
};

const scoreColorClasses = {
  green: 'text-green-600 dark:text-green-400',
  blue: 'text-blue-600 dark:text-blue-400',
  yellow: 'text-yellow-600 dark:text-yellow-400',
  red: 'text-red-600 dark:text-red-400',
};

const progressBarColorClasses = {
  green: 'bg-green-600',
  blue: 'bg-blue-600',
  yellow: 'bg-yellow-600',
  red: 'bg-red-600',
};

onMounted(async () => {
  await fetchAccountInfo();
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
    <!-- Security Score Card -->
    <div
      class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
      <div class="flex items-start justify-between">
        <div>
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.settings.security.security-score') }}
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.settings.security.score-description') }}
          </p>
        </div>
        <div class="text-right">
          <div
            :class="[
              'text-4xl font-bold',
              scoreColorClasses[securityLevel.color],
            ]">
            {{ securityScore }}
          </div>
          <div
            class="mt-1 text-sm font-medium"
            :class="scoreColorClasses[securityLevel.color]">
            {{ securityLevel.label }}
          </div>
        </div>
      </div>

      <!-- Progress Bar -->
      <div class="mt-4">
        <div class="h-2 w-full overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700">
          <div
            :class="[
              'h-full transition-all duration-500',
              progressBarColorClasses[securityLevel.color],
            ]"
            :style="{ width: `${securityScore}%` }" ></div>
        </div>
      </div>

      <!-- Recommendations -->
      <div
        v-if="securityScore < 100"
        class="mt-4 rounded-lg bg-blue-50 p-4 dark:bg-blue-900/20">
        <div class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle-solid"
            class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm text-blue-700 dark:text-blue-300">
            <p class="font-medium">
              {{ t('web.settings.security.improve-security') }}
            </p>
            <ul class="mt-2 list-inside list-disc space-y-1">
              <li v-if="!accountInfo?.mfa_enabled">
                {{ t('web.settings.security.enable-mfa-recommendation') }}
              </li>
              <li v-if="!accountInfo?.recovery_codes_count">
                {{ t('web.settings.security.generate-recovery-codes-recommendation') }}
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>

    <!-- Security Settings Cards -->
    <div class="grid gap-6 sm:grid-cols-2">
      <div
        v-for="card in securityCards"
        :key="card.id"
        class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
        <div class="flex items-start gap-4">
          <div
            class="flex size-12 shrink-0 items-center justify-center rounded-lg bg-gray-100 dark:bg-gray-700">
            <OIcon
              :collection="card.icon.collection"
              :name="card.icon.name"
              class="size-6 text-gray-600 dark:text-gray-400"
              aria-hidden="true" />
          </div>
          <div class="flex-1">
            <h3 class="font-semibold text-gray-900 dark:text-white">
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
              <router-link
                :to="card.action.to"
                class="inline-flex items-center gap-2 text-sm font-medium text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
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

    <!-- Security Best Practices -->
    <div
      class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
      <h2 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
        <OIcon
          collection="heroicons"
          name="light-bulb-solid"
          class="size-5 text-yellow-500"
          aria-hidden="true" />
        {{ t('web.settings.security.best-practices') }}
      </h2>
      <ul class="mt-4 space-y-3 text-sm text-gray-600 dark:text-gray-400">
        <li class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-5 shrink-0 text-green-600 dark:text-green-400"
            aria-hidden="true" />
          {{ t('web.settings.security.use-strong-unique-password') }}
        </li>
        <li class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-5 shrink-0 text-green-600 dark:text-green-400"
            aria-hidden="true" />
          {{ t('web.settings.security.enable-mfa-for-protection') }}
        </li>
        <li class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-5 shrink-0 text-green-600 dark:text-green-400"
            aria-hidden="true" />
          {{ t('web.settings.security.save-recovery-codes-safely') }}
        </li>
        <li class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-5 shrink-0 text-green-600 dark:text-green-400"
            aria-hidden="true" />
          {{ t('web.settings.security.review-sessions-regularly') }}
        </li>
      </ul>
    </div>
    </div>
  </SettingsLayout>
</template>
