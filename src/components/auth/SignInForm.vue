
<script setup lang="ts">
import { ref } from 'vue';
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
})

const email = ref('');
const password = ref('');
const rememberMe = ref(false);
const showPassword = ref(false);

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};


</script>

<template>
  <form action="/signin" method="POST"
        class="bg-white dark:bg-gray-800 shadow-md rounded px-8 pt-6 pb-8 mb-4">
    <input type="hidden"
           name="utf8"
           value="✓" />
    <input type="hidden"
           name="shrimp"
           :value="csrfStore.shrimp" />

    <fieldset>
      <div class="mb-4 relative">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="custidField">
          {{ $t('web.COMMON.field_email') }}
        </label>
        <div class="relative">
          <svg class="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400"
               fill="none"
               stroke="currentColor"
               viewBox="0 0 24 24"
               xmlns="http://www.w3.org/2000/svg"
               width="20"
               height="20">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207">
            </path>
          </svg>
          <input v-model="email"
                 type="email"
                 name="u"
                 id="custidField"
                 required
                 tabindex="1"
                 autofocus
                 class="shadow appearance-none border rounded w-full py-2 pl-10 pr-3
              text-gray-700 dark:text-gray-300 dark:bg-gray-700 focus:ring-brandcomp-500 focus:ring-2
                leading-tight focus:outline-none focus:shadow-outline transition duration-300 ease-in-out
                invalid:not(:placeholder-shown):border-red-500 invalid:not(:placeholder-shown):text-red-600"
                 :placeholder="$t('web.COMMON.email_placeholder')"
                 autocomplete="email"
                 aria-required="true" />
        </div>
      </div>
      <div class="mb-6 relative">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="passField">
          {{ $t('web.COMMON.field_password') }}
        </label>
        <div class="relative">
          <input v-model="password"
                 :type="showPassword ? 'text' : 'password'"
                 name="p"
                 id="passField"
                 required
                 tabindex="2"
                 class="w-full pl-10 pr-10 py-2
                text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700
                border rounded-md transition-colors duration-200 ease-in-out
                focus:outline-none focus:ring-2 focus:ring-brandcomp-500"
                 :placeholder="$t('web.COMMON.password_placeholder')"
                 autocomplete="new-password"
                 aria-required="true" />

          <svg class="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400"
               fill="none"
               stroke="currentColor"
               viewBox="0 0 24 24"
               xmlns="http://www.w3.org/2000/svg"
               width="20"
               height="20">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z">
            </path>
          </svg>
          <button type="button"
                  class="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                  @click="togglePasswordVisibility">
            <svg class="h-5 w-5"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg"
                 width="20"
                 height="20">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z">
              </path>
            </svg>
          </button>
        </div>
      </div>
      <div class="mb-6 flex items-center">
        <div class="flex items-center">
          <input v-model="rememberMe"
                 type="checkbox"
                 tabindex="3"
                 name="remember"
                 id="rememberMe"
                 class="w-4 h-4 text-brandcomp-600 bg-gray-100 border-gray-300 rounded focus:ring-brandcomp-500 dark:focus:ring-brandcomp-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600">
          <label for="rememberMe"
                 class="ml-2 text-sm font-medium text-gray-900 dark:text-gray-300">
            {{ $t('web.login.remember_me') }}
          </label>
        </div>
      </div>
      <div class="flex items-center justify-between">
        <button type="submit"
                tabindex="4"
                class="px-4 py-2 font-bold text-white bg-brand-500 rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 dark:bg-brand-600 dark:hover:bg-brand-700 transition-colors duration-300 ease-in-out transform hover:scale-105">
          {{ $t('web.login.button_sign_in') }}
        </button>
      </div>
    </fieldset>
  </form>
</template>
