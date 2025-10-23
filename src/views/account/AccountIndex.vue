<script setup lang="ts">
import AccountBillingSection from '@/components/account/AccountBillingSection.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { WindowService } from '@/services/window.service';
import { onMounted, computed } from 'vue';
import { useAccountStore } from '@/stores/accountStore';
import { storeToRefs } from 'pinia';
import { useAccount } from '@/composables/useAccount';
import { useI18n } from 'vue-i18n';
import OIcon from '@/components/icons/OIcon.vue';

const { t } = useI18n();

const windowProps = WindowService.getMultiple({
  cust: null,
  customer_since: null,
});

const accountStore = useAccountStore();
const { account } = storeToRefs(accountStore);

const { accountInfo, isLoading: isLoadingAccountInfo, fetchAccountInfo } = useAccount();

const accountCreatedDate = computed(() => {
  if (!accountInfo.value?.created_at) return '';
  return new Date(accountInfo.value.created_at).toLocaleDateString();
});

const emailVerificationStatus = computed(() => {
  if (!accountInfo.value) return '';
  return accountInfo.value.email_verified
    ? t('web.auth.account.verified')
    : t('web.auth.account.not-verified');
});

const mfaStatus = computed(() => {
  if (!accountInfo.value) return '';
  return accountInfo.value.mfa_enabled
    ? t('web.auth.account.mfa-enabled')
    : t('web.auth.account.mfa-disabled');
});

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

onMounted(async () => {
  await accountStore.fetch();
  await fetchAccountInfo();
});
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
    <DashboardTabNav />

    <div class="mb-8">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ $t('your-account') }}
      </h1>
      <p class="mt-2 text-lg text-gray-600 dark:text-gray-400">
        {{ $t('account-type-windowprops-plan-options-name', [windowProps.cust?.planid]) }}
      </p>
    </div>

    <div class="space-y-6">
      <!-- Account Overview Cards -->
      <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <!-- Account Info Card -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="user-circle-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ $t('web.auth.account.email') }}
              </p>
              <p class="mt-1 text-lg font-semibold text-gray-900 dark:text-white">
                {{ accountInfo?.email || '...' }}
              </p>
            </div>
          </div>
          <div class="mt-4 flex items-center gap-2">
            <OIcon
              v-if="accountInfo?.email_verified"
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            <span
              :class="[
                'text-sm',
                accountInfo?.email_verified
                  ? 'text-green-600 dark:text-green-400'
                  : 'text-gray-500 dark:text-gray-400',
              ]">
              {{ emailVerificationStatus }}
            </span>
          </div>
        </div>

        <!-- Security Status Card -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ $t('web.settings.security.security-score') }}
              </p>
              <p class="mt-1 text-3xl font-bold text-gray-900 dark:text-white">
                {{ securityScore }}
              </p>
              <p class="mt-1 text-sm font-medium text-gray-600 dark:text-gray-400">
                {{ securityLevel.label }}
              </p>
            </div>
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-12 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </div>
          <div class="mt-4">
            <router-link
              to="/account/settings/security"
              class="text-sm font-medium text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('web.settings.security.view-details') }} →
            </router-link>
          </div>
        </div>

        <!-- Member Since Card -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="calendar-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ $t('web.auth.account.created') }}
              </p>
              <p class="mt-1 text-lg font-semibold text-gray-900 dark:text-white">
                {{ accountCreatedDate }}
              </p>
            </div>
          </div>
          <div class="mt-4">
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {{
                $t('created-windowprops-cust-secrets_created-secrets', [
                  windowProps.cust?.secrets_created,
                  windowProps.customer_since,
                ])
              }}
            </p>
          </div>
        </div>
      </div>

      <!-- Quick Actions -->
      <div
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ $t('web.auth.account.quick-actions') }}
          </h2>
        </div>
        <div class="grid gap-4 p-6 sm:grid-cols-2 lg:grid-cols-4">
          <router-link
            to="/account/settings/security"
            class="flex flex-col items-center gap-3 rounded-lg border border-gray-200 p-4 text-center transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="font-medium text-gray-900 dark:text-white">
                {{ $t('web.COMMON.security') }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ $t('web.settings.security_settings_description') }}
              </p>
            </div>
          </router-link>

          <router-link
            to="/account/settings/profile"
            class="flex flex-col items-center gap-3 rounded-lg border border-gray-200 p-4 text-center transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <OIcon
              collection="heroicons"
              name="user-circle-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="font-medium text-gray-900 dark:text-white">
                {{ $t('web.settings.profile') }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ $t('web.settings.profile_settings_description') }}
              </p>
            </div>
          </router-link>

          <router-link
            to="/account/settings/api"
            class="flex flex-col items-center gap-3 rounded-lg border border-gray-200 p-4 text-center transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <OIcon
              collection="heroicons"
              name="code-bracket-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="font-medium text-gray-900 dark:text-white">
                {{ $t('api-key') }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ $t('web.settings.api.manage_api_keys') }}
              </p>
            </div>
          </router-link>

          <router-link
            to="/account/settings"
            class="flex flex-col items-center gap-3 rounded-lg border border-gray-200 p-4 text-center transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <OIcon
              collection="heroicons"
              name="cog-6-tooth-solid"
              class="size-8 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            <div>
              <p class="font-medium text-gray-900 dark:text-white">
                {{ $t('web.account.settings') }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ $t('web.settings.manage_your_account_settings_and_preferences') }}
              </p>
            </div>
          </router-link>
        </div>
      </div>

      <!-- Billing Section -->
      <AccountBillingSection
        v-if="account && account.stripe_customer"
        :stripe-customer="account.stripe_customer"
        :stripe-subscriptions="account.stripe_subscriptions" />
    </div>
  </div>
</template>
