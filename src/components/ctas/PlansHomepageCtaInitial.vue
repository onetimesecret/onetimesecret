<template>
  <section
    class="mx-auto my-12 max-w-4xl overflow-hidden rounded-lg bg-white shadow-md transition-colors duration-300 dark:bg-gray-800">
    <div class="relative flex flex-col items-start justify-between p-8 md:flex-row">
      <div class="w-full md:w-2/3 md:pr-8">
        <h2 class="mb-4 flex items-center text-3xl font-bold text-gray-800 dark:text-white">
          <svg
            class="mr-3 size-8 text-brand-500"
            fill="none"
            stroke="currentColor"
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
        <p class="mb-6 text-gray-600 dark:text-gray-300">
          {{ $t('web.page.cta_subtitle') }}
        </p>
        <ul class="mb-8 space-y-3 text-sm text-gray-600 dark:text-gray-300">
          <li class="flex items-center">
            <svg
              class="mr-3 size-5 text-brand-500"
              fill="none"
              stroke="currentColor"
              height="20"
              width="20"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg">
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
              class="mr-3 size-5 text-brand-500"
              fill="none"
              stroke="currentColor"
              height="20"
              width="20"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg">
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
              class="mr-3 size-5 text-brand-500"
              fill="none"
              stroke="currentColor"
              height="20"
              width="20"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg">
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
        <router-link
          to="/pricing"
          class="inline-flex items-center rounded-md bg-brand-600 px-6 py-3 font-brand font-semibold text-white transition duration-300 hover:bg-brand-700">
          {{ $t('web.page.explore_premium_plans') }}
          <svg
            class="ml-2 size-4"
            fill="none"
            stroke="currentColor"
            height="20"
            width="20"
            viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 5l7 7-7 7"
            />
          </svg>
        </router-link>
      </div>
      <div class="mt-20 w-full md:mt-20 md:w-1/3 md:border-l md:border-gray-200 md:pl-8 dark:md:border-gray-700">
        <p class="mb-4 text-gray-600 dark:text-gray-300">
          {{ $t('web.page.need_free_account') }}
        </p>

        <router-link
          to="/signup"
          class="inline-block w-full rounded-md bg-gray-100 px-6 py-3 text-center font-brand text-base font-semibold text-gray-800 transition duration-300 hover:bg-gray-200 dark:bg-gray-700 dark:text-white dark:hover:bg-gray-600">
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
