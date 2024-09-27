<!-- signup_form_basic.vue -->
<script setup lang="ts">
import { ref } from 'vue';
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  planid?: string;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  planid: 'basic',
})

const email = ref('');
const password = ref('');
const confirmPassword = ref('');
const skill = ref('');
const passwordFieldType = ref('password');
const confirmPasswordFieldType = ref('password');

const togglePasswordVisibility = (field: 'password' | 'confirmPassword') => {
  if (field === 'password') {
    passwordFieldType.value = passwordFieldType.value === 'password' ? 'text' : 'password';
  } else {
    confirmPasswordFieldType.value = confirmPasswordFieldType.value === 'password' ? 'text' : 'password';
  }
};

</script>

<template>

  <form action="/signup"
        method="POST"
        class="max-w-md mx-auto bg-white dark:bg-gray-800 p-6 rounded-lg shadow-lg">
    <input type="hidden"
           name="utf8"
           value="✓" />
    <input type="hidden"
           name="shrimp"
           :value="csrfStore.shrimp" />
    <input type="hidden"
           name="planid"
           :value="props.planid" />

    <fieldset>
      <div class="mb-4 relative">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="custidField">
          {{ $t('web.COMMON.field_email') }}
        </label>
        <div class="relative">
          <input v-model="email"
                 type="email"
                 name="u"
                 id="custidField"
                 tabindex="1"
                 class="w-full pl-10 pr-3 py-2 text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border rounded-md transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500 invalid:border-red-500"
                 :placeholder="$t('web.COMMON.email_placeholder')"
                 autocomplete="email"
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
                  d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207">
            </path>
          </svg>
        </div>
      </div>

      <div class="mb-4 relative">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="passField">
          {{ $t('web.COMMON.field_password') }}
        </label>
        <div class="relative">
          <input v-model="password"
                 :type="passwordFieldType"
                 name="p"
                 id="passField"
                 tabindex="2"
                 class="w-full pl-10 pr-10 py-2 text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border rounded-md transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500"
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
                  @click="togglePasswordVisibility('password')"
                  class="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600">
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

      <div class="mb-4 relative">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="pass2Field">
          {{ $t('web.COMMON.field_password2') }}
        </label>
        <div class="relative">
          <input v-model="confirmPassword"
                 :type="confirmPasswordFieldType"
                 name="p2"
                 id="pass2Field"
                 tabindex="3"
                 class="w-full pl-10 pr-10 py-2 text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border rounded-md transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500"
                 :placeholder="$t('web.COMMON.confirm_password_placeholder')"
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
                  @click="togglePasswordVisibility('confirmPassword')"
                  class="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600">
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

      <div class="mb-4 hidden">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="skillTest">
          Skill
        </label>
        <input v-model="skill"
               type="text"
               name="skill"
               id="skillTest"
               class="w-full px-3 py-2 text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border rounded-md transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500"
               :placeholder="$t('web.COMMON.skill_placeholder')"
               autocomplete="off" />
      </div>

      <div class="flex items-center justify-between">
        <button type="submit"
                tabindex="4"
                class="px-4 py-2 font-bold text-white bg-brand-500 rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2 dark:bg-brand-600 dark:hover:bg-brand-700 transition-colors duration-300 ease-in-out transform hover:scale-105">
          {{ $t('web.COMMON.button_create_account') }}
        </button>
      </div>
    </fieldset>
  </form>
</template>
