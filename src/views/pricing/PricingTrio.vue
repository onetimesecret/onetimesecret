<script setup lang="ts">
  import { ref, onMounted } from 'vue';
  import { RadioGroup, RadioGroupOption } from '@headlessui/vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import MovingGlobules from '@/components/MovingGlobules.vue';
  import QuoteSection from '@/components/QuoteSection.vue';
  import type { PaymentFrequency } from '@/sources/productTiers';
  import { paymentFrequencies as frequencies, productTiers as tiers } from '@/sources/productTiers';
  import { testimonials as testimonialsData } from '@/sources/testimonials';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const frequency = ref<PaymentFrequency>(frequencies[0]);

  const testimonials = ref(testimonialsData);
  const randomTestimonial = ref(testimonials.value[0]);

  onMounted(() => {
    const randomIndex = Math.floor(Math.random() * testimonials.value.length);
    randomTestimonial.value = testimonials.value[randomIndex];
  });
</script>

<template>
  <div class="relative isolate dark:bg-gray-900 py-24 sm:py-32">
    <!-- Background Globules -->
    <MovingGlobules
      from-colour="#23b5dd"
      to-colour="#dc4a22"
      speed="10s"
      :interval="3000"
      :scale="1" />

    <div class="mx-auto max-w-7xl px-6 lg:px-8 relative z-10">
      <!-- Header section unchanged -->
      <div class="mx-auto max-w-4xl text-center">
        <h2 class="text-base/7 font-semibold text-brand-600 dark:text-brand-400">{{
          t('pricing')
        }}</h2>
        <p class="mt-2 text-5xl font-bold font-brand tracking-tight text-gray-900 dark:text-white">
          {{ t('secure-links-stronger-connections') }}
        </p>
      </div>
      <p
        class="mx-auto mt-6 max-w-2xl text-center text-lg font-medium text-pretty text-gray-600 dark:text-gray-300 sm:text-xl/8">
        {{ t('secure-your-brand-and-build-customer-trust-with-') }}
      </p>

      <!-- Payment Frequency Toggle unchanged -->
      <div class="mt-16 flex justify-center">
        <fieldset :aria-label="t('payment-frequency')">
          <RadioGroup
            v-model="frequency"
            class="grid grid-cols-2 gap-x-1 rounded-full p-1 text-center text-xs/5 font-semibold ring-1 ring-gray-200 dark:ring-gray-700 ring-inset">
            <RadioGroupOption
              as="template"
              v-for="option in frequencies"
              :key="option.value"
              :value="option"
              v-slot="{ checked }">
              <div
                :class="[
                  checked ? 'bg-brand-600 text-white' : 'text-gray-500 dark:text-gray-400',
                  'cursor-pointer rounded-full px-2.5 py-1',
                ]">
                {{ option.label }}
              </div>
            </RadioGroupOption>
          </RadioGroup>
        </fieldset>
      </div>

      <!-- Updated Pricing Tiers -->
      <div
        class="isolate mx-auto mt-10 grid max-w-md grid-cols-1 gap-8 lg:mx-0 lg:max-w-none lg:grid-cols-3">
        <!-- Pricing tier card dynamic classes -->
        <div
          v-for="tier in tiers"
          :key="tier.id"
          :class="[
            tier.featured
              ? 'bg-brandcomp-100/80 dark:bg-brand-950 ring-brandcomp-900 dark:ring-brand-500 shadow-xl border border-brandcomp-700/30 dark:border-brand-400/30'
              : 'ring-gray-200 dark:ring-gray-700 bg-white dark:bg-gray-900',
            'rounded-3xl p-8 ring-1 xl:p-10 transition-transform duration-200 hover:scale-105',
          ]">
          <!-- Name -->
          <h3
            :id="tier.id"
            :class="[
              tier.featured ? 'text-gray-900 dark:text-white' : 'text-gray-800 dark:text-white',
              'text-2xl font-semibold',
            ]">
            {{ tier.name }}
          </h3>
          <!-- Description -->
          <p
            :class="[
              tier.featured
                ? 'text-brandcomp-900 dark:text-brand-100'
                : 'text-gray-600 dark:text-gray-300',
              'mt-4 text-sm/6',
            ]"
            >{{ tier.description }}</p
          >
          <!-- Price -->
          <p class="mt-6 flex items-baseline gap-x-1">
            <span
              :class="[
                tier.featured
                  ? 'text-brandcomp-900 dark:text-white'
                  : 'text-gray-900 dark:text-white',
                'text-4xl font-semibold tracking-tight',
              ]">
              {{ typeof tier.price === 'string' ? tier.price : tier.price[frequency.value] }}
            </span>
            <span
              v-if="typeof tier.price !== 'string'"
              :class="[
                tier.featured
                  ? 'text-brandcomp-900 dark:text-brand-100'
                  : 'text-gray-600 dark:text-gray-300',
                'text-sm/6 font-semibold',
              ]">
              {{ frequency.priceSuffix }}
            </span>
          </p>
          <!-- CTA Button -->
          <a
            :href="`${tier.href}${frequency.priceSuffix}`"
            :aria-describedby="tier.id"
            :class="[
              tier.featured
                ? 'bg-brandcomp-800 text-white hover:bg-brandcomp-900 focus-visible:outline-brandcomp-400'
                : 'bg-brand-600 text-white shadow-sm hover:bg-brand-500 focus-visible:outline-brand-600',
              'mt-6 block rounded-md px-3 py-2 text-center text-lg font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 transition-colors',
            ]">
            {{ tier.cta }}
          </a>
          <!-- Features -->
          <ul
            role="list"
            :class="[
              tier.featured
                ? 'text-brandcomp-900 dark:text-brand-100'
                : 'text-gray-600 dark:text-gray-300',
              'mt-8 space-y-3 text-sm/6 xl:mt-10',
            ]">
            <li
              v-for="feature in tier.features"
              :key="feature"
              class="flex gap-x-3">
              <OIcon
                collection="heroicons"
                name="check-16-solid"
                :class="[
                  tier.featured
                    ? 'text-brandcomp-600 dark:text-white'
                    : 'text-brand-600 dark:text-brand-400',
                  'h-6 w-5 flex-none',
                ]"
                aria-hidden="true" />
              {{ feature }}
            </li>
          </ul>
        </div>
      </div>

      <!-- Additional content unchanged -->
      <p class="mt-10 text-center text-sm text-gray-600 dark:text-gray-400">
        {{ t('includes-all-data-locality-options') }}
      </p>
    </div>

    <!-- Testimonial Section unchanged -->
    <div class="relative mt-24">
      <QuoteSection
        class="relative z-10 bg-opacity-80 dark:bg-opacity-80"
        :testimonial="randomTestimonial" />

      <MovingGlobules
        class="absolute inset-0 z-0 opacity-50"
        from-colour="#23b5dd"
        to-colour="#dc4a22"
        speed="10s"
        :interval="1000"
        :scale="2" />
    </div>
  </div>
</template>
