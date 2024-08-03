<template>
  <div class="isolate overflow-hidden bg-gray-900">
    <div class="mx-auto max-w-7xl px-6 pb-96 pt-24 text-center sm:pt-32 lg:px-8">
      <div class="mx-auto max-w-4xl">
        <h2 class="text-base font-semibold leading-7 text-indigo-400">Pricing</h2>
        <p class="mt-2 text-4xl font-brand font-bold tracking-tight text-white sm:text-5xl">The right price for you, <br class="hidden sm:inline lg:hidden" />whoever you are</p>
      </div>
      <div class="mt-16 flex justify-center">
        <fieldset aria-label="Payment frequency">
          <RadioGroup v-model="frequency" class="grid grid-cols-2 gap-x-1 rounded-full p-1 text-center text-xs font-semibold leading-5 ring-1 ring-inset ring-gray-200">
            <RadioGroupOption as="template" v-for="option in frequencies" :key="option.value" :value="option" v-slot="{ checked }">
              <div :class="[checked ? 'bg-indigo-600 text-white' : 'text-gray-500', 'cursor-pointer rounded-full px-2.5 py-1']">{{ option.label }}</div>
            </RadioGroupOption>
          </RadioGroup>
        </fieldset>
      </div>
      <div class="relative mt-6">
        <p class="mx-auto max-w-2xl text-lg leading-8 text-white/60">Lorem ipsum dolor sit, amet consectetur adipisicing elit. Velit numquam eligendi quos odit doloribus molestiae voluptatum.</p>
        <svg viewBox="0 0 1208 1024" class="absolute -top-10 left-1/2 -z-10 h-[64rem] -translate-x-1/2 [mask-image:radial-gradient(closest-side,white,transparent)] sm:-top-12 md:-top-20 lg:-top-12 xl:top-0">
          <ellipse cx="604" cy="512" fill="url(#6d1bd035-0dd1-437e-93fa-59d316231eb0)" rx="604" ry="512" />
          <defs>
            <radialGradient id="6d1bd035-0dd1-437e-93fa-59d316231eb0">
              <stop stop-color="#7775D6" />
              <stop offset="1" stop-color="#E935C1" />
            </radialGradient>
          </defs>
        </svg>
      </div>
    </div>
    <div class="flow-root bg-white pb-24 sm:pb-32">
      <div class="-mt-80">
        <div class="mx-auto max-w-7xl px-6 lg:px-8">
          <div class="mx-auto grid max-w-md grid-cols-1 gap-8 lg:max-w-4xl lg:grid-cols-2">
            <div v-for="tier in tiers" :key="tier.id" class="flex flex-col justify-between rounded-3xl bg-white p-8 shadow-xl ring-1 ring-gray-900/10 sm:p-10">
              <div>
                <h3 :id="tier.id" class="text-base font-semibold leading-7 text-indigo-600">{{ tier.name }}</h3>
                <div class="mt-4 flex items-baseline gap-x-2">
                  <span class="text-5xl font-brand font-bold tracking-tight text-gray-900">{{ tier.priceMonthly }}</span>
                  <span class="text-base font-brand font-semibold leading-7 text-gray-600">/month</span>
                </div>
                <p class="mt-6 text-base leading-7 text-gray-600">{{ tier.description }}</p>
                <ul role="list" class="mt-10 space-y-4 text-md leading-6 text-gray-600">
                  <li v-for="feature in tier.features" :key="feature" class="flex gap-x-3">
                    <Icon icon="heroicons-solid:check" class="h-6 w-5 flex-none text-indigo-600" aria-hidden="true" />
                    {{ feature }}
                  </li>
                </ul>
              </div>
              <a :href="tier.href" :aria-describedby="tier.id" class="mt-8 block rounded-md bg-indigo-600 px-3.5 py-2 text-center text-sm font-semibold leading-6 text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">Get started today</a>
            </div>
            <div class="flex flex-col items-start gap-x-8 gap-y-6 rounded-3xl p-8 ring-1 ring-gray-900/10 sm:gap-y-10 sm:p-10 lg:col-span-2 lg:flex-row lg:items-center">
              <div class="lg:min-w-0 lg:flex-1">
                <h3 class="text-lg font-semibold leading-8 tracking-tight text-indigo-600">Discounted</h3>
                <p class="mt-1 text-base leading-7 text-gray-600">Dolor dolores repudiandae doloribus. Rerum sunt aut eum. Odit omnis non voluptatem sunt eos nostrum.</p>
              </div>
              <a href="#" class="rounded-md px-3.5 py-2 text-sm font-semibold leading-6 text-indigo-600 ring-1 ring-inset ring-indigo-200 hover:ring-indigo-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">Buy discounted license <span aria-hidden="true">&rarr;</span></a>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { RadioGroup, RadioGroupOption } from '@headlessui/vue'
import { Icon } from '@iconify/vue';

const tiers = [
  {
    name: 'Hobby',
    id: 'tier-hobby',
    href: '#',
    priceMonthly: '$15',
    description: 'Modi dolorem expedita deleniti. Corporis iste qui inventore pariatur adipisci vitae.',
    features: [
      '5 products', 'Up to 1,000 subscribers', 'Basic analytics', '48-hour support response time'
    ],
  },
  {
    name: 'Team',
    id: 'tier-team',
    href: '#',
    priceMonthly: '$75',
    description: 'Explicabo quo fugit vel facere ullam corrupti non dolores. Expedita eius sit sequi.',
    features: [
      'Unlimited products',
      'Unlimited subscribers',
      'Advanced analytics',
      '1-hour, dedicated support response time',
      'Marketing automations',
    ],
  },
]

const frequencies = [
  { value: 'monthly', label: 'Monthly', priceSuffix: '/month' },
  { value: 'annually', label: 'Annually', priceSuffix: '/year' },
]
const frequency = ref(frequencies[0])

</script>
