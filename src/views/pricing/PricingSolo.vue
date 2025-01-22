<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import MovingGlobules from '@/components/MovingGlobules.vue';
  import QuoteSection from '@/components/QuoteSection.vue';

  import { testimonials as testimonialsData } from '@/sources/testimonials';

  import { onMounted, ref } from 'vue';

  const testimonials = ref(testimonialsData);
  const randomTestimonial = ref(testimonials.value[0]);

  onMounted(() => {
    const randomIndex = Math.floor(Math.random() * testimonials.value.length);
    randomTestimonial.value = testimonials.value[randomIndex];
  });

  const includedFeatures = [
    'Private forum access',
    'Member resources',
    'Entry to annual conference',
    'Official member t-shirt',
  ];
</script>

<template>
  <div class="relative isolate bg-white px-6 dark:bg-gray-900 py-24 sm:py-32 lg:px-8">
    <MovingGlobules
      from-colour="#23b5dd"
      to-colour="#dc4a22"
      speed="10s"
      :interval="3000"
      :scale="1" />
    <div class="mx-auto max-w-7xl px-6 lg:px-8">
      <div class="mx-auto max-w-4xl sm:text-center">
        <h2 class="text-5xl font-semibold tracking-tight text-pretty text-gray-900 sm:text-6xl sm:text-balance">
          Secure Links, Stronger Connections
        </h2>
        <p class="mx-auto mt-6 max-w-2xl text-lg font-medium text-pretty text-gray-500 sm:text-xl/8">
          Distinctio et nulla eum soluta et neque labore quibusdam. Saepe et quasi iusto modi velit ut non voluptas in.
          Explicabo id ut laborum.
        </p>
      </div>
      <div class="mx-auto mt-16 max-w-2xl rounded-3xl ring-1 ring-gray-200 sm:mt-20 lg:mx-0 lg:flex lg:max-w-none">
        <div class="p-8 sm:p-10 lg:flex-auto">
          <h3 class="text-3xl font-semibold tracking-tight text-gray-900">Lifetime membership</h3>
          <p class="mt-6 text-base/7 text-gray-600">
            Lorem ipsum dolor sit amet consect etur adipisicing elit. Itaque amet indis perferendis blanditiis
            repellendus etur quidem assumenda.
          </p>
          <div class="mt-10 flex items-center gap-x-4">
            <h4 class="flex-none text-sm/6 font-semibold text-indigo-600">What’s included</h4>
            <div class="h-px flex-auto bg-gray-100"></div>
          </div>
          <ul
            role="list"
            class="mt-8 grid grid-cols-1 gap-4 text-sm/6 text-gray-600 sm:grid-cols-2 sm:gap-6">
            <li
              v-for="feature in includedFeatures"
              :key="feature"
              class="flex gap-x-3">
              <OIcon
                collection="heroicons"
                name="check-16-solid"
                class="h-6 w-5 flex-none text-indigo-600"
                aria-hidden="true" />
              {{ feature }}
            </li>
          </ul>
        </div>
        <div class="-mt-2 p-2 lg:mt-0 lg:w-full lg:max-w-md lg:shrink-0">
          <div
            class="rounded-2xl bg-gray-50 py-10 text-center ring-1 ring-gray-900/5 ring-inset lg:flex lg:flex-col lg:justify-center lg:py-16">
            <div class="mx-auto max-w-xs px-8">
              <p class="text-base font-semibold text-gray-600">Pay once, own it forever</p>
              <p class="mt-6 flex items-baseline justify-center gap-x-2">
                <span class="text-5xl font-semibold tracking-tight text-gray-900">$349</span>
                <span class="text-sm/6 font-semibold tracking-wide text-gray-600">USD</span>
              </p>
              <a
                href="#"
                class="mt-10 block w-full rounded-md bg-indigo-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">
                Get access
              </a>
              <p class="mt-6 text-xs/5 text-gray-600">Invoices and receipts available for easy company reimbursement</p>
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
        class="absolute inset-0 z-0"
        from-colour="#23b5dd"
        to-colour="#dc4a22"
        speed="10s"
        :interval="1000"
        :scale="2" />
    </div>
  </div>
</template>
