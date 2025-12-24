<!-- src/apps/workspace/components/domains/PrivacyDefaultsBar.vue -->

<script setup lang="ts">
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import PrivacyDefaultsModal from './PrivacyDefaultsModal.vue';
  import type { BrandSettings } from '@/schemas/models';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';

  const { t } = useI18n();

  const props = defineProps<{
    brandSettings: BrandSettings;
    isLoading?: boolean;
  }>();

  const emit = defineEmits<{
    (e: 'update', settings: Partial<BrandSettings>): void;
  }>();

  const isModalOpen = ref(false);
  const { formatDuration } = usePrivacyOptions();

  const openModal = () => {
    isModalOpen.value = true;
  };

  const closeModal = () => {
    isModalOpen.value = false;
  };

  const handleSave = (settings: Partial<BrandSettings>) => {
    emit('update', settings);
    closeModal();
  };

  // Computed display values
  const ttlDisplay = computed(() => {
    if (props.brandSettings.default_ttl) {
      return formatDuration(props.brandSettings.default_ttl);
    }
    return t('web.domains.global_default');
  });

  const passphraseDisplay = computed(() => props.brandSettings.passphrase_required
      ? t('web.domains.required')
      : t('web.domains.optional'));

  const notifyDisplay = computed(() => props.brandSettings.notify_enabled
      ? t('web.domains.enabled')
      : t('web.domains.disabled'));

  const hasCustomSettings = computed(() => (
      props.brandSettings.default_ttl !== null ||
      props.brandSettings.passphrase_required === true ||
      props.brandSettings.notify_enabled === true
    ));
</script>

<template>
  <div
    class="border-b border-gray-200 bg-white px-4 py-3 dark:border-gray-700 dark:bg-gray-800 sm:px-6">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <!-- Left: Privacy Defaults Display -->
      <div class="flex flex-wrap items-center gap-3">
        <div class="flex items-center gap-2">
          <OIcon
            collection="mdi"
            name="shield-lock-outline"
            class="size-5 text-gray-500 dark:text-gray-400"
            :aria-label="t('web.domains.privacy_defaults_icon')" />
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.domains.privacy_defaults') }}:
          </span>
        </div>

        <!-- Privacy chips/badges -->
        <div
          v-if="!isLoading"
          class="flex flex-wrap items-center gap-2">
          <!-- TTL Badge -->
          <span
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset"
            :class="
              brandSettings.default_ttl
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20'
            ">
            <OIcon
              collection="mdi"
              name="timer-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.ttl_short') }}: {{ ttlDisplay }}</span>
          </span>

          <!-- Passphrase Badge -->
          <span
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset"
            :class="
              brandSettings.passphrase_required
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20'
            ">
            <OIcon
              collection="mdi"
              name="key-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.passphrase_short') }}: {{ passphraseDisplay }}</span>
          </span>

          <!-- Notify Badge -->
          <span
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset"
            :class="
              brandSettings.notify_enabled
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20'
            ">
            <OIcon
              collection="mdi"
              name="email-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.notify_short') }}: {{ notifyDisplay }}</span>
          </span>

          <!-- Custom Settings Indicator -->
          <span
            v-if="hasCustomSettings"
            class="inline-flex items-center gap-1 rounded-md bg-amber-50 px-2 py-1 text-xs font-medium text-amber-700 ring-1 ring-inset ring-amber-600/20 dark:bg-amber-900/30 dark:text-amber-300 dark:ring-amber-400/30">
            <OIcon
              collection="mdi"
              name="star-outline"
              class="size-3.5"
              aria-hidden="true" />
            {{ t('web.domains.custom') }}
          </span>
        </div>

        <!-- Loading skeleton -->
        <div
          v-else
          class="flex gap-2">
          <div
            v-for="i in 3"
            :key="i"
            class="h-6 w-24 animate-pulse rounded-md bg-gray-200 dark:bg-gray-700"></div>
        </div>
      </div>

      <!-- Right: Edit Button -->
      <button
        type="button"
        :disabled="isLoading"
        @click="openModal"
        class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800">
        <OIcon
          collection="mdi"
          name="pencil"
          class="size-4"
          aria-hidden="true" />
        {{ t('web.domains.edit_defaults') }}
      </button>
    </div>

    <!-- Modal -->
    <PrivacyDefaultsModal
      :is-open="isModalOpen"
      :brand-settings="brandSettings"
      @close="closeModal"
      @save="handleSave" />
  </div>
</template>
