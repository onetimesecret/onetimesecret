<template>
  <div class="relative isolate bg-white px-6 py-18 sm:py-12 lg:px-8">
    <div class="pb-12 flex justify-center text-sm ">

      <!--<ButtonGroup first-val="Human Content"
                   mid-val1=""
                   last-val="Machine Generated" />-->

    </div>
    <div class="absolute inset-x-0 -top-3 -z-10 transform-gpu overflow-hidden px-36 blur-3xl"
         aria-hidden="true">
      <MovingGlobules from-colour="#23b5dd"
                      to-colour="#dc4a22"
                      speed="6s" />
    </div>
    <div class="mx-auto max-w-2xl text-center lg:max-w-4xl">
      <h2 class="text-2xl font-semibold leading-7 text-brand-600">Pricing</h2>
      <p class="mt-2 text-4xl font-bold tracking-tight text-gray-900 sm:text-5xl">

        Secure Links, Stronger Connections
      </p>
    </div>
    <p class="mx-auto mt-6 max-w-2xl text-center text-xl leading-8 text-gray-600">
      Share confidential information with confidence, elevate your brand, and build trust
    </p>
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
                 :class="[checked ? 'bg-brand-600' : 'bg-white text-gray-900 opacity-55', 'cursor-pointer rounded-full px-2.5 py-1']">
              {{ option.label }}
            </div>
          </RadioGroupOption>
        </RadioGroup>
      </fieldset>
    </div>

    <!-- Plans -->
    <div
         class="mx-auto mt-16 grid max-w-lg grid-cols-1 items-center gap-y-6 sm:mt-20 sm:gap-y-0 lg:max-w-4xl lg:grid-cols-2 ">
      <div v-for="(tier, tierIdx) in tiers"
           :key="tier.id"
           :class="[tier.featured ? 'relative bg-slate-800 shadow-2xl' : 'bg-white/60 sm:mx-8 lg:mx-0', tier.featured ? '' : tierIdx === 0 ? 'rounded-t-3xl sm:rounded-b-none lg:rounded-bl-3xl lg:rounded-tr-none' : 'sm:rounded-t-none lg:rounded-bl-none lg:rounded-tr-3xl', 'rounded-3xl p-8 ring-1 ring-gray-900/10 sm:p-10']">
        <h3 :id="tier.id"
            :class="[tier.featured ? 'text-brand-500' : 'text-brand-500', 'text-xl font-semibold leading-7']">
          {{ tier.name }}
        </h3>
        <p class="mt-4 flex items-baseline gap-x-2">
          <span
                :class="[tier.featured ? 'text-white' : 'text-gray-900', 'text-5xl font-bold tracking-tight']">{{ tier.price[frequency.value] }}</span>
          <span
                :class="[tier.featured ? 'text-gray-400' : 'text-gray-500', 'text-base']">{{ frequency.priceSuffix }}</span>
        </p>
        <p :class="[tier.featured ? 'text-gray-300' : 'text-gray-600', 'mt-6 text-base leading-7']">
          {{ tier.description }}
        </p>
        <ul role="list"
            :class="[tier.featured ? 'text-gray-300' : 'text-gray-600', 'mt-8 space-y-3 text-base leading-6 sm:mt-10']">
          <li v-for="feature in tier.features"
              :key="feature"
              class="flex gap-x-3">
            <Icon icon="heroicons-solid:check"
                  :class="[tier.featured ? 'text-brand-400' : 'text-brand-600', 'h-6 w-5 flex-none']"
                  aria-hidden="true" />
            {{ feature }}
          </li>
        </ul>
        <a :href="tier.href"
           :aria-describedby="tier.id"
           :class="[tier.featured ? 'bg-brand-500 text-white shadow-sm hover:bg-brand-400 focus-visible:outline-brand-500' : 'text-brand-600 ring-1 ring-inset ring-brand-200 hover:ring-brand-300 focus-visible:outline-brand-600', 'mt-8 block rounded-md px-3.5 py-2.5 text-center text-lg font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 sm:mt-10']">
          Buy this plan</a>
      </div>
    </div>

    <!-- Quotes -->
    <p class="pt-8 mx-auto mt-12 max-w-2xl text-center text-lg leading-8 text-gray-600">
      "{{ randomTestimonial.quote }}" — <span class="font-brand">{{ randomTestimonial.name }}, <span
              class="italic">{{ randomTestimonial.company }}</span></span>
    </p>

    <!-- Self-Hosted -->
    <div class="py-8 mx-auto mt-4 grid max-w-4xl justify-center grid-cols-1">
      <div class="relative mx-auto mt-4 max-w-7xl px-4 sm:px-6 lg:mt-5 lg:px-8">
        <div class="mx-auto max-w-md lg:max-w-5xl">
          <div
               class="rounded-lg bg-brandcompdim-50 px-6 py-8 sm:p-10 lg:flex lg:items-center border-2 border-dotted hover:border-brandcompdim-300">
            <div class="flex-1">
              <div>
                <h3 class="inline-flex rounded-full bg-brandcompdim-200 px-4 py-1 text-base font-semibold text-gray-800">
                  Self-Hosted</h3>
              </div>
              <div class="mt-4 text-lg text-gray-600">
                Get full access to all features when self-hosting for the honest and wholesome price of <span class="italic font-semibold text-gray-900">$0 dollars</span>.
                We even include our SimpleStack℠ guarantee at no extra charge.

                <InfoTooltip color="bg-brandcomp-100">
                  <div class="float-left mr-4 mb-2 shape-icon">
                    <Icon icon="fa6-solid:handshake-simple" class="w-24 h-24 text-brandcomp-600" />
                  </div>
                  <h3 class="font-bold mb-2">Our SimpleStack℠ Guarantee</h3>
                  <p class="prose">Our SimpleStack guarantee ensures effortless deployment and management of our
                    software. You can have the entire system up and running in minutes, from a single docker container.
                  </p>
                  <p class="prose">Whether you're a seasoned DevOps pro or new to self-hosting, our SimpleStack design
                    ensures you can focus on using the product, not wrestling with infrastructure. That's the
                    SimpleStack advantage!</p>
                  <p class="prose mt-4 font-semibold ">
                    While others are stacking up complications, we've got your back with a stack so simple, it just
                    works.
                  </p>
                </InfoTooltip>
              </div>
            </div>
            <div class="mt-6 rounded-md shadow lg:ml-10 lg:mt-0 lg:flex-shrink-0">
              <a href="https://github.com/onetimesecret/onetimesecret"
                 class="block items-center justify-center rounded-md border border-transparent bg-brandcompdim-300 px-5 py-3 text-base font-medium text-gray-900 hover:bg-brandcompdim-200">
                Get Started</a>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<!--<div class="bg-gradient-to-r from-brand-500 to-rband-500 font-bold text-2xl gradient-text">
  Gradient Text222
