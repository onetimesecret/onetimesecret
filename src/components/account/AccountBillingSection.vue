<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';
import type Stripe from 'stripe';

interface Props {
  stripeCustomer: Stripe.Customer | null;
  stripeSubscriptions: Stripe.Subscription[];
}

const props = withDefaults(defineProps<Props>(), {
  stripeCustomer: null,
  stripeSubscriptions: () => []
});

const formatDate = (timestamp: number) => new Date(timestamp * 1000).toLocaleDateString();

const defaultPaymentMethod = computed(() => {
  return props.stripeCustomer?.invoice_settings?.default_payment_method as Stripe.PaymentMethod | undefined;
});

const subscriptionDetails = computed(() => {
  return props.stripeSubscriptions.map(subscription => ({
    id: subscription.id,
    status: subscription.status,
    amount: subscription.items.data[0]?.price?.unit_amount ?? 0,
    quantity: subscription.items.data[0]?.quantity ?? 1,
    interval: subscription.items.data[0]?.price?.recurring?.interval ?? 'month',
    currentPeriodEnd: subscription.current_period_end
  }));
});
</script>

<template>
  <div v-if="props.stripeSubscriptions.length > 0 && props.stripeCustomer"
       class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-md space-y-6 mb-6">

    <header class="flex items-center justify-between">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white flex items-center">
        <Icon icon="mdi:credit-card-outline" class="w-6 h-6 mr-2 text-brandcomp-500" />
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
          <li>Customer since: {{ formatDate(props.stripeCustomer.created) }}</li>
          <li v-if="props.stripeCustomer.email">Email: {{ props.stripeCustomer.email }}</li>
          <li v-if="props.stripeCustomer.balance !== 0">
            Account balance: ${{ (props.stripeCustomer.balance / 100).toFixed(2) }}
          </li>
        </ul>
      </div>

      <div v-if="defaultPaymentMethod?.card" class="space-y-4">
        <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">Default Payment Method</h3>
        <div class="flex items-center text-sm text-gray-600 dark:text-gray-400">
          <Icon icon="mdi:credit-card" class="w-8 h-8 mr-2 text-gray-400" />
          {{ defaultPaymentMethod.card.brand }}
          ending in {{ defaultPaymentMethod.card.last4 }}
        </div>
      </div>
    </section>

    <section class="space-y-6">
      <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">Subscriptions</h3>
      <div v-for="subscription in subscriptionDetails"
           :key="subscription.id"
           class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <div class="flex justify-between items-center mb-4">
          <span :class="[
            'px-2 py-1 text-xs font-semibold rounded-full',
            subscription.status === 'active' ? 'bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100' : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-800 dark:text-yellow-100'
          ]">
            {{ subscription.status.charAt(0).toUpperCase() + subscription.status.slice(1) }}
          </span>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
            ${{ ((subscription.amount * subscription.quantity) / 100).toFixed(2) }} /
            {{ subscription.interval }}
          </span>
        </div>
        <div class="text-sm text-gray-600 dark:text-gray-400">
          <p v-if="subscription.quantity > 1">
            Quantity: {{ subscription.quantity }} x ${{ (subscription.amount / 100).toFixed(2) }}
          </p>
          <p>Next billing date: {{ formatDate(subscription.currentPeriodEnd) }}</p>
        </div>
      </div>
    </section>
  </div>
</template>
