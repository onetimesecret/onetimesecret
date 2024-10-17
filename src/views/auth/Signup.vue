<!-- eslint-disable vue/multi-word-component-names -->
<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900 flex items-center justify-center px-4 sm:px-6 lg:px-8 relative overflow-hidden">
    <!-- Background Icon -->
    <div class="absolute inset-0 opacity-5 dark:opacity-10 overflow-hidden">
      <Icon :icon="currentRegion.icon"
            class="absolute top-0 left-1/2 w-full h-auto object-cover object-center transform -translate-x-1/2 translate-y-0 scale-150 blur-x"
            aria-hidden="true" />
    </div>

    <div class="max-w-md w-full space-y-8 relative z-10">
      <div class="flex flex-col items-center">
        <Icon :icon="currentRegion.icon" class="h-48 w-48 text-brand-600 dark:text-brand-400 mb-32" aria-hidden="true" />
      </div>
      <div class="text-center">
        <h2 class="mt-6 text-4xl font-extrabold text-gray-900 dark:text-white">
          Create your account
        </h2>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Join us in {{ currentRegion.display_name }}
        </p>
      </div>

      <div class="mt-8 bg-white dark:bg-gray-800 shadow-xl rounded-lg p-8">
        <SignUpForm :planid="currentPlanId" :region="currentRegion" />

        <div class="mt-6">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-300 dark:border-gray-700"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="px-2 bg-white dark:bg-gray-800 text-gray-500 dark:text-gray-400">
                Or continue with
              </span>
            </div>
          </div>

          <div class="mt-6 grid grid-cols-3 gap-3">
            <button v-for="provider in socialProviders" :key="provider.name"
                    class="w-full inline-flex justify-center py-2 px-4 border border-gray-300 dark:border-gray-700 rounded-md shadow-sm bg-white dark:bg-gray-700 text-sm font-medium text-gray-500 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-200"
                    :aria-label="`Sign up with ${provider.name}`">
              <Icon :icon="provider.icon" class="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>

      <div class="text-center mt-4">
        <router-link to="/signin"
                     class="font-medium text-brand-600 dark:text-brand-400 hover:text-brand-500 dark:hover:text-brand-300 transition-colors duration-200">
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
