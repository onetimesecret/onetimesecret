
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

<template>
  <div class="my-20">
    <section class="my-8">
      <h3 class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
        {{ $t('request-password-reset') }}
      </h3>
    </section>
    <div class="mb-4 rounded bg-white px-8 pb-8 pt-6 shadow-md dark:bg-gray-800">
      <p class="mb-4 text-gray-700 dark:text-gray-300">
        {{ $t('enter-your-email-address-below-and-well-send-you') }}
      </p>
      <form
        method="post"
        id="resetRequestForm">
        <input
          type="hidden"
          name="shrimp"
          :value="csrfStore.shrimp"
        />

        <div class="mb-4">
          <label
            class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
            for="custidField">
            {{ $t('email-address') }}
          </label>
          <input
            type="email"
            name="u"
            id="custidField"
            required
            class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none dark:bg-gray-700 dark:text-gray-300"
            value=""
            placeholder="$t('web.COMMON.email_placeholder')"
          />
        </div>
        <div class="mb-6"></div>
        <div class="flex items-center justify-between">
          <button
            type="submit"
            class="focus:shadow-outline rounded bg-brand-500 px-4 py-2 font-bold text-white transition duration-300 hover:bg-brand-700 focus:outline-none dark:bg-brand-600 dark:hover:bg-brand-800">
            {{ $t('request-reset') }}
          </button>
        </div>
      </form>
    </div>

    <div class="mt-6 text-center">
      <router-link
        to="/signin"
        class="text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-300">
        {{ $t('back-to-sign-in') }}
      </router-link>
    </div>
  </div>
</template>
