<script setup lang="ts">
import InfoTooltip from '@/components/InfoTooltip.vue';
import MovingGlobules from '@/components/MovingGlobules.vue';
import QuoteSection from '@/components/QuoteSection.vue';
import { paymentFrequencies, productTiers } from '@/sources/productTiers';
import { testimonials as testimonialsData } from '@/sources/testimonials';
import { RadioGroup, RadioGroupOption } from '@headlessui/vue';
import OIcon from '@/components/icons/OIcon.vue';
import { onMounted, ref } from 'vue';

const testimonials = ref(testimonialsData);
const randomTestimonial = ref(testimonials.value[0]);

const tiers = ref(productTiers);
const frequencies = ref(paymentFrequencies);
const frequency = ref(frequencies.value[0]);

onMounted(() => {
  const randomIndex = Math.floor(Math.random() * testimonials.value.length);
  randomTestimonial.value = testimonials.value[randomIndex];
});

</script>


<template>
  <div class="py-18 relative isolate bg-white px-6 dark:bg-gray-900 sm:py-12 lg:px-8">
    <div class="flex justify-center pb-6 text-sm">
    </div>

    <MovingGlobules
      from-colour="#23b5dd"
      to-colour="#dc4a22"
      speed="10s"
      :interval="3000"
      :scale="1"
    />

    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl text-center lg:max-w-4xl">
        <h2 class="text-base font-semibold leading-7 text-brand-600 dark:text-brand-400 sm:text-lg md:text-xl">
          Pricing
        </h2>
        <p
          class="mt-2 font-brand text-4xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-5xl md:text-6xl lg:text-7xl">
          Secure Links, Stronger Connections
        </p>
        <p
          class="mx-auto mt-6 max-w-md text-center text-base leading-7 text-gray-600 dark:text-gray-300 sm:text-lg sm:leading-8 md:text-xl lg:max-w-xl">
          Share confidential information with confidence, elevate your brand, and build trust
        </p>
      </div>
    </div>
    <div class="mt-16 flex justify-center font-serif">
      <fieldset aria-label="Payment frequency">
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
              :class="[checked ? 'bg-brand-600 dark:bg-brand-500' : 'bg-white text-gray-900 opacity-55 dark:bg-gray-700 dark:text-gray-200', 'cursor-pointer rounded-full px-2.5 py-1']">
              {{ option.label }}
            </div>
          </RadioGroupOption>
        </RadioGroup>
      </fieldset>
    </div>

    <!-- Plans -->
    <div
      class="mx-auto mt-16 grid max-w-lg grid-cols-1 items-center gap-y-6 sm:mt-20 sm:gap-y-0 lg:max-w-4xl lg:grid-cols-2">
      <div
        v-for="(tier, tierIdx) in tiers"
        :key="tier.id"
        :class="[tier.featured ? 'relative bg-slate-800 shadow-2xl dark:bg-slate-700' : 'bg-white/60 dark:bg-gray-800/60 sm:mx-8 lg:mx-0', tier.featured ? '' : tierIdx === 0 ? 'rounded-t-3xl sm:rounded-b-none lg:rounded-bl-3xl lg:rounded-tr-none' : 'sm:rounded-t-none lg:rounded-bl-none lg:rounded-tr-3xl', 'rounded-3xl p-8 ring-1 ring-gray-900/10 dark:ring-gray-100/10 sm:p-10']">
        <h3
          :id="tier.id"
          :class="[tier.featured ? 'text-brand-500' : 'text-brand-500', 'text-xl font-semibold leading-7']">
          {{ tier.name }}
        </h3>
        <p class="mt-4 flex items-baseline gap-x-2">
          <span
            :class="[tier.featured ? 'text-white blur-lg' : 'text-gray-900 dark:text-white', 'text-5xl font-bold tracking-tight']">{{ tier.price[frequency.value] }}</span>
          <span
            :class="[tier.featured ? 'text-gray-400' : 'text-gray-500 dark:text-gray-400', 'text-base']">{{ frequency.priceSuffix }}</span>
        </p>
        <p :class="[tier.featured ? 'text-gray-300' : 'text-gray-600 dark:text-gray-300', 'mt-6 text-base leading-7']">
          {{ tier.description }}
        </p>
        <ul
          role="list"
          :class="[tier.featured ? 'pb-10 text-gray-300' : 'text-gray-600 dark:text-gray-300', 'mt-8 space-y-3 text-base leading-6 sm:mt-10']">
          <li
            v-for="feature in tier.features"
            :key="feature"
            class="flex gap-x-3">
            <OIcon
              collection="heroicons"
              name="check-16-solid"
              :class="[tier.featured ? 'text-brand-400' : 'text-brand-600 dark:text-brand-400', 'h-6 w-5 flex-none']"
              aria-hidden="true"
            />
            {{ feature }}
          </li>
        </ul>
        <form
          :action="`${tier.href}${frequency.priceSuffix}`"
          method="GET">
          <button
            type="submit"
            :aria-describedby="tier.id"
            v-on="tier.featured ? { click: ($event: MouseEvent) => $event.preventDefault() } : {}"
            :class="[tier.featured ? 'block bg-gray-800 text-brand-400 ring-2 ring-inset hover:ring-gray-300 focus-visible:outline-gray-600 dark:text-brand-400 dark:ring-slate-800 dark:hover:ring-gray-800' : 'block bg-brand-500 text-white shadow-sm hover:bg-brand-600 focus-visible:outline-brand-500', 'mt-8 block rounded-md px-3.5 py-2.5 text-center text-lg font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 sm:mt-10']">
            {{ tier.cta }}
          </button>
        </form>
      </div>
    </div>

    <!-- Quotes -->
    <div class="relative">
      <QuoteSection
        class="relative z-10 bg-opacity-80 dark:bg-opacity-80"
        :testimonial="randomTestimonial"
      />

      <MovingGlobules
        class="absolute inset-0 z-0"
        from-colour="#23b5dd"
        to-colour="#dc4a22"
        speed="10s"
        :interval="1000"
        :scale="2"
      />
    </div>

    <!-- Alternative option -->
    <div class="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
      <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
        <div class="px-6 py-8 sm:p-10 lg:flex lg:items-center lg:justify-between">
          <div class="flex-1 space-y-6">
            <h3
              class="inline-flex items-center rounded-full bg-brandcomp-100 px-4 py-1 text-sm font-semibold text-brandcomp-700 dark:bg-brandcomp-900 dark:text-brandcomp-300">
              <svg
                class="mr-2 size-5"
                fill="currentColor"
                viewBox="0 0 20 20"
                xmlns="http://www.w3.org/2000/svg">
                <path
                  fill-rule="evenodd"
                  d="M5 2a1 1 0 011 1v1h1a1 1 0 010 2H6v1a1 1 0 01-2 0V6H3a1 1 0 010-2h1V3a1 1 0 011-1zm0 10a1 1 0 011 1v1h1a1 1 0 110 2H6v1a1 1 0 11-2 0v-1H3a1 1 0 110-2h1v-1a1 1 0 011-1zm7-10a1 1 0 01.707.293l3 3a1 1 0 010 1.414l-3 3a1 1 0 01-1.414-1.414L13.586 8l-2.293-2.293a1 1 0 011.414-1.414l3 3z"
                  clip-rule="evenodd"
                />
              </svg>
              An Unlimited-Time Offer
            </h3>
            <ul class="space-y-4 text-base text-gray-600 dark:text-gray-300">
              <li class="flex items-center">
                <svg
                  class="mr-3 size-6 text-brandcomp-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
                <span><strong class="font-medium">Start Free:</strong> Unlock most features at $0/month</span>
              </li>
              <li class="flex items-center">
                <svg
                  class="mr-3 size-6 text-brandcomp-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
                  />
                </svg>
                <span><strong class="font-medium">Self-Host:</strong> Get our SimpleStack℠ guarantee included</span>
                <InfoTooltip color="bg-brandcomp-100 dark:bg-brandcomp-900">
                  <div class="shape-icon float-left mb-2 mr-4">
                    <OIcon
                      collection="fa6-solid"
                      name="handshake-simple"
                      class="size-24 text-brandcomp-600 dark:text-brandcomp-400"
                    />
                  </div>
                  <h3 class="mb-2 font-bold text-gray-900 dark:text-white">
                    Our SimpleStack℠ Guarantee
                  </h3>
                  <p class="prose dark:prose-invert">
                    Our SimpleStack guarantee ensures effortless deployment and
                    management of our software. You can have the entire system up and running in minutes, from a single
                    docker container.
                  </p>
                  <p class="prose dark:prose-invert">
                    Whether you're a seasoned DevOps pro or new to self-hosting, our
                    SimpleStack design ensures you can focus on using the product, not wrestling with infrastructure.
                    That's the
                    SimpleStack advantage!
                  </p>
                  <p class="prose mt-4 font-semibold dark:prose-invert">
                    While others are stacking up complications, we've got your back with a stack so simple, it just
                    works.
                  </p>
                </InfoTooltip>
              </li>
            </ul>
            <p class="text-base text-gray-600 dark:text-gray-300">
              Why wait? Join thousands of happy users today!
            </p>
          </div>
          <div class="mt-8 flex flex-col space-y-4 lg:ml-10 lg:mt-0">
            <router-link
              to="/signup/basic"
              class="inline-flex items-center justify-center rounded-md border border-transparent bg-brandcomp-500 px-5 py-3 font-brand text-base font-medium text-white transition-colors duration-200 hover:bg-brandcomp-600 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2">
              Get Started for Free
            </router-link>
            <a
              href="https://github.com/onetimesecret/onetimesecret"
              ref="noopener noreferrer"
              class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-5 py-3 font-brand text-base font-medium text-gray-700 transition-colors duration-200 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600">
              Learn About Self-Hosting
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.gradient-text {
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
}
</style>
