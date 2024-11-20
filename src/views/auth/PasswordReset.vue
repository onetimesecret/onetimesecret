<script setup lang="ts">
import { useFetchDataRecord } from '@/composables/useFetchData';
import { SecretData } from '@/schemas/models';
import { useCsrfStore } from '@/stores/csrfStore';
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';

const csrfStore = useCsrfStore();
const router = useRouter();

export interface Props {
  enabled?: boolean;
  resetKey: string;
}

/**
 * Handles errors by redirecting to '/' if the status is 404.
 * @param error - The error object.
 * @param status - The HTTP status code.
 */
 const onError = (error: Error, status?: number | null) => {
  if (status === 404) {
    router.push('/');
  }
};


const props = withDefaults(defineProps<Props>(), {
  enabled: true,
})

const { fetchData: fetchSecret } = useFetchDataRecord<SecretData>({
  url: `/api/v2/secret/${props.resetKey}`,
  onError,
});

onMounted(fetchSecret)

</script>

<template>
  <h3 class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
    Request password reset
  </h3>

  <div class="mb-4 rounded bg-white px-8 pb-8 pt-6 shadow-md dark:bg-gray-800">
    <p class="mb-4 text-gray-700 dark:text-gray-300">
      Please enter your new password below. Make sure it's at least 8 characters long and includes a
      mix of letters, numbers, and symbols.
    </p>
    <form
      method="post"
      id="passwordResetForm">
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp"
      />

      <!-- Username field for accessibility -->
      <div class="mb-4 hidden">
        <label
          class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
          for="email">
          Email address
        </label>
        <input
          type="text"
          name="email"
          id="usernameField"
          autocomplete="email"
          class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none dark:bg-gray-700 dark:text-gray-300"
          placeholder=""
        />
      </div>

      <div class="mb-4">
        <label
          class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
          for="passField">
          New password
        </label>
        <input
          type="password"
          name="newp"
          id="passField"
          required
          minlength="6"
          autocomplete="new-password"
          class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none dark:bg-gray-700 dark:text-gray-300"
          placeholder=""
        />
      </div>
      <div class="mb-6">
        <label
          class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
          for="pass2Field">
          Confirm password
        </label>
        <input
          type="password"
          name="newp2"
          id="pass2Field"
          required
          minlength="6"
          autocomplete="new-password"
          class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none dark:bg-gray-700 dark:text-gray-300"
          placeholder=""
        />
      </div>
      <div id="app"></div>
      <div class="flex items-center justify-between">
        <button
          type="submit"
          class="focus:shadow-outline rounded bg-brand-500 px-4 py-2 font-bold text-white transition duration-300 hover:bg-brand-700 focus:outline-none dark:bg-brand-600 dark:hover:bg-brand-800">
          Update Password
        </button>
      </div>
    </form>
  </div>

  <div class="mt-6 text-center">
    <router-link
      to="/signin"
      class="text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-300">
      Back to Sign-in
    </router-link>
  </div>
</template>
