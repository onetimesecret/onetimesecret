<!-- StatusLink -->
<!-- older -->
<script setup lang="ts">
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { ref } from 'vue';

  interface Props {
    record: Metadata;
    details: MetadataDetails;
    isInitialView: boolean;
  }

  defineProps<Props>();

  const copied = ref(false);
  const showToast = ref(false);
  const linkInput = ref<HTMLInputElement>();

  const copyToClipboard = async () => {
    if (!linkInput.value) return;

    try {
      await navigator.clipboard.writeText(linkInput.value.value);
      copied.value = true;
      showToast.value = true;

      // Reset copy icon
      setTimeout(() => {
        copied.value = false;
      }, 2000);

      // Hide toast
      setTimeout(() => {
        showToast.value = false;
      }, 1500);
    } catch (err) {
      console.error('Failed to copy text: ', err);

      linkInput.value.select();
      document.execCommand('copy'); // fallback for older browsers
    }
  };
</script>

<template>
  <div>
    <h1
      id="secret-header"
      class="sr-only">
      {{ $t('web.LABELS.secret_link') }}
    </h1>

    <!-- Passphrase Indicator -->
    <div
      v-if="details?.has_passphrase"
      class="absolute -top-4 right-2 flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400">
      <OIcon
        collection=""
        name="mdi-lock"
        class="w-4 h-4" />
      {{ $t('web.LABELS.passphrase_protected') }}
    </div>

    <div
      class="relative overflow-hidden rounded-lg border bg-white dark:bg-gray-800 dark:border-gray-700 border-gray-200">

      <!-- Momentum Indicator - Changes color based on state -->
      <div class="absolute top-0 left-0 w-full h-1 overflow-hidden">
        <div
          class="w-full h-full bg-200% animate-gradient-x"
          :class="[
            isInitialView
              ? 'bg-gradient-to-r from-green-400 via-green-600 to-green-400'
              : 'bg-gradient-to-r from-amber-400 via-amber-600 to-amber-300'
          ]">
        </div>
      </div>

      <!-- Initial Success Message - Only shown on first view -->
      <div
        v-if="isInitialView"
        class="flex items-center gap-2 mb-2 px-4 pt-3 text-base font-brand text-green-600 dark:text-green-400">
        <OIcon
          collection="mdi"
          name="check-circle"
          class="size-5"
          aria-hidden="true" />
          <span>{{ $t('web.private.created_success') }}</span>
      </div>

      <!-- Subsequent Message - Shown after first view -->
      <div
        class="flex items-center gap-2 mb-2 px-4 pt-3 text-sm font-mono text-gray-500 mt-2">
        <OIcon
          collection="material-symbols"
          name="key-vertical"
          class="size-4"
          aria-hidden="true" />
        <span>{{ record.secret_shortkey }}</span>
      </div>

      <!-- Secret Link Display -->
      <div class="flex items-start px-4 py-3">
        <div class="flex-grow min-w-0">
          <textarea
            ref="linkInput"
            readonly
            :value="record.share_url"
            class="w-full bg-transparent border-0 text-gray-900 font-mono text-sm sm:text-base dark:text-gray-100 focus:ring-0 resize-none pt-1"
            aria-label="Secret link"></textarea>
        </div>

        <div class="flex-shrink-0 ml-4">
          <button
            @click="copyToClipboard"
            class="inline-flex items-center justify-center p-2 rounded-md text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-150"
            :class="{ 'text-green-500 dark:text-green-400': copied }">
            <OIcon
              collection="material-symbols"
              :name="copied ? 'check' : 'content-copy-outline'"
              class="w-5 h-5" />
            <span class="sr-only">{{ copied ? 'Copied!' : 'Copy to clipboard' }}</span>
          </button>
        </div>
      </div>

      <!-- Security Notice -->
      <div
        class="bg-gray-50 dark:bg-gray-900/50 px-4 py-2 border-t border-gray-200 dark:border-gray-700">
        <div class="flex items-center text-xs text-gray-500 dark:text-gray-400">
          <OIcon
            collection="material-symbols"
            name="shield-outline"
            class="w-4 h-4 mr-2" />
          {{ $t('web.COMMON.share_link_securely') }}
        </div>
      </div>

      <!-- Copy Feedback Toast -->
      <div
        v-if="showToast"
        class="absolute top-3 right-3 px-3 py-1.5 bg-gray-900 dark:bg-gray-700 text-white text-sm rounded-md shadow-lg transform transition-all duration-300"
        :class="{
          'opacity-0 translate-y-1': !showToast,
          'opacity-100 translate-y-0': showToast,
        }">
        {{ $t('web.COMMON.copied_to_clipboard') }}
      </div>
    </div>
  </div>
</template>
