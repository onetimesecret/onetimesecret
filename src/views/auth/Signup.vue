<!-- eslint-disable vue/multi-word-component-names -->
<template>
  <div class="relative flex min-h-screen items-center justify-center overflow-hidden px-4 sm:px-6 lg:px-8
              bg-gray-50 dark:bg-gray-900">
    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <Icon :icon="currentJurisdiction.icon"
            class="absolute top-0 left-1/2 h-auto w-full transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center blur-x backdrop-invert"
            aria-hidden="true" />
    </div>

    <div class="relative z-10 w-full max-w-md space-y-8">
      <div class="flex flex-col items-center">
        <Icon :icon="currentJurisdiction.icon"
              class="mb-32 h-48 w-48 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
      </div>
      <div class="text-center">
        <h2 id="signup-heading"
            class="mt-6 text-4xl font-extrabold text-gray-900 dark:text-white">
          Create your account
        </h2>
        <p class="mt-2 text-base text-gray-600 dark:text-gray-400 flex items-center justify-center">
          <span class="mr-1">
            Serving you from the <span lang="en">{{ currentJurisdiction.identifier }}</span>
          </span>
        </p>
      </div>


      <div class="mt-8 rounded-lg p-8 shadow-xl bg-white dark:bg-gray-800">
        <SignUpForm :planid="currentPlanId"
                    :jurisdiction="currentJurisdiction" />

        <!-- Alternate sign up methods -->
        <div class="mt-6 hidden">
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

          <div class="mt-8 grid grid-cols-3 gap-3 relative">
            <div class="absolute inset-0 flex items-center justify-center z-10">
              <div
                   class="roudned rounded-md font-brand dark:bg-brand-400 text-white dark:text-gray-700 px-4 py-2 text-lg font-bold transform rotate-[-15deg] shadow-lg opacity-65">
                Coming Soon
              </div>
            </div>
            <div class="absolute inset-0 bg-gray-200 bg-opacity-50 dark:bg-gray-800 dark:bg-opacity-50 z-5"></div>
            <button v-for="provider in socialProviders"
                    :key="provider.name"
                    class="inline-flex w-full justify-center rounded-md border px-4 py-2 text-sm font-medium
                           shadow-sm bg-gray-100 text-gray-400 border-gray-300 cursor-not-allowed
                         dark:bg-gray-800 dark:text-gray-500 dark:border-gray-700
                           focus:outline-none transition-colors duration-200"
                    :aria-label="`Sign up with ${provider.name} (coming soon)`"
                    disabled>
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
import { computed, ref } from 'vue';
import SignUpForm from '@/components/auth/SignUpForm.vue';
import { useWindowProps } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { Icon } from '@iconify/vue';
import { storeToRefs } from 'pinia';

const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

const { default_planid } = useWindowProps(['default_planid']);

const currentPlanId = ref(default_planid)

// Use computed properties to access the current region and jurisdiction

const currentJurisdiction = computed(() => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: 'mdi:help-circle',
});

const socialProviders = [
  { name: 'Google', icon: 'mdi:google' },
  { name: 'GitHub', icon: 'mdi:github' },
  { name: 'Twitter', icon: 'mdi:twitter' },
];
</script>
