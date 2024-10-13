<template>

  <section
           class="max-w-4xl mx-auto my-8 bg-gradient-to-r from-brand-500 to-brand-600 rounded-lg shadow-lg overflow-hidden">
    <div class="p-6 flex flex-col md:flex-row items-center justify-between">
      <div class="w-full md:w-2/3 md:pr-6">
        <h2 class="text-2xl md:text-3xl font-bold text-white mb-2 flex items-center"
            id="bannerTitle">
          <svg class="w-8 h-8 mr-3 text-brand-500"
               fill="none"
               stroke="white"
               height="20"
               width="20"
               viewBox="0 0 24 24"
               xmlns="http://www.w3.org/2000/svg">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z">
            </path>
          </svg>
          {{ $t('web.page.cta_title') }}
        </h2>
        <p class="text-white text-opacity-90 mb-4">{{ $t('web.page.cta_subtitle') }}</p>
        <ul class="space-y-2 text-sm text-white text-opacity-90 mb-4">
          <li class="flex items-center">
            <svg class="h-5 w-5 mr-2 text-white"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg"
                 width="20"
                 height="20"
                 aria-hidden="true">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"></path>
            </svg>
            {{ $t('web.page.cta_feature1') }}
          </li>
          <li class="flex items-center">
            <svg class="h-5 w-5 mr-2 text-white"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg"
                 width="20"
                 height="20"
                 aria-hidden="true">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"></path>
            </svg>
            {{ $t('web.page.cta_feature2') }}
          </li>
          <li class="flex items-center">
            <svg class="h-5 w-5 mr-2 text-white"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg"
                 width="20"
                 height="20"
                 aria-hidden="true">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"></path>
            </svg>
            {{ $t('web.page.cta_feature3') }}
          </li>
        </ul>
      </div>
      <div class="w-full md:w-1/3 flex flex-col items-center md:items-end">
        <router-link to="/pricing"
                     class="w-full md:w-auto mb-3 px-6 py-3 bg-white text-brand-600 font-semibold rounded-md hover:bg-opacity-90 transition duration-300 text-center"
                     aria-describedby="bannerTitle">
          {{ $t('web.page.explore_premium_plans') }}
        </router-link>
        <router-link to="/signup"
                     class="w-full md:w-auto px-6 py-3 bg-brand-700 text-white font-semibold rounded-md hover:bg-brand-800 transition duration-300 text-center"
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
