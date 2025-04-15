<!-- src/components/secrets/canonical/SecretDisplayCase.vue -->

<script setup lang="ts">
  import { useClipboard } from '@/composables/useClipboard';
  import { Secret, SecretDetails } from '@/schemas/models';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import BaseSecretDisplay from './BaseSecretDisplay.vue';

  interface Props {
    record: Secret | null;
    details: SecretDetails | null;
    submissionStatus?: {
      status: 'idle' | 'submitting' | 'success' | 'error';
      message?: string;
    };
  }

  const props = defineProps<Props>();
  const { t } = useI18n();

  const alertClasses = computed(() => ({
    'mb-4 p-4 rounded-md': true,
    'bg-branddim-50 text-branddim-700 dark:bg-branddim-900 dark:text-branddim-100':
      props.submissionStatus?.status === 'error',
    'bg-brand-50 text-brand-700 dark:bg-brand-900 dark:text-brand-100':
      props.submissionStatus?.status === 'success',
  }));

  const { isCopied, copyToClipboard } = useClipboard();
  const isCopiedText = computed(() =>
    isCopied ? t('web.STATUS.copied') : t('web.LABELS.copy_to_clipboard')
  );
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

  const closeTruncatedWarning = (event: Event) => {
    const element = event.target as HTMLElement;
    const warning = element.closest('.bg-brandcomp-100');
    if (warning) {
      warning.remove();
      // Announce removal to screen readers
      const announcement = document.createElement('div');
      announcement.setAttribute('role', 'status');
      announcement.setAttribute('aria-live', 'polite');
      announcement.textContent = t('warning-dismissed');
      document.body.appendChild(announcement);
      setTimeout(() => announcement.remove(), 1000);
    }
  };
</script>

<template>
  <BaseSecretDisplay>
    <!-- Alert display -->
    <div
      v-if="submissionStatus?.status === 'error' || submissionStatus?.status === 'success'"
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
              submissionStatus.message || (submissionStatus.status === 'error' ? 'An error occurred' : 'Success')
            }}
          </p>
        </div>
      </div>
    </div>

    <template #content>
      <div class="relative">
        <label
          :for="'secret-content-' + record?.identifier"
          class="sr-only">
          {{ $t('secret-content') }}
        </label>
        <textarea
          v-if="record?.secret_value"
          :id="'secret-content-' + record?.identifier"
          class="w-full resize-none rounded-md border border-gray-300 bg-gray-100 px-3 py-2
            font-mono text-base leading-[1.2] tracking-wider
            focus:outline-none focus:ring-2 focus:ring-brand-500
            dark:border-gray-600 dark:bg-gray-800 dark:text-white"
          readonly
          :rows="details?.display_lines ?? 4"
          :value="record?.secret_value"
          :aria-label="$t('secret-content')"></textarea>
        <div
          v-else
          class="text-red-500 dark:text-red-400"
          role="alert">
          {{ $t('secret-value-not-available') }}
        </div>
      </div>
    </template>

    <template #warnings>
      <div>
        <p
          v-if="!record?.verification"
          class="text-sm text-branddim-500 dark:text-gray-500"
          role="alert"
          aria-live="polite">
          ({{ $t('web.COMMON.careful_only_see_once') }})
        </p>

        <div
          v-if="record?.is_truncated"
          class="border-l-4 border-brandcomp-500 bg-brandcomp-100 p-4
          text-sm text-brandcomp-700 dark:bg-brandcomp-800 dark:text-brandcomp-200"
          role="alert"
          aria-live="polite">
          <button
            type="button"
            class="float-right hover:text-brandcomp-900
              focus:outline-none focus:ring-2 focus:ring-brandcomp-500 dark:hover:text-brandcomp-50"
            @click="closeTruncatedWarning"
            :aria-label="$t('dismiss-truncation-warning')">
            <span aria-hidden="true">&times;</span>
          </button>
          <strong>{{ $t('web.COMMON.warning') }}</strong>
          {{ $t('web.shared.secret_was_truncated') }} {{ record.original_size }}.
        </div>
      </div>
    </template>

    <template #cta>
      <div class="mt-4">
        <button
          @click="copySecretContent"
          :title="isCopiedText"
          class="inline-flex items-center justify-center rounded-md bg-brand-500 px-4 py-2.5
            text-sm font-medium text-brand-50 shadow-sm transition-colors duration-150 ease-in-out
            hover:bg-brand-600 hover:shadow
            focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
            disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-700 dark:text-brand-100 dark:hover:bg-brand-600"
          :aria-label="isCopiedText"
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
          <span>{{ isCopiedText }}</span>
        </button>

        <!-- Navigation -->
        <div
          v-if="!record?.verification"
          class="mt-24 text-center text-sm text-slate-500 dark:text-slate-400 italic">
          <p>
            {{ $t('you-can-safely-close-this-tab') }}
          </p>
        </div>
        <div
          v-else
          class="mt-16">
          <a
            href="/signin"
            class="block w-full rounded-md border border-slate-500 bg-white px-4 py-2 text-center text-slate-500 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-500 focus:ring-offset-2 dark:border-slate-400 dark:bg-gray-800 dark:text-slate-400 dark:hover:bg-gray-700"
            :aria-label="$t('sign-in-to-your-account')">
            {{ $t('web.COMMON.login_to_your_account') }}
          </a>
        </div>
      </div>
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
