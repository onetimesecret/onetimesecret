<!-- SignUpForm.vue -->
<template>
  <form action="/signup"
        method="POST"
        class="mt-8 space-y-6">
    <div class="rounded-md shadow-sm -space-y-px text-lg">
      <div>
        <label for="email-address"
               class="sr-only">Email address</label>
        <input id="email-address"
               name="email"
               type="email"
               autocomplete="email"
               required
               class="relative block w-full rounded-none rounded-t-md appearance-none
                      text-lg
                      border border-gray-300
                      px-3 py-2
                      placeholder-gray-500 text-gray-900
                      focus:outline-none focus:ring-brand-500 focus:border-brand-500 focus:z-10
                      dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white
                      dark:focus:ring-brand-500 dark:focus:border-brand-500"
               placeholder="Email address"
               v-model="email">
      </div>
      <div>
        <label for="password"
               class="sr-only">Password</label>
        <input id="password"
               name="password"
               type="password"
               autocomplete="new-password"
               required
               class="relative block w-full rounded-none rounded-b-md appearance-none
                      text-lg
                      border border-gray-300
                      px-3 py-2
                      placeholder-gray-500 text-gray-900
                      focus:outline-none focus:ring-brand-500 focus:border-brand-500 focus:z-10
                      dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white
                      dark:focus:ring-brand-500 dark:focus:border-brand-500"
               placeholder="Password"
               v-model="password">
      </div>
    </div>

    <div class="flex items-center justify-between">
      <div class="flex items-center text-lg">
        <input id="terms-agreement"
               name="terms-agreement"
               type="checkbox"
               required
               class="h-4 w-4 rounded
                      border-gray-300
                      text-brand-600
                      focus:ring-brand-500
                      dark:border-gray-600 dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-brand-500"
               v-model="termsAgreed">
        <label for="terms-agreement"
               class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
          I agree to the
          <a href="#"
             class="font-medium text-brand-600 hover:text-brand-500
                    dark:text-brand-500 dark:hover:text-brand-400">Terms
            of Service</a>
          and
          <a href="#"
             class="font-medium text-brand-600 hover:text-brand-500
                    dark:text-brand-500 dark:hover:text-brand-400">Privacy
            Policy</a>
        </label>
      </div>
    </div>

    <div>
      <button type="submit"
              class="group relative w-full flex justify-center
                     rounded-md
                     py-2 px-4
                     text-lg font-medium text-white
                     border border-transparent
                     bg-brand-600 hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
        Sign up
      </button>
    </div>
  </form>
</template>


<!-- signup_form_basic.vue -->
<script setup lang="ts">
import { ref } from 'vue';
import { Jurisdiction } from '@/types/onetime';
//import { useCsrfStore } from '@/stores/csrfStore';
//
//const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  planid?: string;
  jurisdiction?: Jurisdiction
}

withDefaults(defineProps<Props>(), {
  enabled: true,
  planid: 'basic',
})

const email = ref('');
const password = ref('');

const termsAgreed = ref(false);

</script>
