<script setup lang="ts">
import type Stripe from 'stripe';

interface Props {
  stripeCustomer: Stripe.Customer | null;
  stripeSubscriptions: Stripe.Subscription[];
}

const props = withDefaults(defineProps<Props>(), {
  stripeCustomer: null,
  stripeSubscriptions: () => []
});
</script>

<template>
  <div v-if="props.stripeSubscriptions.length > 0 && props.stripeCustomer"
       class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-md space-y-6 mb-6 ">

    <header class="flex items-center justify-between">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white flex items-center">
        <svg class="w-6 h-6 mr-2 text-brandcomp-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"></path>
        </svg>
        Subscription
      </h2>
      <a href="/account/billing_portal"
         class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-brandcomp-500 hover:bg-brandcomp-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 transition-colors duration-150">
        Manage Subscription
      </a>
    </header>

    <section class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div class="space-y-4">
        <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">Customer Information</h3>
        <ul class="text-sm text-gray-600 dark:text-gray-400 space-y-2">
          <li>Customer since: {{ new Date(props.stripeCustomer.created * 1000).toLocaleDateString() }}</li>
          <li v-if="props.stripeCustomer.email">Email: {{ props.stripeCustomer.email }}</li>
          <li v-if="props.stripeCustomer.balance !== 0">
            Account balance: ${{ (props.stripeCustomer.balance / 100).toFixed(2) }}
          </li>
        </ul>
      </div>

      <div v-if="props.stripeCustomer.invoice_settings?.default_payment_method" class="space-y-4">
        <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">Default Payment Method</h3>
        <div class="flex items-center text-sm text-gray-600 dark:text-gray-400">
          <svg class="w-8 h-8 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"></path>
          </svg>
          {{ props.stripeCustomer.invoice_settings.default_payment_method.card.brand }}
          ending in {{ props.stripeCustomer.invoice_settings.default_payment_method.card.last4 }}
        </div>
      </div>
    </section>

    <section class="space-y-6">
      <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">Subscriptions</h3>
      <div v-for="subscription in props.stripeSubscriptions"
           :key="subscription?.id"
           class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <div class="flex justify-between items-center mb-4">
          <span :class="[
            'px-2 py-1 text-xs font-semibold rounded-full',
            subscription.status === 'active' ? 'bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100' : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-800 dark:text-yellow-100'
          ]">
            {{ subscription.status.charAt(0).toUpperCase() + subscription.status.slice(1) }}
          </span>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
            ${{ ((subscription.plan.amount * subscription.quantity) / 100).toFixed(2) }} /
            {{ subscription.plan.interval }}
          </span>
        </div>
        <div class="text-sm text-gray-600 dark:text-gray-400">
          <p v-if="subscription.quantity > 1">
            Quantity: {{ subscription.quantity }} x ${{ (subscription.plan.amount / 100).toFixed(2) }}
          </p>
          <p>Next billing date: {{ new Date(subscription.current_period_end * 1000).toLocaleDateString() }}</p>
        </div>
      </div>
    </section>
  </div>
</template>
