<!-- eslint-disable vue/multi-word-component-names -->
<template>
  <div class="relative flex min-h-screen items-center justify-center overflow-hidden px-4 sm:px-6 lg:px-8
              bg-gray-50 dark:bg-gray-900">
    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <Icon :icon="currentRegion.icon"
            class="absolute top-0 left-1/2 h-auto w-full transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center blur-x backdrop-invert"
            aria-hidden="true" />
    </div>

    <div class="relative z-10 w-full max-w-md space-y-8">
      <div class="flex flex-col items-center">
        <Icon :icon="currentRegion.icon"
              class="mb-32 h-48 w-48 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
      </div>
      <div class="text-center">
        <h2 class="mt-6 text-4xl font-extrabold text-gray-900 dark:text-white">
          Create your account
        </h2>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Located in {{ currentRegion.identifier }}
        </p>
      </div>

      <div class="mt-8 rounded-lg p-8 shadow-xl bg-white dark:bg-gray-800">
        <SignUpForm :planid="currentPlanId"
                    :region="currentRegion" />

        <div class="mt-6">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-300 dark:border-gray-700"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="px-2 text-gray-500 dark:text-gray-400 bg-white dark:bg-gray-800">
                Or continue with
              </span>
            </div>
          </div>

          <div class="mt-6 grid grid-cols-3 gap-3">
            <button v-for="provider in socialProviders"
                    :key="provider.name"
                    class="inline-flex w-full justify-center rounded-md border px-4 py-2 text-sm font-medium
                           shadow-sm bg-white hover:bg-gray-50 text-gray-500 border-gray-300
                           dark:bg-gray-700 dark:hover:bg-gray-600 dark:text-gray-300 dark:border-gray-700
                           focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
                           transition-colors duration-200"
                    :aria-label="`Sign up with ${provider.name}`">
              <Icon :icon="provider.icon"
                    class="h-5 w-5"
                    aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>

      <div class="mt-4 text-center">
        <router-link to="/signin"
                     class="font-medium text-brand-600 hover:text-brand-500
                            dark:text-brand-400 dark:hover:text-brand-300
                            transition-colors duration-200">
          Already have an account? Sign in
        </router-link>
      </div>
    </div>
  </div>
</template>




<script setup lang="ts">
import { ref, computed } from 'vue';
import { Icon } from '@iconify/vue';
import SignUpForm from '@/components/auth/SignUpForm.vue';
import { useWindowProps } from '@/composables/useWindowProps';
import type { Jurisdiction } from '@/types/onetime';

const { regions_enabled: regionsEnabled, regions } = useWindowProps(['regions_enabled', 'regions']);

const currentPlanId = ref('basic');

const currentRegion = computed(() => {
  if (regionsEnabled && regions.value.current_jurisdiction) {
    const defaultJurisdiction = regions.value.current_jurisdiction;
    const jurisdiction: Jurisdiction | undefined = regions.value.jurisdictions.find(j => j.identifier === defaultJurisdiction) || regions.value.jurisdictions[0];
    return jurisdiction;
  } else {
    throw new Error('No jurisdictions found or regions are not enabled.');
  }
});

const socialProviders = [
  { name: 'Google', icon: 'mdi:google' },
  { name: 'GitHub', icon: 'mdi:github' },
  { name: 'Twitter', icon: 'mdi:twitter' },
];
</script>
