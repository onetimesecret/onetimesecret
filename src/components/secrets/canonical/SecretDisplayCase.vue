<template>
  <div class="relative">
    <textarea
      v-if="secret.secret_value"
      class="w-full resize-none rounded-md border border-gray-300 bg-gray-100 px-3
        py-2 font-mono text-base
        leading-[1.2] tracking-wider focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
      readonly
      :rows="details.display_lines"
      :value="secret.secret_value"></textarea>
    <div
      v-else
      class="text-red-500 dark:text-red-400">
      Secret value not available
    </div>
    <button
      @click="copySecretContent"
      :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
      class="absolute right-2 top-2 rounded-md bg-gray-200 p-1.5 transition-colors duration-200 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-600 dark:hover:bg-gray-500"
      aria-label="Copy to clipboard">
      <svg
        v-if="!isCopied"
        xmlns="http://www.w3.org/2000/svg"
        class="size-5 text-gray-600 dark:text-gray-300"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
        />
      </svg>
      <svg
        v-else
        xmlns="http://www.w3.org/2000/svg"
        class="size-5 text-green-500"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M5 13l4 4L19 7"
        />
      </svg>
    </button>
  </div>

  <p
    v-if="!secret.verification"
    class="text-sm text-gray-500 dark:text-gray-400">
    ({{ $t('web.COMMON.careful_only_see_once') }})
  </p>

  <div
    v-if="secret.is_truncated"
    class="border-l-4 border-brandcomp-500 bg-brandcomp-100 p-4 text-sm text-blue-700 dark:bg-blue-800 dark:text-blue-200">
    <button
      type="button"
      class="float-right"
      @click="closeTruncatedWarning">
      &times;
    </button>
    <strong>{{ $t('web.COMMON.warning') }}</strong>
    {{ $t('web.shared.secret_was_truncated') }} {{ secret.original_size }}.
  </div>

  <div class="mt-4">
    <div
      v-if="!secret.verification"
      class="my-16 mb-4 border-l-4 border-gray-400 bg-gray-100 p-4 text-gray-700 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
      <button
        type="button"
        class="float-right hover:text-gray-900 dark:hover:text-gray-100"
        onclick="this.parentElement.remove()">
        &times;
      </button>
      <p>
        Once you've finished viewing the secret, feel free to navigate away from this page or
        close the window.
      </p>
    </div>
    <div v-else>
      <a
        href="/signin"
        class="block w-full rounded-md border border-brand-500 bg-white px-4 py-2 text-center text-brand-500 hover:bg-brand-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-brand-400 dark:bg-gray-800 dark:text-brand-400 dark:hover:bg-gray-700">
        {{ $t('web.COMMON.login_to_your_account') }}
      </a>
    </div>
  </div>

  <div class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600">
    <div class="space-x-2">
      <a
        :href="`https://${siteHost}`"
        class="hover:underline"
        rel="noopener noreferrer">
        Powered by Onetime Secret
      </a>
      <span>·</span>
      <router-link
        to="/info/terms"
        class="hover:underline">
        Terms
      </router-link>
      <span>·</span>
      <router-link
        to="/info/privacy"
        class="hover:underline">
        Privacy
      </router-link>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard';
import { useWindowProp } from '@/composables/useWindowProps';
import { SecretData, SecretDetails } from '@/schemas/models';

const siteHost = useWindowProp('site_host');

interface Props {
  secret: SecretData;
  details: SecretDetails;
}

const props = defineProps<Props>();

const { isCopied, copyToClipboard } = useClipboard();

const copySecretContent = () => {
  if (props.secret.secret_value === undefined) {
    return;
  }

  copyToClipboard(props.secret.secret_value);
};

const closeTruncatedWarning = (event: Event) => {
  (event.target as HTMLElement).closest('.bg-brandcomp-100')?.remove();
};
</script>
