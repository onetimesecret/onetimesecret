<!-- SignUpForm.vue -->
<script setup lang="ts">
import { Jurisdiction } from '@/schemas/models';
import { useCsrfStore } from '@/stores/csrfStore';
import { ref } from 'vue';

const csrfStore = useCsrfStore();

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
const showPassword = ref(false);

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};
</script>

<template>
  <form
    action="/signup"
    method="POST"
    class="mt-8 space-y-6">
    <input
      type="hidden"
      name="utf8"
      value="✓"
    />
    <input
      type="text"
      name="skill"
      class="hidden"
      aria-hidden="true"
      aria-disabled="true"
      tabindex="-1"
      value=""
    />
    <input
      type="hidden"
      name="shrimp"
      :value="csrfStore.shrimp"
    />

    <div class="-space-y-px rounded-md text-lg shadow-sm">
      <!-- Email field -->
      <div>
        <label
          for="email-address"
          class="sr-only">{{ $t('email-address') }}</label>
        <input
          id="email-address"
          name="u"
          type="email"
          autocomplete="email"
          required
          focus
          tabindex="1"
          class="relative block w-full appearance-none rounded-none rounded-t-md
                      border
                      border-gray-300 px-3
                      py-2 text-lg
                      text-gray-900 placeholder:text-gray-500
                      focus:z-10 focus:border-brand-500 focus:outline-none focus:ring-brand-500
                      dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                      dark:focus:border-brand-500 dark:focus:ring-brand-500"
          :placeholder="$t('email-address')"
          v-model="email"
        />
      </div>

      <!-- Password input with visibility toggle -->
      <div class="relative">
        <label
          for="password"
          class="sr-only">{{ $t('web.COMMON.field_password') }}</label>
        <input
          id="password"
          :type="showPassword ? 'text' : 'password'"
          name="p"
          autocomplete="new-password"
          required
          tabindex="2"
          class="relative block w-full appearance-none rounded-none rounded-b-md
                 border
                 border-gray-300 px-3
                 py-2 pr-10 text-lg
                 text-gray-900 placeholder:text-gray-500
                 focus:z-10 focus:border-brand-500 focus:outline-none focus:ring-brand-500
                 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                 dark:focus:border-brand-500 dark:focus:ring-brand-500"
          :placeholder="$t('web.COMMON.field_password')"
          v-model="password"
        />
        <button
          type="button"
          @click="togglePasswordVisibility"
          class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5">
          <svg
            class="size-5 text-gray-400"
            :class="{ 'hidden': showPassword, 'block': !showPassword }"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 576 512">
            <path
              fill="currentColor"
              d="M572.52 241.4C518.29 135.59 410.93 64 288 64S57.68 135.64 3.48 241.41a32.35 32.35 0 0 0 0 29.19C57.71 376.41 165.07 448 288 448s230.32-71.64 284.52-177.41a32.35 32.35 0 0 0 0-29.19zM288 400a144 144 0 1 1 144-144 143.93 143.93 0 0 1-144 144zm0-240a95.31 95.31 0 0 0-25.31 3.79 47.85 47.85 0 0 1-66.9 66.9A95.78 95.78 0 1 0 288 160z"
            />
          </svg>

          <svg
            tabindex="3"
            class="size-5 text-gray-400"
            :class="{ 'block': showPassword, 'hidden': !showPassword }"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 640 512">
            <path
              fill="currentColor"
              d="M320 400c-75.85 0-137.25-58.71-142.9-133.11L72.2 185.82c-13.79 17.3-26.48 35.59-36.72 55.59a32.35 32.35 0 0 0 0 29.19C89.71 376.41 197.07 448 320 448c26.91 0 52.87-4 77.89-10.46L346 397.39a144.13 144.13 0 0 1-26 2.61zm313.82 58.1l-110.55-85.44a331.25 331.25 0 0 0 81.25-102.07 32.35 32.35 0 0 0 0-29.19C550.29 135.59 442.93 64 320 64a308.15 308.15 0 0 0-147.32 37.7L45.46 3.37A16 16 0 0 0 23 6.18L3.37 31.45A16 16 0 0 0 6.18 53.9l588.36 454.73a16 16 0 0 0 22.46-2.81l19.64-25.27a16 16 0 0 0-2.82-22.45zm-183.72-142l-39.3-30.38A94.75 94.75 0 0 0 416 256a94.76 94.76 0 0 0-121.31-92.21A47.65 47.65 0 0 1 304 192a46.64 46.64 0 0 1-1.54 10l-73.61-56.89A142.31 142.31 0 0 1 320 112a143.92 143.92 0 0 1 144 144c0 21.63-5.29 41.79-13.9 60.11z"
            />
          </svg>
        </button>
      </div>
    </div>

    <!-- Terms checkbox -->
    <div class="flex items-center justify-between">
      <div class="flex items-center text-lg">
        <input
          id="terms-agreement"
          name="agree"
          type="checkbox"
          required
          tabindex="4"
          class="size-4 rounded border-gray-300
                      text-brand-600
                      focus:ring-brand-500
                      dark:border-gray-600
                      dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-brand-500"
          v-model="termsAgreed"
        />
        <label
          for="terms-agreement"
          class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
          {{ $t('i-agree-to-the') }}
          <router-link
            to="/info/terms"
            class="font-medium text-brand-600 hover:text-brand-500
                     dark:text-brand-500 dark:hover:text-brand-400">
            {{ $t('terms-of-service') }}
          </router-link>
          and
          <router-link
            to="/info/privacy"
            class="font-medium text-brand-600 hover:text-brand-500
                     dark:text-brand-500 dark:hover:text-brand-400">
            {{ $t('privacy-policy') }}
          </router-link>
        </label>
      </div>
    </div>

    <!-- Submit button -->
    <div>
      <button
        type="submit"
        class="group relative flex w-full justify-center
                     rounded-md
                     border border-transparent
                     bg-brand-600 px-4 py-2
                     text-lg font-medium
                     text-white hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
        {{ $t('create-account') }}
      </button>
    </div>
  </form>
</template>
