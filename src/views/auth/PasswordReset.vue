<script setup lang="ts">
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  enabled: true,
})

</script>

<template>
  <h3 class="text-2xl font-semibold mb-6 text-gray-900 dark:text-gray-100">
    Request password reset
  </h3>

  <div class="bg-white dark:bg-gray-800 shadow-md rounded px-8 pt-6 pb-8 mb-4">
    <p class="mb-4 text-gray-700 dark:text-gray-300">
      Please enter your new password below. Make sure it's at least 8 characters long and includes a
      mix of letters, numbers, and symbols.
    </p>
    <form method="post"
          id="passwordResetForm">
      <input type="hidden"
             name="shrimp"
             :value="csrfStore.shrimp" />

      <!-- Username field for accessibility -->
      <div class="mb-4 hidden">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2" for="email">
          Email address
        </label>
        <input type="text" name="email" id="usernameField" autocomplete="email" class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline" placeholder="" />
      </div>

      <div class="mb-4">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="passField">
          New password
        </label>
        <input type="password"
               name="newp"
               id="passField"
               required
               minlength="6"
               class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline"
               placeholder="" />
      </div>
      <div class="mb-6">
        <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
               for="pass2Field">
          Confirm password
        </label>
        <input type="password"
               name="newp2"
               id="pass2Field"
               required
               minlength="6"
               class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline"
               placeholder="" />
      </div>
      <div id="app"></div>
      <div class="flex items-center justify-between">
        <button type="submit"
                class="bg-brand-500 hover:bg-brand-700 dark:bg-brand-600 dark:hover:bg-brand-800 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline transition duration-300">
          Update Password
        </button>
      </div>
    </form>
  </div>

  <div class="text-center mt-6">
    <router-link to="/signin"
                 class="text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-300">
      Back to Sign-in
    </router-link>
  </div>
</template>
