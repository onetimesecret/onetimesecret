<!-- src/components/secrets/branded/SecretDisplayCase.vue -->

<script setup lang="ts">
  import BaseSecretDisplay from '@/components/secrets/branded/BaseSecretDisplay.vue';
  import { useClipboard } from '@/composables/useClipboard';
  import { useProductIdentity } from '@/stores/identityStore';
  import { Secret, SecretDetails, brandSettingschema } from '@/schemas/models';
  import {
    CornerStyle,
    FontFamily,
    cornerStyleClasses,
    fontFamilyClasses
  } from '@/schemas/models/domain/brand';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';


const { t } = useI18n();
  interface Props {
    record: Secret | null;
    details: SecretDetails | null;
    domainId: string;
    submissionStatus?: {
      status: 'idle' | 'submitting' | 'success' | 'error';
      message?: string;
    };
  }

  const props = defineProps<Props>();
  const i18n = useI18n();
  const { t } = i18n;

  const isRevealed = computed(() => !!props.record?.secret_value && props.record.secret_value !== '');

  const productIdentity = useProductIdentity();
  const brandSettings = productIdentity.brand; // Not reactive
  const defaultBranding = brandSettingschema.parse({});
  const safeBrandSettings = computed(() =>
    brandSettings ? brandSettingschema.parse(brandSettings) : defaultBranding
  );

  const cornerClass = computed(() => {
    const style = safeBrandSettings.value?.corner_style as CornerStyle | undefined;
    return cornerStyleClasses[style ?? CornerStyle.ROUNDED];
  });

  const fontFamilyClass = computed(() => {
    const font = safeBrandSettings.value?.font_family as FontFamily | undefined;
    return fontFamilyClasses[font ?? FontFamily.SANS];
  });

  const alertClasses = computed(() => ({
    'mb-4 p-4 rounded-md': true,
    'bg-branddim-50 text-branddim-700 dark:bg-branddim-900 dark:text-branddim-100':
      props.submissionStatus?.status === 'error',
    'bg-brand-50 text-brand-700 dark:bg-brand-900 dark:text-brand-100':
      props.submissionStatus?.status === 'success',
  }));


  const hasImageError = ref(false);
  const { isCopied, copyToClipboard } = useClipboard();

  const logoAriaLabel = hasImageError.value ? t('default-logo-icon') : t('brand-logo')
  const copySecretContent = async () => {
    if (props.record?.secret_value === undefined) {
      return;
    }

    await copyToClipboard(props.record?.secret_value);

    // Announce copy success to screen readers
    const announcement = document.createElement('div');
    announcement.setAttribute('role', 'status');
    announcement.setAttribute('aria-live', 'polite');
    announcement.textContent = t('secret-content-copied-to-clipboard');
    document.body.appendChild(announcement);
    setTimeout(() => announcement.remove(), 1000);
  };

  const handleImageError = () => {
    hasImageError.value = true;
  };
  const isCopiedText = computed(() => isCopied ? t('web.STATUS.copied') : t('web.LABELS.copy_to_clipboard') );

  // Prepare the standardized path to the logo image.
  // Note that the file extension needs to be present but is otherwise not used.
  const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>

<template>
  <!-- Updated -->
  <BaseSecretDisplay
    :default-title="t('you-have-a-message')"
    :preview-i18n="i18n"
    :domain-branding="safeBrandSettings"
    :corner-class="cornerClass"
    :font-class="fontFamilyClass"
    :is-revealed="isRevealed">
    <!-- Alert display -->
    <div
      v-if="
        submissionStatus?.status === 'error' || submissionStatus?.status === 'success'
      "
      :class="alertClasses"
      role="alert"
      aria-live="polite">
      <div class="flex">
        <div class="shrink-0">
          <svg
            v-if="submissionStatus.status === 'error'"
            class="size-5"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
              clip-rule="evenodd" />
          </svg>
          <svg
            v-else
            class="size-5"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
              clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm">
            {{
              submissionStatus.message ||
                (submissionStatus.status === 'error' ? t('an-error-occurred') : t('web.STATUS.success'))
            }}
          </p>
        </div>
      </div>
    </div>

    <template #logo>
      <!-- Brand Icon -->
      <div class="relative mx-auto sm:mx-0">
        <router-link to="/">
          <div
            :class="[cornerClass]"
            class="flex size-14 items-center justify-center bg-gray-100 dark:bg-gray-700 sm:size-16"
            role="img"
            :aria-label="logoAriaLabel">
            <!-- Default lock icon -->
            <svg
              v-if="!logoImage || hasImageError"
              class="size-8 text-gray-400 dark:text-gray-500"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>

            <!-- Logo -->
            <img
              v-if="logoImage && !hasImageError"
              :src="logoImage"
              :alt="t('brand-logo')"
              class="size-16 object-contain"
              :class="[cornerClass]"
              @error="handleImageError" />
          </div>
        </router-link>
      </div>
    </template>

<style scoped>
  /* Ensure focus outline is visible in all color schemes */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
