<template>
  <section
    class="mx-auto my-8 max-w-4xl overflow-hidden rounded-lg bg-gradient-to-r from-brand-500 to-brand-600 shadow-lg">
    <div class="flex flex-col items-center justify-between p-6 md:flex-row">
      <div class="w-full md:w-2/3 md:pr-6">
        <h2
          class="mb-2 flex items-center text-2xl font-bold text-white md:text-3xl"
          id="bannerTitle">
          <svg
            class="mr-3 size-8 text-brand-500"
            fill="none"
            stroke="white"
            height="20"
            width="20"
            viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
            />
          </svg>
          {{ $t('web.page.cta_title') }}
        </h2>
        <p class="mb-4 text-white text-opacity-90">
          {{ $t('web.page.cta_subtitle') }}
        </p>
        <ul class="mb-4 space-y-2 text-sm text-white text-opacity-90">
          <li class="flex items-center">
            <svg
              class="mr-2 size-5 text-white"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('web.page.cta_feature1') }}
          </li>
          <li class="flex items-center">
            <svg
              class="mr-2 size-5 text-white"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('web.page.cta_feature2') }}
          </li>
          <li class="flex items-center">
            <svg
              class="mr-2 size-5 text-white"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {{ $t('web.page.cta_feature3') }}
          </li>
        </ul>
      </div>
      <div class="flex w-full flex-col items-center md:w-1/3 md:items-end">
        <router-link
          to="/pricing"
          class="mb-3 w-full rounded-md bg-white px-6 py-3 text-center font-semibold text-brand-600 transition duration-300 hover:bg-opacity-90 md:w-auto"
          aria-describedby="bannerTitle">
          {{ $t('web.page.explore_premium_plans') }}
        </router-link>
        <router-link
          to="/signup"
          class="w-full rounded-md bg-brand-700 px-6 py-3 text-center font-semibold text-white transition duration-300 hover:bg-brand-800 md:w-auto"
          aria-describedby="bannerTitle">
          {{ $t('web.page.sign_up_free') }}
        </router-link>
      </div>
    </div>
  </section>
</template>
<script setup lang="ts">
  defineProps<{
    ariaLabel: string;
  }>();
</script>
