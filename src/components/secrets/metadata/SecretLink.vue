<!-- src/components/secrets/metadata/SecretLink.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import { ref } from 'vue';

  interface Props {
    record: Metadata;
    details: MetadataDetails;
    isInitialView: boolean;
  }

  defineProps<Props>();

  const linkInput = ref<HTMLInputElement>();
</script>

<template>
  <div>
    <h1
      id="secret-header"
      class="sr-only">
      {{ $t('web.LABELS.secret_link') }}
    </h1>

    <!-- Passphrase Indicator -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="details?.has_passphrase"
      class="flex items-center gap-2 rounded-full
        border border-amber-100 bg-amber-50 px-2 py-1
        text-sm font-medium text-amber-600 shadow-sm transition-transform
        dark:border-amber-800/50 dark:bg-amber-900/30 dark:text-amber-400">
      <OIcon
        collection="mdi"
        name="lock"
        class="size-4" />
      {{ $t('web.LABELS.passphrase_protected') }}
    </div>

    <!-- prettier-ignore-attribute class -->
    <div
      class="group relative overflow-hidden rounded-lg
        border-gray-200 bg-white shadow-md
        dark:border-gray-700 dark:bg-gray-800">
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
      <!-- prettier-ignore-attribute class -->
      <div
        class="mb-1 flex items-center gap-2 px-5 pt-4
          font-mono text-sm tracking-wide text-gray-500">
        <OIcon
          collection="material-symbols"
          name="key-vertical"
          class="size-4 transition-transform duration-300 group-hover:rotate-12"
          aria-hidden="true" />
        <span class="transition-colors group-hover:text-brand-500 dark:group-hover:text-brand-400">
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
            class="w-full resize-none rounded-md
              border-0 bg-slate-50 px-3 py-2.5 font-mono text-sm text-gray-900
              focus:ring-1 focus:ring-green-500
              dark:bg-slate-900 dark:text-gray-100 sm:text-base"
            :aria-label="$t('secret-link')"></textarea>
        </div>

        <div class="ml-4 shrink-0">
          <CopyButton
                class="ml-auto transition-transform hover:scale-105"
                :text="record.share_url" />
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
