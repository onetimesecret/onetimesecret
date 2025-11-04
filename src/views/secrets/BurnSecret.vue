<!-- src/views/secrets/BurnSecret.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useMetadata } from '@/composables/useMetadata';
  import { onMounted } from 'vue';

  interface Props {
    metadataKey: string;
  }
  const props = defineProps<Props>();

  const { record, details, isLoading, passphrase, fetch, burn } = useMetadata(props.metadataKey);

  onMounted(() => {
    fetch();
  });
</script>

<template>
  <div>
    <!-- Loading State -->
    <div
      v-if="isLoading"
      class="animate-pulse space-y-4"
      role="status"
      aria-live="polite"
      aria-busy="true">
      <div class="h-20 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      <div class="mx-auto h-10 w-3/4 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      <span class="sr-only">{{ $t('web.COMMON.loading') }}</span>
    </div>

    <!-- Destroyed/Invalid State -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-else-if="!record || record?.is_destroyed"
      role="alert"
      class="space-y-4 rounded-lg
        border-l-4 border-red-500
        bg-red-50 p-5 shadow-sm
        dark:border-red-600 dark:bg-red-900/30">
      <!-- Status Message -->
      <div class="flex items-center space-x-3">
        <OIcon
          collection="heroicons"
          name="exclamation-circle-16-solid"
          class="size-6 text-red-500 dark:text-red-400" />
        <p class="text-base font-medium text-red-800 dark:text-red-200">
          <template v-if="record?.is_received">
            {{ $t('viewed-on-record-received', [record?.received]) }}
          </template>
          <template v-else-if="record?.is_burned">
            {{ $t('deleted-on-record-burned', [record?.burned]) }}
          </template>
          <template v-else> {{ $t('permanently-deleted') }} </template>
        </p>
      </div>

      <!-- Action Buttons -->
      <div class="flex flex-col gap-3 sm:flex-row">
        <!-- prettier-ignore-attribute class -->
        <router-link
          v-if="record?.metadata_path"
          :to="{ name: 'Receipt link', params: { metadataKey: record.identifier } }"
          class="flex-1 rounded-lg
            bg-white px-4 py-2.5 text-center font-brand font-medium
            text-gray-700 shadow-sm transition
            hover:bg-gray-200
            focus:outline-none focus:ring-2 focus:ring-red-500 dark:bg-gray-700
            dark:text-gray-200 dark:hover:bg-gray-600"
          :aria-label="$t('back-to-details')">
          {{ $t('back-to-details') }}
        </router-link>
        <!-- prettier-ignore-attribute class -->
        <router-link
          to="/"
          class="flex-1 rounded-lg
            bg-red-600 px-4 py-2.5 text-center font-brand font-medium
            text-white shadow-sm transition
            hover:bg-red-700
            focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2
            dark:bg-red-700 dark:hover:bg-red-600">
          {{ $t('web.LABELS.create_new_secret') }}
        </router-link>
      </div>
    </div>

    <!-- Active Secret State -->
    <div v-else>
      <div class="mb-6">
        <h1
          v-if="details?.has_passphrase"
          class="mt-2 text-2xl font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.COMMON.burn_this_secret_aria') }}
        </h1>
        <h2 class="text-xl text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.secret') }}: {{ record?.secret_shortid }}
        </h2>
      </div>

      <form
        @submit.prevent="burn"
        class="space-y-4">
        <div v-if="details?.has_passphrase">
          <label
            for="passField"
            class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ $t('web.COMMON.enter_passphrase_here') }}
          </label>
          <!-- prettier-ignore-attribute class -->
          <input
            type="password"
            v-model="passphrase"
            id="passField"
            class="w-full rounded-md
              border border-gray-300 bg-white px-3 py-2
              focus:outline-none focus:ring-2 focus:ring-brand-500
              dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200"
            :aria-describedby="details?.has_passphrase ? 'password-hint' : undefined" />
        </div>
        <!-- prettier-ignore-attribute class -->
        <button
          type="submit"
          :disabled="isLoading"
          class="group flex w-full items-center justify-center rounded-md
            bg-yellow-400 px-4 py-2 text-gray-800  duration-200
            hover:bg-yellow-500
            focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2
            dark:focus:ring-offset-gray-800"
          aria-describedby="burn-action-description">
          <OIcon
            collection=""
            name="heroicons-fire-20-solid"
            class="mr-1 size-5 transition-all group-hover:rotate-12 group-hover:scale-125"
            aria-hidden="true" />
          {{ $t('web.COMMON.word_confirm') }}: {{ $t('web.COMMON.burn_this_secret') }}
        </button>
        <!-- prettier-ignore-attribute class -->
        <a
          :href="`/${record?.metadata_path}`"
          class="mx-auto block w-3/4 rounded bg-gray-200 px-4 py-2 text-center
            text-gray-700 transition duration-200 hover:bg-gray-300
            dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600">
          {{ $t('web.COMMON.word_cancel') }}
        </a>
        <div class="py-6"></div>
        <p
          id="burn-action-description"
          class="text-center text-base text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.burn_this_secret_confirm_hint') }}
        </p>
        <div class="my-6 py-12"></div>
      </form>
    </div>
  </div>
</template>
