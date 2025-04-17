<!-- src/components/secrets/metadata/SecretLink.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  interface Props {
    record: Metadata;
    details: MetadataDetails;
    isInitialView: boolean;
  }

  defineProps<Props>();

  const copied = ref(false);
  const showToast = ref(false);
  const linkInput = ref<HTMLInputElement>();
  const buttonText = computed(() =>
    copied.value ? t('web.STATUS.copied') : t('web.LABELS.copy_to_clipboard')
  );

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
      class="flex items-center gap-2 rounded-full
        border border-amber-100 bg-amber-50 px-2 py-1
        text-sm font-medium text-amber-600 shadow-sm transition-transform dark:border-amber-800/50 dark:bg-amber-900/30 dark:text-amber-400">
      <OIcon
        collection="mdi"
        name="lock"
        class="size-4" />
      {{ $t('web.LABELS.passphrase_protected') }}
    </div>

    <div
      class="group relative overflow-hidden rounded-lg border-gray-200 bg-white shadow-md dark:border-gray-700 dark:bg-gray-800">
      <!-- Momentum Indicator - Enhanced Animation -->
      <div class="absolute left-0 top-0 h-1.5 w-full overflow-hidden">
        <div
          class="size-full animate-gradient-x bg-200%"
          :class="[
            isInitialView
              ? 'bg-gradient-to-r from-green-400 via-green-500 to-green-400'
              : 'bg-gradient-to-r from-amber-300 via-amber-500 to-amber-300',
          ]">
        </div>
      </div>

      <!-- Initial Success Message - Enhanced with Icon Animation -->
      <div
        v-if="isInitialView"
        class="mb-2 flex items-center gap-2 px-5 pt-4 font-brand text-base">
        <div class="relative">
          <OIcon
            collection="mdi"
            name="check-circle"
            class="size-5 text-green-600 dark:text-green-400"
            aria-hidden="true" />
          <div class="absolute inset-0 size-full rounded-full opacity-50"></div>
        </div>
        <span>{{ $t('web.private.created_success') }}</span>
      </div>

      <!-- Subsequent Message -->
      <div
        class="mb-1 flex items-center gap-2 px-5 pt-4 font-mono text-sm tracking-wide text-gray-500">
        <OIcon
          collection="material-symbols"
          name="key-vertical"
          class="size-4 transition-transform duration-300 group-hover:rotate-12"
          aria-hidden="true" />
        <span
          class="transition-colors group-hover:text-brand-500 dark:group-hover:text-brand-400">
          {{ record.secret_shortkey }}
        </span>
      </div>

      <!-- Secret Link Display with Enhanced Styling -->
      <div
        v-if="!details.show_recipients"
        class="flex items-start px-5 py-3">
        <div class="group/link relative min-w-0 grow">
          <!-- prettier-ignore-attribute class -->
          <textarea
            ref="linkInput"
            readonly
            :value="record.share_url"
            class="w-full resize-none rounded-md border-0 bg-slate-50 px-3 py-2.5 font-mono text-sm text-gray-900 focus:ring-1 focus:ring-brand-500 dark:bg-slate-900 dark:text-gray-100 sm:text-base"
            :aria-label="$t('secret-link')"></textarea>

          <!-- Focus effect overlay -->
          <!-- prettier-ignore-attribute class -->
          <div
            class="pointer-events-none absolute inset-0 rounded-md border border-transparent group-focus-within/link:border-brand-500"></div>
        </div>

        <div class="ml-4 shrink-0">
          <!-- prettier-ignore-attribute class -->
          <button
            @click="copyToClipboard"
            class="inline-flex items-center justify-center rounded-md p-2.5 text-gray-500 transition-all duration-200 hover:bg-gray-100 hover:text-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-brand-400"
            :class="{
              'bg-green-50 text-green-500 dark:bg-green-900/30 dark:text-green-400': copied,
            }">
            <OIcon
              collection="material-symbols"
              :name="copied ? 'check' : 'content-copy-outline'"
              class="size-5" />
            <span class="sr-only">{{ buttonText }}</span>
          </button>
        </div>
      </div>

      <!-- Security Notice with Enhanced Design -->
      <!-- prettier-ignore-attribute class -->
      <div
        v-if="!details.show_recipients"
        class="border-t border-gray-200
          bg-gray-50 px-5 py-3 dark:border-gray-700 dark:bg-gray-900/50">
        <div class="flex items-center text-xs text-gray-500 dark:text-gray-400">
          <OIcon
            collection="material-symbols"
            name="shield-outline"
            class="mr-2 size-4 text-brand-500 transition-transform dark:text-brand-400" />
          <span class="transition-colors group-hover:text-gray-700 dark:group-hover:text-gray-300">
            {{ $t('web.COMMON.share_link_securely') }}
          </span>
        </div>
      </div>

      <!-- Copy Feedback Toast with Enhanced Design -->
      <!-- prettier-ignore-attribute class -->
      <div
        v-if="showToast"
        class="absolute right-4 top-4 flex items-center gap-2 rounded-md
        bg-slate-900 px-3.5 py-2 text-sm text-white shadow-lg transition-all duration-300 dark:bg-slate-700"
        :class="{
          'translate-y-1 opacity-0': !showToast,
          'translate-y-0 opacity-100': showToast,
        }">
        <OIcon
          collection="material-symbols"
          name="check-circle-outline"
          class="size-4 text-green-400" />
        {{ $t('web.COMMON.copied_to_clipboard') }}
      </div>
    </div>
  </div>
</template>

<style scoped>
  .animate-gradient-x {
    animation: gradient-x 10s linear infinite;
  }

  @keyframes gradient-x {
    0% {
      background-position: 0% 0;
    }
    100% {
      background-position: 200% 0;
    }
  }

  .animate-success-ping {
    animation: success-ping 10s cubic-bezier(0, 0, 0.2, 1);
  }

  @keyframes success-ping {
    0% {
      transform: scale(0.5);
      opacity: 0;
    }
    100% {
      transform: scale(1);
      opacity: 1;
    }
  }
</style>
