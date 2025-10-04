<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import type Stripe from 'stripe';
  import { computed } from 'vue';

  interface Props {
    stripeCustomer: Stripe.Customer | null;
    stripeSubscriptions?: Stripe.Subscription[] | null;
  }

  const props = withDefaults(defineProps<Props>(), {
    stripeCustomer: null,
    stripeSubscriptions: () => [],
  });

  const formatDate = (timestamp: number) => new Date(timestamp * 1000).toLocaleDateString();

  const defaultPaymentMethod = computed(
    () =>
      props.stripeCustomer?.invoice_settings?.default_payment_method as
        | Stripe.PaymentMethod
        | undefined
  );

  const subscriptionDetails = computed(() =>
    props?.stripeSubscriptions?.map((subscription) => ({
      id: subscription.id,
      status: subscription.status,
      amount: subscription.items.data[0]?.price?.unit_amount ?? 0,
      quantity: subscription.items.data[0]?.quantity ?? 1,
      interval: subscription.items.data[0]?.price?.recurring?.interval ?? 'month',
      currentPeriodEnd: (subscription as any).current_period_end,
    }))
  );
</script>

<template>
  <div
    v-if="props.stripeSubscriptions && props.stripeSubscriptions.length > 0 && props.stripeCustomer"
    class="mb-6 space-y-6 rounded-lg bg-white p-6 shadow-md dark:bg-gray-800">
    <header class="flex items-center justify-between">
      <h2 class="flex items-center text-2xl font-bold text-gray-900 dark:text-white">
        <OIcon
          collection="mdi"
          name="credit-card-outline"
          class="mr-2 size-6 text-brandcomp-500" />
        {{ $t('web.account.subscription_title') }}
      </h2>
      <a
        href="/account/billing_portal"
        class="inline-flex items-center rounded-md border border-transparent bg-brandcomp-500 px-4 py-2 text-sm font-medium text-white transition-colors duration-150 hover:bg-brandcomp-600 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2">
        {{ $t('web.account.manage_subscription') }}
      </a>
    </header>

    <section class="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div class="space-y-4">
        <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">
          {{ $t('web.account.customer_information') }}
        </h3>
        <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
          <li
            >{{ $t('web.account.customer_since') }}
            {{ formatDate(props.stripeCustomer.created) }}</li
          >
          <li v-if="props.stripeCustomer.email">
            {{ $t('web.account.email') }} {{ props.stripeCustomer.email }}
          </li>
          <li v-if="props.stripeCustomer.balance !== 0">
            {{ $t('web.account.account_balance') }} ${{
              (props.stripeCustomer.balance / 100).toFixed(2)
            }}
          </li>
        </ul>
      </div>

      <div
        v-if="defaultPaymentMethod?.card"
        class="space-y-4">
        <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">
          {{ $t('web.account.default_payment_method') }}
        </h3>
        <div class="flex items-center text-sm text-gray-600 dark:text-gray-400">
          <OIcon
            collection="mdi"
            name="credit-card"
            class="mr-2 size-8 text-gray-400" />
          {{ defaultPaymentMethod.card.brand }}
          {{ $t('web.account.card_ending') }} {{ defaultPaymentMethod.card.last4 }}
        </div>
      </div>
    </section>

    <section class="space-y-6">
      <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300">
        {{ $t('web.account.subscriptions_title') }}
      </h3>
      <div
        v-for="subscription in subscriptionDetails"
        :key="subscription.id"
        class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <div class="mb-4 flex items-center justify-between">
          <span
            :class="[
              'rounded-full px-2 py-1 text-xs font-semibold',
              subscription.status === 'active'
                ? 'bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100'
                : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-800 dark:text-yellow-100',
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
            {{ $t('web.account.quantity') }} {{ subscription.quantity }} x ${{
              (subscription.amount / 100).toFixed(2)
            }}
          </p>
          <p
            >{{ $t('web.account.next_billing_date') }}
            {{ formatDate(subscription.currentPeriodEnd) }}</p
          >
        </div>
      </div>
    </section>
  </div>
</template>
