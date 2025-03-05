<script setup lang="ts">
import { useSecret } from '@/composables/useSecret';
import { useCsrfStore } from '@/stores/csrfStore';
import { onMounted } from 'vue';
import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  resetKey: string;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
})

const defaultAsyncHandlerOptions: AsyncHandlerOptions = {}


const { state, load } = useSecret(props.resetKey, defaultAsyncHandlerOptions);

onMounted(load);
</script>

<template>
  <h3 class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
    {{ $t('choose-a-new-password') }}
  </h3>

  <div class="mb-4 rounded bg-white px-8 pb-8 pt-6 shadow-md dark:bg-gray-800">
    <p class="mb-4 text-gray-700 dark:text-gray-300">
      {{ $t('please-enter-your-new-password-below-make-sure-i') }}
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
          {{ $t('email-address') }}
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
          {{ $t('new-password') }}
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
          {{ $t('confirm-password') }}
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
          :disabled="state.isLoading"
          class="focus:shadow-outline rounded bg-brand-500 px-4 py-2 font-bold text-white transition duration-300 hover:bg-brand-700 focus:outline-none dark:bg-brand-600 dark:hover:bg-brand-800">
          {{ $t('web.account.changePassword.updatePassword') }}
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
</template>
