<script setup lang="ts">
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
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
  const buttonText = computed(() => copied.value ? t('web.STATUS.copied') : t('web.LABELS.copy_to_clipboard') );

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
      class="absolute -top-2 right-3 flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400 font-medium px-2 py-1 rounded-full bg-amber-50 dark:bg-amber-900/30 border border-amber-100 dark:border-amber-800/50 shadow-sm transform transition-transform hover:scale-105">
      <OIcon
        collection=""
        name="mdi-lock"
        class="w-4 h-4" />
      {{ $t('web.LABELS.passphrase_protected') }}
    </div>

    <div
      class="relative overflow-hidden rounded-lg shadow-md bg-white dark:bg-gray-800 dark:border-gray-700 border-gray-200 group">

      <!-- Momentum Indicator - Enhanced Animation -->
      <div class="absolute top-0 left-0 w-full h-1.5 overflow-hidden">
        <div
          class="w-full h-full bg-200% animate-gradient-x"
          :class="[
            isInitialView
              ? 'bg-gradient-to-r from-green-400 via-green-500 to-green-400'
              : 'bg-gradient-to-r from-amber-300 via-amber-500 to-amber-300'
          ]">
        </div>
      </div>

      <!-- Initial Success Message - Enhanced with Icon Animation -->
      <div
        v-if="isInitialView"
        class="flex items-center gap-2 mb-2 px-5 pt-4 text-base font-brand text-green-600 dark:text-green-400">
        <div class="relative">
          <OIcon
            collection="mdi"
            name="check-circle"
            class="size-5 animate-success-ping"
            aria-hidden="true" />
          <div class="absolute inset-0 h-full w-full rounded-full bg-green-400 opacity-50 animate-ping-slow"></div>
        </div>
        <span>{{ $t('web.private.created_success') }}</span>
      </div>

      <!-- Subsequent Message - Enhanced Design -->
      <div
        class="flex items-center gap-2 mb-1 px-5 pt-4 text-sm font-mono text-gray-500 tracking-wide">
        <OIcon
          collection="material-symbols"
          name="key-vertical"
          class="size-4 group-hover:rotate-12 transition-transform duration-300"
          aria-hidden="true" />
        <span class="group-hover:text-brand-500 dark:group-hover:text-brand-400 transition-colors">{{ record.secret_shortkey }}</span>
      </div>

      <!-- Secret Link Display with Enhanced Styling -->
      <div class="flex items-start px-5 py-3">
        <div class="flex-grow min-w-0 group/link relative">
          <textarea
            ref="linkInput"
            readonly
            :value="record.share_url"
            class="w-full bg-slate-50 dark:bg-slate-900 border-0 rounded-md py-2.5 px-3 text-gray-900 font-mono text-sm sm:text-base dark:text-gray-100 focus:ring-1 focus:ring-brand-500 resize-none"
            :aria-label="$t('secret-link')"></textarea>

          <!-- Focus effect overlay -->
          <div class="absolute inset-0 pointer-events-none border border-transparent group-focus-within/link:border-brand-500 rounded-md"></div>
        </div>

        <div class="flex-shrink-0 ml-4">
          <button
            @click="copyToClipboard"
            class="inline-flex items-center justify-center p-2.5 rounded-md text-gray-500 dark:text-gray-400 hover:text-brand-600 dark:hover:text-brand-400 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-all duration-200"
            :class="{ 'text-green-500 dark:text-green-400 bg-green-50 dark:bg-green-900/30': copied }">
            <OIcon
              collection="material-symbols"
              :name="copied ? 'check' : 'content-copy-outline'"
              class="w-5 h-5" />
            <span class="sr-only">{{ buttonText }}</span>
          </button>
        </div>
      </div>

      <!-- Security Notice with Enhanced Design -->
      <div
        class="bg-gray-50 dark:bg-gray-900/50 px-5 py-3 border-t border-gray-200 dark:border-gray-700">
        <div class="flex items-center text-xs text-gray-500 dark:text-gray-400">
          <OIcon
            collection="material-symbols"
            name="shield-outline"
            class="w-4 h-4 mr-2 text-brand-500 dark:text-brand-400 group-hover:scale-110 transition-transform" />
          <span class="group-hover:text-gray-700 dark:group-hover:text-gray-300 transition-colors">{{ $t('web.COMMON.share_link_securely') }}</span>
        </div>
      </div>

      <!-- Copy Feedback Toast with Enhanced Design -->
      <div
        v-if="showToast"
        class="absolute top-4 right-4 px-3.5 py-2 bg-slate-900 dark:bg-slate-700 text-white text-sm rounded-md shadow-lg transform transition-all duration-300 flex items-center gap-2"
        :class="{
          'opacity-0 translate-y-1': !showToast,
          'opacity-100 translate-y-0': showToast,
        }">
        <OIcon
                    collection="material-symbols"
          name="check-circle-outline"
          class="w-4 h-4 text-green-400" />
        {{ $t('web.COMMON.copied_to_clipboard') }}
      </div>
    </div>
  </div>
</template>

<style scoped>
.animate-gradient-x {
  animation: gradient-x 3s linear infinite;
}

@keyframes gradient-x {
  0% {
    background-position: 0% 0;
  }
  100% {
    background-position: 200% 0;
  }
}

.animate-ping-slow {
  animation: ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;
}

@keyframes ping {
  0% {
    transform: scale(0.75);
    opacity: 1;
  }
  75%, 100% {
    transform: scale(1.5);
    opacity: 0;
  }
}

.animate-success-ping {
  animation: success-ping 0.5s cubic-bezier(0, 0, 0.2, 1);
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
