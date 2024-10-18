<!-- eslint-disable vue/multi-word-component-names -->

<template>
  <div class="relative flex min-h-screen items-start justify-center overflow-hidden px-4 sm:px-6 lg:px-8
              bg-gray-50 dark:bg-gray-900 pt-16 sm:pt-24">
    <!-- Background Icon -->
    <div class="absolute inset-0 overflow-hidden opacity-5 dark:opacity-10">
      <Icon :icon="currentJurisdiction.icon"
            class="absolute top-0 left-1/2 h-auto w-full transform -translate-x-1/2 translate-y-0 scale-150
                   object-cover object-center blur-x backdrop-invert"
            aria-hidden="true" />
    </div>

    <div class="relative z-10 w-full max-w-md space-y-6">
      <div class="flex flex-col items-center">
        <Icon :icon="currentJurisdiction.icon"
              class="mb-24 h-40 w-40 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
      </div>
      <div class="text-center">
        <h2 id="signin-heading"
            class="text-3xl font-extrabold text-gray-900 dark:text-white">
          Sign in to your account
        </h2>
        <p class="mt-2 text-base text-gray-600 dark:text-gray-400 flex items-center justify-center">
          <span class="mr-1">
            Serving you from the <span lang="en">{{ currentJurisdiction.identifier }}</span>
          </span>
        </p>
      </div>

      <div class="mt-6 rounded-lg p-8 shadow-xl bg-white dark:bg-gray-800">
        <SignInForm />

        <div class="mt-6 text-center">
          <ul class="space-y-2">
            <li>
              <router-link to="/forgot"
                           class="text-sm text-gray-600 dark:text-gray-400 hover:underline transition duration-300 ease-in-out"
                           aria-label="Forgot Password">
                {{ $t('web.login.forgot_your_password') }}
              </router-link>
            </li>
          </ul>
        </div>
      </div>

      <div class="mt-4 text-center">
        <router-link to="/signup"
                     class="font-medium text-brand-600 hover:text-brand-500
                            dark:text-brand-400 dark:hover:text-brand-300
                            transition-colors duration-200">
          {{ $t('web.login.need_an_account') }}
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import SignInForm from '@/components/auth/SignInForm.vue';
import { Icon } from '@iconify/vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

const currentJurisdiction = computed(() => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: 'mdi:help-circle',
});

</script>
