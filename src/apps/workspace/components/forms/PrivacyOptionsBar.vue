<!-- src/apps/workspace/components/forms/PrivacyOptionsBar.vue -->

<script setup lang="ts">
  /**
   * Privacy Options Bar
   *
   * Responsive privacy controls for the workspace secret form.
   * - Desktop (sm+): Inline TtlSelector and PassphraseInput chips
   * - Mobile (<sm): Single button that opens PrivacyOptionsSheet
   */
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useMediaQuery } from '@vueuse/core';
  import { storeToRefs } from 'pinia';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import TtlSelector from './privacy-options/TtlSelector.vue';
  import PassphraseInput from './privacy-options/PassphraseInput.vue';
  import PrivacyOptionsSheet from './privacy-options/PrivacyOptionsSheet.vue';

  const { t } = useI18n();

  // Disable auto attribute inheritance since we have multiple root nodes
  // (main div + PrivacyOptionsSheet which renders a Dialog via Teleport)
  defineOptions({
    inheritAttrs: false,
  });

  const props = withDefaults(
    defineProps<{
      /** Current TTL value in seconds */
      currentTtl: number;
      /** Current passphrase value */
      currentPassphrase: string;
      /** Whether form is submitting */
      isSubmitting?: boolean;
    }>(),
    {
      isSubmitting: false,
    }
  );

  const emit = defineEmits<{
    (e: 'update:ttl', value: number): void;
    (e: 'update:passphrase', value: string): void;
  }>();

  // Responsive breakpoint detection
  const isMobile = useMediaQuery('(max-width: 639px)');
  const showMobileSheet = ref(false);

  const { formatDuration } = usePrivacyOptions();

  // Get passphrase config for minLength prop
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);
  const minPassphraseLength = computed(
    () => secret_options.value?.passphrase?.minimum_length || 0
  );

  // Display values for mobile button
  const ttlDisplay = computed(() => formatDuration(props.currentTtl));
  const hasPassphrase = computed(() => !!props.currentPassphrase);
</script>

<template>
  <div
    v-bind="$attrs"
    class="relative z-10 rounded-lg border border-gray-200/60 bg-white/80 px-4 py-3 shadow-sm backdrop-blur-sm
      dark:border-gray-700/60 dark:bg-gray-800/80 sm:px-6">
    <div class="flex flex-wrap items-center gap-4">
      <!-- Privacy Options Label -->
      <div class="flex items-center gap-2">
        <OIcon
          collection="material-symbols"
          name="shield-outline"
          class="size-5 text-gray-500 dark:text-gray-400"
          aria-hidden="true" />
        <span class="text-sm font-medium font-brand text-gray-700 dark:text-gray-300">
          {{ t('web.COMMON.secret_privacy_options') }}
        </span>
      </div>

      <!-- Desktop: Inline chip components -->
      <div
        v-if="!isMobile"
        class="flex flex-wrap items-center gap-2">
        <TtlSelector
          :model-value="currentTtl"
          :disabled="isSubmitting"
          @update:model-value="emit('update:ttl', $event)" />
        <PassphraseInput
          :model-value="currentPassphrase"
          :min-length="minPassphraseLength"
          :disabled="isSubmitting"
          @update:model-value="emit('update:passphrase', $event)" />
      </div>

      <!-- Mobile: Summary button that opens bottom sheet -->
      <button
        v-else
        type="button"
        :disabled="isSubmitting"
        class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs
          font-medium ring-1 ring-inset transition-all
          bg-brand-50 text-brand-700 ring-brand-600/20
          hover:bg-brand-100 hover:ring-brand-600/30
          focus:outline-none focus:ring-2 focus:ring-brand-500
          dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30
          dark:hover:bg-brand-900/50
          disabled:cursor-not-allowed disabled:opacity-50"
        @click="showMobileSheet = true">
        <span>{{ ttlDisplay }}</span>
        <span
          v-if="hasPassphrase"
          class="flex items-center justify-center rounded bg-brand-200/60 p-0.5
            dark:bg-brand-700/40">
          <OIcon
            collection="mdi"
            name="key"
            class="size-3"
            aria-hidden="true" />
        </span>
        <OIcon
          collection="heroicons"
          name="chevron-right"
          class="size-3"
          aria-hidden="true" />
      </button>
    </div>
  </div>

  <!-- Mobile bottom sheet -->
  <PrivacyOptionsSheet
    v-model="showMobileSheet"
    :current-ttl="currentTtl"
    :current-passphrase="currentPassphrase"
    :disabled="isSubmitting"
    @update:ttl="emit('update:ttl', $event)"
    @update:passphrase="emit('update:passphrase', $event)" />
</template>
