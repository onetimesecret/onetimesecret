<template>
  <div class="max-w-2xl p-4 mx-auto">
    <h1 class="dark:text-white mb-6 text-3xl font-bold">Your Account</h1>
    <p class="dark:text-gray-300 mb-4 text-lg">Account type: {{ plan?.options?.name }}</p>

    <!-- API KEY -->
    <div class="dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">API Key</span>
      </h2>
      <div class="pl-3">

        <APIKeyForm :apitoken="account?.apitoken" :shrimp="shrimp" />

      </div>
    </div>

    <!-- BILLING INFO -->
    <AccountBillingSection :stripe-customer="account?.stripe_customer"
                           :stripe-subscriptions="account?.stripe_subscriptions" />

    <!-- PASSWORD CHANGE -->
    <div class="dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-lock mr-2"></i> Update Password
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->
        <AccountChangePasswordForm :shrimp="shrimp" />
      </div>
    </div>

    <div class="dark:bg-gray-800 p-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">Delete Account</span>
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->

        <AccountDeleteButtonWithModalForm :shrimp="shrimp" :cust="cust" />

      </div>
    </div>

    <p class="dark:text-gray-400 mt-6 text-sm text-gray-600">
      Created {{ cust?.secrets_created }} secrets since {{ customer_since }}.
    </p>

  </div>
</template>

<script setup lang="ts">
import { AccountApiResponse, Account } from '@/types/onetime';
import { ref, onMounted } from 'vue';
import { useWindowProps } from '@/composables/useWindowProps';
import AccountChangePasswordForm from '@/components/account/AccountChangePasswordForm.vue';
import AccountDeleteButtonWithModalForm from '@/components/account/AccountDeleteButtonWithModalForm.vue';
import AccountBillingSection from '@/components/account/AccountBillingSection.vue';
import APIKeyForm from '@/components/account/APIKeyForm.vue';

// Grabbing values from the window properties is a convenient way to get
// preformatted template variables (i.e. the jsvars from Onetime::App::View)
// rather than re-implement them here in Vue. We'll replace all of them
// eventually, but for now, this is a good way to keep momentum going.
const { shrimp, plan, cust, customer_since} = useWindowProps(['shrimp', 'plan', 'cust', 'customer_since' ]);

const account = ref<Account | null>(null)
const isLoading = ref(false)
const error = ref('')


const fetchAccount = async () => {
  isLoading.value = true
  error.value = ''

  try {
    const response = await fetch('/api/v2/account', {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      throw new Error('Failed to fetch account')
    }

    const jsonData: AccountApiResponse = await response.json()
    account.value = jsonData.record;
    console.log(account.value.cust)
  } catch (err: unknown) {
    if (err instanceof Error) {
      error.value = err.message
    } else {
      console.error('An unexpected error occurred', err)
      error.value = 'An unexpected error occurred'
    }
  } finally {
    isLoading.value = false
  }
}

onMounted(() => {
  fetchAccount()
})

</script>