</div>-->
<style>
.gradient-text {
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
}
</style>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { RadioGroup, RadioGroupOption } from '@headlessui/vue'
import { Icon } from '@iconify/vue';
import MovingGlobules from '@/components/MovingGlobules.vue';
//import ButtonGroup from '@/components/ButtonGroup.vue';
import InfoTooltip
  from '@/components/InfoTooltip.vue';
const frequencies = [
  { value: 'monthly', label: 'Monthly', priceSuffix: '/month' },
  { value: 'annually', label: 'Annually', priceSuffix: '/year' },
]
const frequency = ref(frequencies[0])
const tiers = [
  {
    name: 'Identity Plus',
    id: 'tier-identity',
    href: '#',
    price: { monthly: '$25', annually: '$365' },
    description: "Secure sharing that elevates your brand and simplifies communication.",
    features: [
      'Custom domain and branding',
      'Unlimited secrets',
      'AuthentiCore℗ Technology'

    ],
    featured: false,
  },
  {
    name: 'Global Elite',
    id: 'tier-integrity',
    href: '#',
    price: { monthly: '$185', annually: '$1995' },
    description: 'Dedicated infrastructure for your company.',
    features: [
      'Dedicated, private cloud infrastructure',
      'Identity Plus',
      'Unlimited usage',
      'Data residency options (EU, US)',
      'SafeTek® Architecture'
    ],
    featured: true,
  },
]


const testimonials: Array<{ quote: string, name: string, company: string, uri: string }> = [
  {
    quote: "Powerful tools, flexible plans. Choose the package that fits your ambitions.",
    name: "Claude",
    company: "Anthropic AI",
    uri: ""
  },
  {
    quote: "The AI-powered recommendations were spot-on. I'm now on a plan that perfectly fits my business needs.",
    name: "Alex",
    company: "TechStart Solutions",
    uri: ""
  },
  {
    quote: "I love how my plan evolves with my business. It's like having a pricing partner that grows with you.",
    name: "Emma",
    company: "Growth Dynamics",
    uri: ""
  },
  {
    quote: "The flexibility to adjust features and see real-time price changes is a game-changer. No more overpaying!",
    name: "Marcus",
    company: "Agile Innovations",
    uri: ""
  },
  {
    quote: "As a freelancer, my needs change constantly. This dynamic pricing model is perfect for my fluctuating workload.",
    name: "Sophia",
    company: "Creative Freelance Hub",
    uri: ""
  },
  {
    quote: "The transparency in pricing is refreshing. I know exactly what I'm paying for and why.",
    name: "Daniel",
    company: "Clear Vision Analytics",
    uri: ""
  },
  {
    quote: "We scaled from a small team to a mid-sized company, and our pricing plan seamlessly adapted. Brilliant!",
    name: "Laura",
    company: "ScaleUp Enterprises",
    uri: ""
  },
  {
    quote: "The customization options allowed me to create a plan that aligns perfectly with my nonprofit's budget and goals.",
    name: "Michael",
    company: "Community Impact Foundation",
    uri: ""
  }
];





const randomTestimonial = ref(testimonials[0]);

onMounted(() => {
  const randomIndex = Math.floor(Math.random() * testimonials.length);
  randomTestimonial.value = testimonials[randomIndex];
});
</script>

<style scoped></style>
