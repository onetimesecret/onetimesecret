<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import MovingGlobules from '@/components/MovingGlobules.vue';
  import QuoteSection from '@/components/QuoteSection.vue';
  import { RadioGroup, RadioGroupOption } from '@headlessui/vue';
  import { testimonials as testimonialsData } from '@/sources/testimonials';
  import { paymentFrequencies, productTiers } from '@/sources/productTiers';
  import { onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const frequencies = ref(paymentFrequencies);
  const frequency = ref(frequencies.value[0]);

  // Get Identity Plus tier
  const identityTier = productTiers.find((tier) => tier.id === 'tier-identity');

  // Validate tier exists
  if (!identityTier) {
    throw new Error(t('identity-tier-not-found-in-product-tiers'));
  }

  const testimonials = ref(testimonialsData);
  const randomTestimonial = ref(testimonials.value[0]);

  onMounted(() => {
    const randomIndex = Math.floor(Math.random() * testimonials.value.length);
    randomTestimonial.value = testimonials.value[randomIndex];
  });
</script>

<template>
  <div class="relative isolate bg-white px-6 py-24 dark:bg-gray-900 sm:py-32 lg:px-8">
    <!-- Existing MovingGlobules -->
    <MovingGlobules
      from-colour="#23b5dd"
      to-colour="#dc4a22"
      speed="10s"
      :interval="3000"
      :scale="1" />

    <div class="mx-auto max-w-7xl px-6 lg:px-8">
      <div class="mx-auto max-w-4xl sm:text-center">
        <h2 class="text-5xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-6xl">
          {{ $t('secure-links-stronger-connections') }}
        </h2>
        <p class="mx-auto mt-6 max-w-2xl text-lg text-gray-600 dark:text-gray-300 sm:text-xl/8">
          {{ $t('secure-your-brand-and-build-customer-trust-with-') }}
        </p>
      </div>

      <!-- Pricing Toggle -->
      <div class="mt-16 flex justify-center font-serif">
        <fieldset :aria-label="$t('payment-frequency')">
          <RadioGroup
            v-model="frequency"
            class="grid grid-cols-2 gap-x-1 rounded-full bg-white/5 p-1 text-center text-xs font-semibold leading-5 text-white">
            <RadioGroupOption
              as="template"
              v-for="option in frequencies"
              :key="option.value"
              :value="option"
              v-slot="{ checked }">
              <div
                :class="[
                  checked
                    ? 'bg-brand-600 dark:bg-brand-500'
                    : 'bg-white text-gray-900 opacity-55 dark:bg-gray-700 dark:text-gray-200',
                  'cursor-pointer rounded-full px-2.5 py-1',
                ]">
                {{ option.label }}
              </div>
            </RadioGroupOption>
          </RadioGroup>
        </fieldset>
      </div>

      <!-- Identity Plus Card -->
      <div
        class="mx-auto mt-16 max-w-2xl rounded-3xl bg-white dark:bg-gray-800 ring-1 ring-gray-200 dark:ring-gray-700 sm:mt-20 lg:mx-0 lg:flex lg:max-w-none">
        <div class="p-8 sm:p-10 lg:flex-auto">
          <h3 class="text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">{{
            $t('identity-plus')
          }}</h3>
          <p class="mt-6 text-base leading-7 text-gray-600 dark:text-gray-300">
            {{ $t('elevate-your-secure-sharing-with-custom-domains-') }}
          </p>

          <div class="mt-10 flex items-center gap-x-4">
            <h4 class="flex-none text-sm font-semibold text-brand-600 dark:text-brand-400">{{
              $t('features')
            }}</h4>
            <div class="h-px flex-auto bg-gray-100 dark:bg-gray-700"></div>
          </div>

          <ul
            role="list"
            class="mt-8 grid grid-cols-1 gap-4 text-sm text-gray-600 dark:text-gray-300 sm:grid-cols-2">
            <li
              v-for="feature in identityTier.features"
              :key="feature"
              class="flex gap-x-3">
              <OIcon
                collection="heroicons"
                name="check-16-solid"
                class="h-6 w-5 flex-none text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
              {{ feature }}
            </li>
          </ul>
        </div>

        <div class="-mt-2 p-2 lg:mt-0 lg:w-full lg:max-w-md lg:flex-shrink-0">
          <div
            class="rounded-2xl bg-gray-50 py-10 text-center ring-1 ring-inset ring-gray-900/5 dark:bg-gray-800 dark:ring-gray-700 lg:flex lg:flex-col lg:justify-center lg:py-16">
            <div class="mx-auto max-w-xs px-8">
              <p class="text-base font-semibold text-gray-600 dark:text-gray-300">
                {{
                  $t('frequency-value-annually-annual-monthly-subscrip', [
                    frequency.value === 'annually' ? 'Annual' : 'Monthly',
                  ])
                }}
              </p>
              <p class="mt-6 flex items-baseline justify-center gap-x-2">
                <span class="text-5xl font-bold tracking-tight text-gray-900 dark:text-white">
                  {{ identityTier?.price[frequency.value] }}
                </span>
                <span class="text-sm font-semibold text-gray-600 dark:text-gray-400">
                  {{ frequency.priceSuffix }}
                </span>
              </p>
              <a
                :href="`/plans/identity${frequency.priceSuffix}`"
                class="mt-10 block w-full rounded-md bg-brand-600 px-4 py-3 text-center text-base font-semibold text-white shadow-lg hover:bg-brand-500 hover:shadow-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 light:bg-brand-500 light:hover:bg-brand-400">
                {{ $t('get-started') }}
              </a>
              <p class="mt-6 text-xs text-gray-600 dark:text-gray-400">
                {{ $t('includes-all-features-and-unlimited-sharing-capa') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Quotes -->
    <div class="relative">
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
