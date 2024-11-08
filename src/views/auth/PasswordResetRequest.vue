
<template>
  <div class="my-20">
    <section class="my-8">
      <h3 class="text-2xl font-semibold mb-6 text-gray-900 dark:text-gray-100">
        Request password reset
      </h3>
    </section>
    <div class="bg-white dark:bg-gray-800 shadow-md rounded px-8 pt-6 pb-8 mb-4">
      <p class="mb-4 text-gray-700 dark:text-gray-300">
        Enter your email address below, and we'll send you instructions to reset your password.
      </p>
      <form method="post"
            id="resetRequestForm">
        <input type="hidden"
              name="shrimp"
              :value="csrfStore.shrimp" />

        <div class="mb-4">
          <label class="block text-gray-700 dark:text-gray-300 text-sm font-bold mb-2"
                for="custidField">
            Email address
          </label>
          <input type="email"
                name="u"
                id="custidField"
                required
                class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 dark:text-gray-300 dark:bg-gray-700 leading-tight focus:outline-none focus:shadow-outline"
                value=""
                placeholder="e.g. tom@myspace.com" />
        </div>
        <div class="mb-6"></div>
        <div class="flex items-center justify-between">
          <button type="submit"
                  class="bg-brand-500 hover:bg-brand-700 dark:bg-brand-600 dark:hover:bg-brand-800 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline transition duration-300">
            Request Reset
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
  </div>
</template>

<script setup lang="ts">
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
})

</script>
