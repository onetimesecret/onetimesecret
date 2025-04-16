/** eslint-disable tailwindcss/classnames-order */
<!-- src/components/secrets/metadata/BurnButtonForm.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useMetadata } from '@/composables/useMetadata';
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import { ref } from 'vue';

  interface Props {
    record: Metadata;
    details: MetadataDetails;
  }

  const props = defineProps<Props>();

  const { burn, isLoading, passphrase } = useMetadata(props.record.key);

  const showConfirmation = ref(false);
  const isHovered = ref(false);

  // Add hover effect for the burn icon
  const startBounce = () => {
    isHovered.value = true;
    setTimeout(() => {
      isHovered.value = false;
    }, 1000);
  };

  // Trigger bounce animation periodically
  setInterval(startBounce, 5000);
</script>

<template>
  <div
    v-if="!record.is_destroyed"
    class="mx-auto w-full max-w-md">
    <form
      class="space-y-6"
      @submit.prevent>
      <!-- Initial Burn Button with Enhanced Design -->
      <!-- prettier-ignore-attribute class -->
      <button
        v-if="!showConfirmation"
        type="button"
        @click="showConfirmation = true"
        class="group flex w-full items-center justify-center gap-3 rounded-lg bg-gradient-to-r
        from-brand-500 to-brand-600 px-6 py-3 text-base
        font-medium text-white shadow-sm transition-all duration-200
        hover:from-brand-600 hover:to-brand-700 hover:shadow
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        disabled:opacity-70 dark:focus:ring-offset-gray-900"
        :disabled="isLoading"
        :aria-label="$t('web.COMMON.burn_this_secret_aria')"
        :aria-busy="isLoading"
        role="button">
        <OIcon
          collection=""
          name="heroicons-fire-20-solid"
          class="size-5 transition-all group-hover:rotate-12 group-hover:scale-125"
          aria-hidden="true" />
        <span>{{ $t('web.COMMON.burn_this_secret') }}</span>
      </button>

      <!-- Confirmation Dialog with Enhanced Design -->
      <!-- prettier-ignore-attribute class -->
      <div
        v-else
        role="alertdialog"
        aria-labelledby="burn-dialog-title"
        aria-describedby="burn-dialog-desc"
        class="rounded-xl border border-gray-200
          bg-white p-6 shadow-lg dark:border-gray-700 dark:bg-gray-800">
        <div class="space-y-4 text-center">
          <div class="relative mx-auto size-16">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle-20-solid"
              class="mx-auto text-yellow-500"
              size="16" />
            <div class="absolute rounded-full opacity-30"></div>
          </div>
          <h3
            id="burn-dialog-title"
            class="text-xl font-bold text-gray-900 dark:text-white">
            {{ $t('web.COMMON.burn_confirmation_title') }}
          </h3>
          <p
            id="burn-dialog-desc"
            class="text-sm text-gray-600 dark:text-gray-300">
            {{ $t('web.COMMON.burn_confirmation_message') }}
          </p>
        </div>

        <div
          v-if="details.has_passphrase"
          class="mt-6">
          <!-- prettier-ignore-attribute class -->
          <label
            for="passField"
            class="mb-2 flex items-center gap-2
              text-sm font-medium text-gray-700 dark:text-gray-300">
            <OIcon
              collection="mdi"
              name="lock"
              class="size-4 text-amber-500 dark:text-amber-400" />
            {{ $t('web.LABELS.passphrase_protected') }}
          </label>
          <div class="relative">
            <!-- prettier-ignore-attribute class -->
            <input
              type="password"
              v-model="passphrase"
              id="passField"
              autocomplete="current-password"
              :placeholder="$t('web.COMMON.enter_passphrase_here')"
              class="w-full rounded-lg border border-gray-300
                bg-white py-2.5 pl-10 pr-4 text-gray-900 shadow-sm
                focus:border-transparent focus:ring-2 focus:ring-brand-500
                dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
          </div>
        </div>

        <div class="mt-6 flex flex-col justify-end gap-3 sm:flex-row">
          <!-- prettier-ignore-attribute class -->
          <button
            type="button"
            @click="showConfirmation = false"
            class="over:bg-gray-50 ark:border-gray-600 rounded-lg border border-gray-300 bg-white
              px-4 py-2.5 text-base font-medium text-gray-700
              transition-colors duration-200 focus:outline-none focus:ring-2
              focus:ring-brand-500 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
            {{ $t('web.LABELS.cancel') }}
          </button>
          <!-- prettier-ignore-attribute class -->
          <button
            type="submit"
            @click="burn"
            :disabled="isLoading"
            class="flex items-center gap-2 rounded-lg
              bg-gradient-to-r from-brand-500 to-brand-600 px-4 py-2.5
              text-base font-medium text-white shadow-sm transition-all duration-200
              hover:from-brand-600 hover:to-brand-700 hover:shadow
              focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:opacity-50">
            <OIcon
              collection="material-symbols"
              name="local-fire-department-rounded"
              class="size-4" />
            <span>{{ $t('web.COMMON.confirm_burn') }}</span>
          </button>
        </div>
      </div>
    </form>
  </div>
</template>

<style scoped></style>
