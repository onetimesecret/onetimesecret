<!-- src/apps/workspace/components/domains/PrivacyDefaultsBar.vue -->

<script setup lang="ts">
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import PrivacyDefaultsModal from './PrivacyDefaultsModal.vue';
  import type { BrandSettings } from '@/schemas/models';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
  import { WindowService } from '@/services/window.service';

  const { t } = useI18n();

  const props = withDefaults(
    defineProps<{
      brandSettings: BrandSettings;
      isLoading?: boolean;
      /** Whether this is the canonical (default) domain */
      isCanonical?: boolean;
      /** Whether the settings are editable (false for canonical domain) */
      isEditable?: boolean;
    }>(),
    {
      isLoading: false,
      isCanonical: false,
      isEditable: true,
    }
  );

  const emit = defineEmits<{
    (e: 'update', settings: Partial<BrandSettings>): void;
    (e: 'chip-click', setting: 'ttl' | 'passphrase' | 'notify'): void;
  }>();

  const isModalOpen = ref(false);
  const { formatDuration } = usePrivacyOptions();

  // Get global defaults for canonical domain display
  const secretOptions = WindowService.get('secret_options');
  const globalDefaultTtl = secretOptions?.default_ttl ?? 604800;
  const globalPassphraseRequired = secretOptions?.passphrase?.required ?? false;

  const openModal = () => {
    if (!props.isEditable) return;
    isModalOpen.value = true;
  };

  const closeModal = () => {
    isModalOpen.value = false;
  };

  const handleSave = (settings: Partial<BrandSettings>) => {
    emit('update', settings);
    closeModal();
  };

  const handleChipClick = (setting: 'ttl' | 'passphrase' | 'notify') => {
    if (!props.isEditable) return;
    emit('chip-click', setting);
    openModal();
  };

  // Computed display values - use global defaults for canonical domain
  const ttlDisplay = computed(() => {
    if (props.isCanonical) {
      return formatDuration(globalDefaultTtl);
    }
    if (props.brandSettings.default_ttl) {
      return formatDuration(props.brandSettings.default_ttl);
    }
    return t('web.domains.global_default');
  });

  const passphraseDisplay = computed(() => {
    if (props.isCanonical) {
      return globalPassphraseRequired
        ? t('web.domains.required')
        : t('web.domains.optional');
    }
    return props.brandSettings.passphrase_required
      ? t('web.domains.required')
      : t('web.domains.optional');
  });

  const notifyDisplay = computed(() => {
    if (props.isCanonical) {
      return t('web.domains.disabled');
    }
    return props.brandSettings.notify_enabled
      ? t('web.domains.enabled')
      : t('web.domains.disabled');
  });

  // For canonical domain, never show custom indicator
  const hasCustomSettings = computed(() => {
    if (props.isCanonical) return false;
    return (
      props.brandSettings.default_ttl !== null ||
      props.brandSettings.passphrase_required === true ||
      props.brandSettings.notify_enabled === true
    );
  });

  // Check if specific setting is active (for styling)
  const isTtlActive = computed(() => {
    if (props.isCanonical) return true;
    return props.brandSettings.default_ttl !== null;
  });

  const isPassphraseActive = computed(() => {
    if (props.isCanonical) return globalPassphraseRequired;
    return props.brandSettings.passphrase_required === true;
  });

  const isNotifyActive = computed(() => {
    if (props.isCanonical) return false;
    return props.brandSettings.notify_enabled === true;
  });

  // Interactive chip classes
  const interactiveChipClasses = computed(() =>
    props.isEditable
      ? 'cursor-pointer hover:ring-2 hover:ring-brand-500/50 focus:outline-none focus:ring-2 focus:ring-brand-500'
      : 'cursor-default'
  );
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
          <button
            type="button"
            :disabled="!isEditable"
            :tabindex="isEditable ? 0 : -1"
            :aria-label="isEditable ? t('web.domains.edit_ttl') : undefined"
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset transition-shadow"
            :class="[
              isTtlActive
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20',
              interactiveChipClasses
            ]"
            @click="handleChipClick('ttl')">
            <OIcon
              collection="mdi"
              name="timer-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.ttl_short') }}: {{ ttlDisplay }}</span>
          </button>

          <!-- Passphrase Badge -->
          <button
            type="button"
            :disabled="!isEditable"
            :tabindex="isEditable ? 0 : -1"
            :aria-label="isEditable ? t('web.domains.edit_passphrase') : undefined"
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset transition-shadow"
            :class="[
              isPassphraseActive
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20',
              interactiveChipClasses
            ]"
            @click="handleChipClick('passphrase')">
            <OIcon
              collection="mdi"
              name="key-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.passphrase_short') }}: {{ passphraseDisplay }}</span>
          </button>

          <!-- Notify Badge -->
          <button
            type="button"
            :disabled="!isEditable"
            :tabindex="isEditable ? 0 : -1"
            :aria-label="isEditable ? t('web.domains.edit_notify') : undefined"
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium ring-1 ring-inset transition-shadow"
            :class="[
              isNotifyActive
                ? 'bg-brand-50 text-brand-700 ring-brand-600/20 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                : 'bg-gray-50 text-gray-600 ring-gray-500/10 dark:bg-gray-700/50 dark:text-gray-400 dark:ring-gray-500/20',
              interactiveChipClasses
            ]"
            @click="handleChipClick('notify')">
            <OIcon
              collection="mdi"
              name="email-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ t('web.domains.notify_short') }}: {{ notifyDisplay }}</span>
          </button>

          <!-- Custom Settings Indicator (only for custom domains) -->
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

          <!-- Global Defaults Indicator (for canonical domain) -->
          <span
            v-if="isCanonical"
            class="inline-flex items-center gap-1 rounded-md bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 dark:bg-gray-700 dark:text-gray-400 dark:ring-gray-500/20">
            <OIcon
              collection="mdi"
              name="earth"
              class="size-3.5"
              aria-hidden="true" />
            {{ t('web.domains.global_defaults') }}
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

      <!-- Right: Edit Button (only shown for custom domains) -->
      <button
        v-if="isEditable"
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
