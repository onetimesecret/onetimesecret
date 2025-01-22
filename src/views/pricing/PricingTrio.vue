<script setup lang="ts">
  import { ref } from 'vue';
  import { RadioGroup, RadioGroupOption } from '@headlessui/vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import type { PaymentFrequency, ProductTier } from '@/sources/productTiers';

  const frequencies: PaymentFrequency[] = [
    { value: 'monthly', label: 'Monthly', priceSuffix: '/month' },
    { value: 'annually', label: 'Annually', priceSuffix: '/year' },
  ];
  const tiers: ProductTier[] = [
    {
      name: 'Freelancer',
      id: 'tier-freelancer',
      href: '#',
      price: { monthly: '$19', annually: '$199' },
      description: 'The essentials to provide your best work for clients.',
      features: ['5 products', 'Up to 1,000 subscribers', 'Basic analytics', '48-hour support response time'],
      featured: false,
      cta: 'Buy plan',
    },
    {
      name: 'Startup',
      id: 'tier-startup',
      href: '#',
      price: { monthly: '$29', annually: '$299' },
      description: 'A plan that scales with your rapidly growing business.',
      features: [
        '25 products',
        'Up to 10,000 subscribers',
        'Advanced analytics',
        '24-hour support response time',
        'Marketing automations',
      ],
      featured: false,
      cta: 'Buy plan',
    },
    {
      name: 'Enterprise',
      id: 'tier-enterprise',
      href: '#',
      price: { monthly: 'Custom', annually: 'Custom' },
      description: 'Dedicated support and infrastructure for your company.',
      features: [
        'Unlimited products',
        'Unlimited subscribers',
        'Advanced analytics',
        '1-hour, dedicated support response time',
        'Marketing automations',
        'Custom reporting tools',
      ],
      featured: true,
      cta: 'Contact sales',
    },
  ];

  const frequency = ref<PaymentFrequency>(frequencies[0])
</script>

<template>
  <div class="bg-white py-24 sm:py-32">
    <div class="mx-auto max-w-7xl px-6 lg:px-8">
      <div class="mx-auto max-w-4xl text-center">
        <h2 class="text-base/7 font-semibold text-indigo-600">Pricing</h2>
        <p class="mt-2 text-5xl font-semibold tracking-tight text-balance text-gray-900 sm:text-6xl">
          Pricing that grows with you
        </p>
      </div>
      <p class="mx-auto mt-6 max-w-2xl text-center text-lg font-medium text-pretty text-gray-600 sm:text-xl/8">
        Choose an affordable plan that’s packed with the best features for engaging your audience, creating customer
        loyalty, and driving sales.
      </p>
      <div class="mt-16 flex justify-center">
        <fieldset aria-label="Payment frequency">
          <RadioGroup
            v-model="frequency"
            class="grid grid-cols-2 gap-x-1 rounded-full p-1 text-center text-xs/5 font-semibold ring-1 ring-gray-200 ring-inset">
            <RadioGroupOption
              as="template"
              v-for="option in frequencies"
              :key="option.value"
              :value="option"
              v-slot="{ checked }">
              <div
                :class="[
                  checked ? 'bg-indigo-600 text-white' : 'text-gray-500',
                  'cursor-pointer rounded-full px-2.5 py-1',
                ]">
                {{ option.label }}
              </div>
            </RadioGroupOption>
          </RadioGroup>
        </fieldset>
      </div>
      <div class="isolate mx-auto mt-10 grid max-w-md grid-cols-1 gap-8 lg:mx-0 lg:max-w-none lg:grid-cols-3">
        <div
          v-for="tier in tiers"
          :key="tier.id"
          :class="[tier.featured ? 'bg-gray-900 ring-gray-900' : 'ring-gray-200', 'rounded-3xl p-8 ring-1 xl:p-10']">
          <h3
            :id="tier.id"
            :class="[tier.featured ? 'text-white' : 'text-gray-900', 'text-lg/8 font-semibold']">
            {{ tier.name }}
          </h3>
          <p :class="[tier.featured ? 'text-gray-300' : 'text-gray-600', 'mt-4 text-sm/6']">{{ tier.description }}</p>
          <p class="mt-6 flex items-baseline gap-x-1">
            <span :class="[tier.featured ? 'text-white' : 'text-gray-900', 'text-4xl font-semibold tracking-tight']">
              {{ typeof tier.price === 'string' ? tier.price : tier.price[frequency.value] }}
            </span>
            <span
              v-if="typeof tier.price !== 'string'"
              :class="[tier.featured ? 'text-gray-300' : 'text-gray-600', 'text-sm/6 font-semibold']">
              {{ frequency.priceSuffix }}
            </span>
          </p>
          <a
            :href="tier.href"
            :aria-describedby="tier.id"
            :class="[
              tier.featured
                ? 'bg-white/10 text-white hover:bg-white/20 focus-visible:outline-white'
                : 'bg-indigo-600 text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-indigo-600',
              'mt-6 block rounded-md px-3 py-2 text-center text-sm/6 font-semibold focus-visible:outline-2 focus-visible:outline-offset-2',
            ]">
            {{ tier.cta }}
          </a>
          <ul
            role="list"
            :class="[tier.featured ? 'text-gray-300' : 'text-gray-600', 'mt-8 space-y-3 text-sm/6 xl:mt-10']">
            <li
              v-for="feature in tier.features"
              :key="feature"
              class="flex gap-x-3">
              <OIcon
                collection="heroicons"
                name="check-16-solid"
                :class="[tier.featured ? 'text-white' : 'text-indigo-600', 'h-6 w-5 flex-none']"
                aria-hidden="true" />
              {{ feature }}
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>
