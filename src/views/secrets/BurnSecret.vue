<template>
  <div>
    <div
      v-if="!record || details?.is_destroyed"
      class="relative mb-4 rounded border border-red-400
     bg-red-100 px-4 py-3
     text-red-700 dark:border-red-600 dark:bg-red-900/50 dark:text-red-300"
    >
      <span class="block sm:inline">
        <template v-if="details?.is_received">
          This secret was viewed on {{ details.received_date }}
          and is no longer accessible.
        </template>
        <template v-else-if="details?.is_burned">
          This secret was permanently deleted on {{ details.burned_date }}.
        </template>
        <template v-else>
          This secret was permanently deleted.
        </template>
      </span>
      <a
        v-if="record && record?.metadata_url"
        :href="record?.metadata_url"
        class="mt-2 block w-full rounded bg-gray-300
     px-4 py-2 text-center text-gray-700
     hover:bg-gray-300
     dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
      >
        Back
      </a>
      <router-link
        to="/"
        class="mt-2 block w-full rounded bg-gray-300
               px-4 py-2 text-center text-gray-700
               hover:bg-gray-300
               dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
      >
        Home
      </router-link>
    </div>


    <div v-else>
      <div class="mb-6">
        <span class="text-lg text-gray-600 dark:text-gray-400">{{ $t('web.COMMON.secret') }}:
          {{ record?.secret_shortkey }}</span>
        <h2
          v-if="details?.has_passphrase"
          class="mt-2 text-xl font-semibold text-gray-800 dark:text-gray-200"
        >
          {{ $t('web.private.requires_passphrase') }}
        </h2>
      </div>

      <form
        @submit.prevent="handleBurn"
        class="space-y-4"
      >
        <div v-if="details?.has_passphrase">
          <input
            type="password"
            v-model="passphrase"
            id="passField"
            class="w-full rounded-md border border-gray-300 bg-white
                px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500
                dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200"
            placeholder="Enter the passphrase here"
          />
        </div>
        <button
          type="submit"
          :disabled="isLoading"
          class="flex w-full items-center justify-center
                rounded-md bg-yellow-400
                px-4 py-2 text-gray-800 transition duration-200 hover:bg-yellow-300
                focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="mr-2 size-5"
            viewBox="0 0 20 20"
            fill="currentColor"
            width="20"
            height="20"
          >
            <path
              fill-rule="evenodd"
              d="M12.395 2.553a1 1 0 00-1.45-.385c-.345.23-.614.558-.822.88-.214.33-.403.713-.57 1.116-.334.804-.614 1.768-.84 2.734a31.365 31.365 0 00-.613 3.58 2.64 2.64 0 01-.945-1.067c-.328-.68-.398-1.534-.398-2.654A1 1 0 005.05 6.05 6.981 6.981 0 003 11a7 7 0 1011.95-4.95c-.592-.591-.98-.985-1.348-1.467-.363-.476-.724-1.063-1.207-2.03zM12.12 15.12A3 3 0 017 13s.879.5 2.5.5c0-1 .5-4 1.25-4.5.5 1 .786 1.293 1.371 1.879A2.99 2.99 0 0113 13a2.99 2.99 0 01-.879 2.121z"
              clip-rule="evenodd"
            />
          </svg>
          {{ $t('web.COMMON.word_confirm') }}: {{ $t('web.COMMON.burn_this_secret') }}
        </button>
        <a
          :href="record?.metadata_url"
          class="block w-full rounded bg-gray-200 px-4 py-2
           text-center text-gray-700 transition duration-200 hover:bg-gray-300 dark:bg-gray-700
           dark:text-gray-200 dark:hover:bg-gray-600"
        >{{ $t('web.COMMON.word_cancel') }}</a>
        <hr class="border-gray-300 dark:border-gray-600" />
        <p class="text-md text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.burn_this_secret_confirm_hint') }}
        </p>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useMetadataBurn } from '@/composables/useMetadataBurn';
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notifications';
import { storeToRefs } from 'pinia';
import { useRouter } from 'vue-router';

interface Props {
  metadataKey: string
}

const props = defineProps<Props>();
const router = useRouter();

const metadataStore = useMetadataStore();
const notifications = useNotificationsStore();
const { currentRecord: record, details, isLoading } = storeToRefs(metadataStore);

const { passphrase, handleBurn } = useMetadataBurn(props.metadataKey);
</script>
