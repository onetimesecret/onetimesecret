<script setup lang="ts">
  import { useMetadata } from '@/composables/useMetadata';
  import { onMounted } from 'vue';

  interface Props {
    metadataKey: string;
  }
  const props = defineProps<Props>();

  const { record, details, isLoading, passphrase, fetch, burn } = useMetadata(
    props.metadataKey
  );

  onMounted(() => {
    fetch();
  });
</script>

<template>
  <div>
    <!-- Loading State -->
    <div v-if="isLoading"
         class="animate-pulse space-y-4">
      <div class="h-20 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-10 mx-auto w-3/4 rounded-lg bg-gray-200 dark:bg-gray-700"></div>
    </div>

    <!-- Destroyed/Invalid State -->
    <div v-else-if="!record || record?.is_destroyed"
         role="alert"
         class="space-y-4 rounded-lg border-l-4 border-red-500 bg-red-50 p-5 shadow-sm dark:border-red-600 dark:bg-red-900/30">
      <!-- Status Message -->
      <div class="flex items-center space-x-3">
        <svg class="size-6 text-red-500 dark:text-red-400"
             fill="currentColor"
             viewBox="0 0 20 20">
          <path fill-rule="evenodd"
                d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" />
        </svg>
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
        <a v-if="record?.metadata_path"
           :href="record.metadata_path"
           class="flex-1 rounded-lg bg-white px-4 py-2.5 text-center font-brand font-medium text-gray-700 shadow-sm transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-red-500 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700">
          {{ $t('back-to-details') }}
        </a>
        <router-link to="/"
                     class="flex-1 rounded-lg bg-red-600 px-4 py-2.5 text-center font-brand font-medium text-white shadow-sm transition hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:bg-red-700 dark:hover:bg-red-600">
          {{ $t('web.LABELS.create_new_secret') }}
        </router-link>
      </div>
    </div>

    <!-- Active Secret State -->
    <div v-else>
      <div class="mb-6">
        <span class="text-lg text-gray-600 dark:text-gray-400">{{ $t('web.COMMON.secret') }}:
          {{ record?.secret_shortkey }}</span>
        <h2 v-if="details?.has_passphrase"
            class="mt-2 text-xl font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.private.requires_passphrase') }}
        </h2>
      </div>

      <form @submit.prevent="burn"
            class="space-y-4">
        <div v-if="details?.has_passphrase">
          <input type="password"
                 v-model="passphrase"
                 id="passField"
                 class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200"
                 placeholder="$t('web.COMMON.enter_passphrase_here')" />
        </div>
        <button type="submit"
                :disabled="isLoading"
                class="flex w-full items-center justify-center rounded-md bg-yellow-400 px-4 py-2 text-gray-800 transition duration-200 hover:bg-yellow-300 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800">
          <svg xmlns="http://www.w3.org/2000/svg"
               class="mr-2 size-5"
               viewBox="0 0 20 20"
               fill="currentColor"
               width="20"
               height="20">
            <path fill-rule="evenodd"
                  d="M12.395 2.553a1 1 0 00-1.45-.385c-.345.23-.614.558-.822.88-.214.33-.403.713-.57 1.116-.334.804-.614 1.768-.84 2.734a31.365 31.365 0 00-.613 3.58 2.64 2.64 0 01-.945-1.067c-.328-.68-.398-1.534-.398-2.654A1 1 0 005.05 6.05 6.981 6.981 0 003 11a7 7 0 1011.95-4.95c-.592-.591-.98-.985-1.348-1.467-.363-.476-.724-1.063-1.207-2.03zM12.12 15.12A3 3 0 017 13s.879.5 2.5.5c0-1 .5-4 1.25-4.5.5 1 .786 1.293 1.371 1.879A2.99 2.99 0 0113 13a2.99 2.99 0 01-.879 2.121z"
                  clip-rule="evenodd" />
          </svg>
          {{ $t('web.COMMON.word_confirm') }}: {{ $t('web.COMMON.burn_this_secret') }}
        </button>
        <a :href="`/${record?.metadata_path}`"
           class="mx-auto block w-3/4 rounded bg-gray-200 px-4 py-2 text-center text-gray-700 transition duration-200 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600">{{ $t('web.COMMON.word_cancel') }}</a>
        <hr class="border-gray-300 dark:border-gray-600" />
        <p class="text-base text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.burn_this_secret_confirm_hint') }}
        </p>
      </form>
    </div>
  </div>
</template>
