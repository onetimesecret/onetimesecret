<script setup lang="ts">
  import BaseSecretDisplay from '@/components/secrets/branded/BaseSecretDisplay.vue';
  import { useClipboard } from '@/composables/useClipboard';
  import { useProductIdentity } from '@/stores/identityStore';
  import { Secret, SecretDetails, brandSettingschema } from '@/schemas/models';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';

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
  const { t } = useI18n();

  const productIdentity = useProductIdentity();
  const brandSettings = productIdentity.brand; // Not reactive
  const defaultBranding = brandSettingschema.parse({});
  const safeBrandSettings = computed(() =>
    brandSettings ? brandSettingschema.parse(brandSettings) : defaultBranding
  );
  const cornerStyle = computed(() => {
    switch (brandSettings?.corner_style) {
      case 'rounded': return 'rounded-lg';
      case 'pill': return 'rounded-2xl'; // Changed from rounded-full for textarea
      case 'square': return 'rounded-none';
      default: return 'rounded-lg';
    }
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
  const isCopiedText = computed(() => isCopied ? t('copied') : t('copy_to_clipboard') );

  // Prepare the standardized path to the logo image.
  // Note that the file extension needs to be present but is otherwise not used.
  const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>

<template>
  <BaseSecretDisplay
    :default-title="$t('you-have-a-message')"
    :instructions="brandSettings?.instructions_pre_reveal"
    :domain-branding="safeBrandSettings">
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
              (submissionStatus.status === 'error' ? $t('an-error-occurred') : $t('web.STATUS.success'))
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
            :class="{
              'rounded-lg': brandSettings?.corner_style === 'rounded',
              'rounded-full': brandSettings?.corner_style === 'pill',
              'rounded-none': brandSettings?.corner_style === 'square',
            }"
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
              :alt="$t('brand-logo')"
              class="size-16 object-contain"
              :class="{
                'rounded-lg': brandSettings?.corner_style === 'rounded',
                'rounded-full': brandSettings?.corner_style === 'pill',
                'rounded-none': brandSettings?.corner_style === 'square',
              }"
              @error="handleImageError" />
          </div>
        </router-link>
      </div>
    </template>

    <template #content>
      <div class="relative size-full p-0">
        <div :class="[cornerStyle, 'size-full overflow-hidden bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-600']">
          <label
            :for="'secret-content-' + record?.identifier"
            class="sr-only">
            {{ $t('secret-content') }}
          </label>
          <textarea
            :id="'secret-content-' + record?.identifier"
            class="block size-full min-h-32 resize-none border-none bg-transparent font-mono text-base focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-white sm:min-h-36"
            readonly
            :rows="details?.display_lines ?? 4"
            :value="record?.secret_value"
            :aria-label="$t('secret-content')"
            ref="secretContent"></textarea>
        </div>
      </div>
    </template>

    <template #action-button>
      <button
        @click="copySecretContent"
        :title="isCopiedText"
        class="inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium text-brand-700 shadow-sm transition-colors duration-150 ease-in-out hover:shadow focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:text-brand-100"
        :class="[
          {
            'font-sans': brandSettings?.font_family === 'sans',
            'font-serif': brandSettings?.font_family === 'serif',
            'font-mono': brandSettings?.font_family === 'mono'
          }
        ]"
        :style="{
          backgroundColor: brandSettings?.primary_color ??' #dc4a22',
          color: (brandSettings?.button_text_light ?? true) ? '#ffffff' : '#000000'
        }"
        aria-live="polite"
        :aria-label="isCopied ? $t('secret-copied-to-clipboard') : $t('copy-secret-to-clipboard')"
        :aria-pressed="isCopied">
        <svg
          v-if="!isCopied"
          xmlns="http://www.w3.org/2000/svg"
          class="mr-2 size-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        <svg
          v-else
          xmlns="http://www.w3.org/2000/svg"
          class="mr-2 size-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7" />
        </svg>
        <span>{{ isCopied ? $t('copied') : $t('copy_to_clipboard') }}</span>
      </button>
    </template>
  </BaseSecretDisplay>
</template>

<style scoped>
  /* Ensure focus outline is visible in all color schemes */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
