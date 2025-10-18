<script setup lang="ts">
import AccountBillingSection from '@/components/account/AccountBillingSection.vue';
import AccountChangePasswordForm from '@/components/account/AccountChangePasswordForm.vue';
import AccountDeleteButtonWithModalForm from '@/components/account/AccountDeleteButtonWithModalForm.vue';
import APIKeyForm from '@/components/account/APIKeyForm.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { WindowService } from '@/services/window.service';
import { onMounted, computed } from 'vue';
import { useAccountStore } from '@/stores/accountStore';
import { storeToRefs } from 'pinia';
import { useAccount } from '@/composables/useAccount';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Grabbing values from the window properties is a convenient way to get
// preformatted template variables (i.e. the serialized_data from Core::Views::BaseView)
// rather than re-implement them here in Vue. We'll replace all of them
// eventually, but for now, this is a good way to keep momentum going.
const windowProps = WindowService.getMultiple({
  cust: null,
  customer_since: null,
});


const accountStore = useAccountStore();
const { account } = storeToRefs(accountStore);

// New account info composable
const { accountInfo, isLoading: isLoadingAccountInfo, fetchAccountInfo } = useAccount();

// Computed properties for account info display
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

onMounted(async () => {
  await accountStore.fetch();
  await fetchAccountInfo();
});

</script>

<template>
  <div>
    <DashboardTabNav />

    <h1 class="mb-6 text-3xl font-bold dark:text-white">
      {{ $t('your-account') }}
    </h1>
    <p class="mb-4 text-lg dark:text-gray-300">
      {{ $t('account-type-windowprops-plan-options-name', [windowProps.cust?.planid]) }}
    </p>

    <!-- ACCOUNT INFORMATION -->
    <div v-if="accountInfo" class="mb-6 rounded-lg bg-white p-6 shadow dark:bg-gray-800">
      <h2 class="mb-4 flex items-center text-xl font-semibold dark:text-white">
        <i class="fas fa-user-circle mr-2"></i>
        <span class="flex-1">{{ $t('web.auth.account.title') }}</span>
      </h2>
      <div class="space-y-3 pl-3">
        <div class="flex flex-col sm:flex-row sm:items-center">
          <span class="font-medium dark:text-gray-300 sm:w-1/3">{{ $t('web.auth.account.email') }}:</span>
          <span class="dark:text-gray-400">{{ accountInfo.email }}</span>
        </div>
        <div class="flex flex-col sm:flex-row sm:items-center">
          <span class="font-medium dark:text-gray-300 sm:w-1/3">{{ $t('web.auth.account.created') }}:</span>
          <span class="dark:text-gray-400">{{ accountCreatedDate }}</span>
        </div>
        <div class="flex flex-col sm:flex-row sm:items-center">
          <span class="font-medium dark:text-gray-300 sm:w-1/3">{{ $t('web.auth.account.verified') }}:</span>
          <span class="flex items-center gap-2">
            <i v-if="accountInfo.email_verified" class="fas fa-check-circle text-green-500"></i>
            <i v-else class="fas fa-times-circle text-red-500"></i>
            <span class="dark:text-gray-400">{{ emailVerificationStatus }}</span>
          </span>
        </div>
        <div class="flex flex-col sm:flex-row sm:items-center">
          <span class="font-medium dark:text-gray-300 sm:w-1/3">{{ $t('web.auth.account.mfa-status') }}:</span>
          <span class="flex items-center gap-2">
            <i v-if="accountInfo.mfa_enabled" class="fas fa-shield-alt text-green-500"></i>
            <i v-else class="fas fa-shield-alt text-gray-400"></i>
            <span class="dark:text-gray-400">{{ mfaStatus }}</span>
          </span>
        </div>
      </div>

      <!-- Quick actions for account management -->
      <div class="mt-6 border-t border-gray-200 pt-4 dark:border-gray-700">
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
          {{ $t('web.auth.account.quick-actions') }}
        </h3>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <router-link
            to="/account/settings/sessions"
            class="flex items-center gap-3 rounded-lg border border-gray-200 p-3 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700"
          >
            <i class="fas fa-desktop text-brand-600 dark:text-brand-400"></i>
            <span class="text-sm font-medium dark:text-white">{{ $t('web.auth.account.manage-sessions') }}</span>
          </router-link>
          <router-link
            to="/account/settings/password"
            class="flex items-center gap-3 rounded-lg border border-gray-200 p-3 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700"
          >
            <i class="fas fa-lock text-brand-600 dark:text-brand-400"></i>
            <span class="text-sm font-medium dark:text-white">{{ $t('web.auth.account.change-password') }}</span>
          </router-link>
        </div>
      </div>
    </div>

    <!-- Loading state for account info -->
    <div v-else-if="isLoadingAccountInfo" class="mb-6 rounded-lg bg-white p-6 shadow dark:bg-gray-800">
      <div class="flex items-center justify-center py-4">
        <i class="fas fa-spinner fa-spin mr-2 text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">Loading account information...</span>
      </div>
    </div>

    <!-- API KEY -->
    <div class="mb-6 rounded-lg bg-white p-6 shadow dark:bg-gray-800">
      <h2 class="mb-4 flex items-center text-xl font-semibold dark:text-white">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">{{ $t('api-key') }}</span>
      </h2>
      <div class="pl-3">
        <APIKeyForm :apitoken="account?.apitoken" />
      </div>
    </div>

    <!-- BILLING INFO -->
    <AccountBillingSection
      v-if="account && account.stripe_customer"
      :stripe-customer="account.stripe_customer"
      :stripe-subscriptions="account.stripe_subscriptions"
    />

    <!-- PASSWORD CHANGE -->
    <div class="mb-6 rounded-lg bg-white p-6 shadow dark:bg-gray-800">
      <h2 class="mb-4 flex items-center text-xl font-semibold dark:text-white">
        <i class="fas fa-lock mr-2"></i> {{ $t('web.account.changePassword.updatePassword') }}
      </h2>
      <div class="pl-3">
        <AccountChangePasswordForm />
      </div>
    </div>

    <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
      <h2 class="mb-4 flex items-center text-xl font-semibold dark:text-white">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">{{ $t('delete-account') }}</span>
      </h2>
      <div class="pl-3">
        <!-- Added padding-left to align with the title text -->

        <!-- Ensure cust is not null or undefined before rendering the component -->
        <AccountDeleteButtonWithModalForm
          v-if="windowProps.cust"
          :cust="windowProps.cust"
        />
      </div>
    </div>

    <p class="mt-6 text-sm text-gray-600 dark:text-gray-400">
      {{ $t('created-windowprops-cust-secrets_created-secrets', [windowProps.cust?.secrets_created, windowProps.customer_since]) }}
    </p>
  </div>
</template>
