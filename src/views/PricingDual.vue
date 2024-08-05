<template>
  <div class="relative isolate bg-white dark:bg-gray-900 px-6 py-18 sm:py-12 lg:px-8">
    <div class="pb-6 flex justify-center text-sm">

    </div>


    <MovingGlobules from-colour="#23b5dd"
                    to-colour="#dc4a22"
                    speed="10s"
                    :interval="3000" />

    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="mx-auto text-center max-w-2xl lg:max-w-4xl">
        <h2 class="text-base font-semibold leading-7 text-brand-600 dark:text-brand-400 sm:text-lg md:text-xl">Pricing
        </h2>
        <p
           class="mt-2 text-3xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-4xl md:text-5xl lg:text-6xl">
          Secure Links, Stronger Connections
        </p>
        <p
           class="mx-auto mt-6 max-w-md lg:max-w-xl text-center text-base sm:text-lg md:text-xl leading-7 sm:leading-8 text-gray-600 dark:text-gray-300">
          Share confidential information with confidence, elevate your brand, and build trust
        </p>
      </div>

    </div>
    <div class="mt-16 flex justify-center">
      <fieldset aria-label="Payment frequency">
        <RadioGroup v-model="frequency"
                    class="grid grid-cols-2 gap-x-1 rounded-full bg-white/5 p-1 text-center text-xs font-semibold leading-5 text-white">
          <RadioGroupOption as="template"
                            v-for="option in frequencies"
                            :key="option.value"
                            :value="option"
                            v-slot="{ checked }">
            <div
                 :class="[checked ? 'bg-brand-600 dark:bg-brand-500' : 'bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-200 opacity-55', 'cursor-pointer rounded-full px-2.5 py-1']">
              {{ option.label }}
            </div>
          </RadioGroupOption>
        </RadioGroup>
      </fieldset>
    </div>

    <!-- Plans -->
    <div
         class="mx-auto mt-16 grid max-w-lg grid-cols-1 items-center gap-y-6 sm:mt-20 sm:gap-y-0 lg:max-w-4xl lg:grid-cols-2">
      <div v-for="(tier, tierIdx) in tiers"
           :key="tier.id"
           :class="[tier.featured ? 'relative bg-slate-800 dark:bg-slate-700 shadow-2xl' : 'bg-white/60 dark:bg-gray-800/60 sm:mx-8 lg:mx-0', tier.featured ? '' : tierIdx === 0 ? 'rounded-t-3xl sm:rounded-b-none lg:rounded-bl-3xl lg:rounded-tr-none' : 'sm:rounded-t-none lg:rounded-bl-none lg:rounded-tr-3xl', 'rounded-3xl p-8 ring-1 ring-gray-900/10 dark:ring-gray-100/10 sm:p-10']">
        <h3 :id="tier.id"
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
        <ul role="list"
            :class="[tier.featured ? 'text-gray-300 pb-10' : 'text-gray-600 dark:text-gray-300', 'mt-8 space-y-3 text-base leading-6 sm:mt-10']">
          <li v-for="feature in tier.features"
              :key="feature"
              class="flex gap-x-3">
            <Icon icon="heroicons-solid:check"
                  :class="[tier.featured ? 'text-brand-400' : 'text-brand-600 dark:text-brand-400', 'h-6 w-5 flex-none']"
                  aria-hidden="true" />
            {{ feature }}
          </li>
        </ul>
        <form :action="tier.href" method="POST">
          <input type="hidden" name="shrimp" :value="shrimp" />
                    <button type="submit"
                  :aria-describedby="tier.id"
                  v-on="tier.featured ? { click: ($event: MouseEvent) => $event.preventDefault() } : {}"
                  :class="[tier.featured ? 'block text-brand-400 dark:text-brand-400 ring-2 ring-inset bg-gray-800 dark:ring-slate-800 hover:ring-gray-300 dark:hover:ring-gray-800 focus-visible:outline-gray-600' : 'block bg-brand-500 text-white shadow-sm hover:bg-brand-600 focus-visible:outline-brand-500', 'mt-8 block rounded-md px-3.5 py-2.5 text-center text-lg font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 sm:mt-10']">
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
    <div class="py-8 mx-auto mt-4 grid max-w-4xl justify-center grid-cols-1">

      <div class="relative mx-auto mt-4 max-w-7xl px-4 sm:px-6 lg:mt-5 lg:px-8">
        <div class="mx-auto max-w-md lg:max-w-5xl">
          <div
               class="rounded-lg bg-brandcompdim-50 dark:bg-gray-800 px-6 py-8 sm:p-10 lg:flex lg:items-center border-2 border-dotted hover:border-brandcompdim-300 dark:hover:border-brandcompdim-600">
            <div class="flex-1">
              <div>
                <h3
                    class="inline-flex rounded-full bg-brandcompdim-200 dark:bg-brandcompdim-700 px-4 py-1 text-base font-semibold text-gray-800 dark:text-gray-200">
                  Self-Hosted
                </h3>
              </div>
              <div class="mt-4 text-lg text-gray-600 dark:text-gray-300">
                Get full access to all features for the honest and wholesome price of <span
                      class="italic font-semibold text-gray-900 dark:text-gray-100">$0 dollars</span> with self-hosting.
                We even include our SimpleStack℠ guarantee at no extra charge.

                <InfoTooltip color="bg-brandcomp-100 dark:bg-brandcomp-900">
                  <div class="float-left mr-4 mb-2 shape-icon">
                    <Icon icon="fa6-solid:handshake-simple"
                          class="w-24 h-24 text-brandcomp-600 dark:text-brandcomp-400" />
                  </div>
                  <h3 class="font-bold mb-2 text-gray-900 dark:text-white">Our SimpleStack℠ Guarantee</h3>
                  <p class="prose dark:prose-invert">Our SimpleStack guarantee ensures effortless deployment and
                    management of our
                    software. You can have the entire system up and running in minutes, from a single docker container.
                  </p>
                  <p class="prose dark:prose-invert">Whether you're a seasoned DevOps pro or new to self-hosting, our
                    SimpleStack design
                    ensures you can focus on using the product, not wrestling with infrastructure. That's the
                    SimpleStack advantage!</p>
                  <p class="prose mt-4 font-semibold dark:prose-invert">
                    While others are stacking up complications, we've got your back with a stack so simple, it just
                    works.
                  </p>
                </InfoTooltip>
              </div>
            </div>
            <div class="mt-6 rounded-md shadow lg:ml-10 lg:mt-0 lg:flex-shrink-0">
              <a href="https://github.com/onetimesecret/onetimesecret"
                 class="block items-center justify-center rounded-md border border-transparent bg-brandcompdim-300 dark:bg-brandcompdim-700 px-5 py-3 text-base font-medium text-gray-900 dark:text-gray-100 hover:bg-brandcompdim-200 dark:hover:bg-brandcompdim-600">
                Get Started
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>


<script setup lang="ts">
import InfoTooltip from '@/components/InfoTooltip.vue';
import MovingGlobules from '@/components/MovingGlobules.vue';
import QuoteSection from '@/components/QuoteSection.vue';
import { paymentFrequencies, productTiers } from '@/sources/productTiers';
import { testimonials as testimonialsData } from '@/sources/testimonials';
import { RadioGroup, RadioGroupOption } from '@headlessui/vue';
import { Icon } from '@iconify/vue';
import { onMounted, ref } from 'vue';

const testimonials = ref(testimonialsData);
const randomTestimonial = ref(testimonials.value[0]);

const tiers = ref(productTiers);
const frequencies = ref(paymentFrequencies);
const frequency = ref(frequencies.value[0]);

const shrimp = ref(window.shrimp);

onMounted(() => {
  const randomIndex = Math.floor(Math.random() * testimonials.value.length);
  randomTestimonial.value = testimonials.value[randomIndex];
});
</script>

<style scoped>
.gradient-text {
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
}
</style>
