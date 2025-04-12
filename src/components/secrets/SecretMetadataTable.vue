<script setup lang="ts">
import SecretMetadataTableItem from '@/components/secrets/SecretMetadataTableItem.vue';
import { MetadataRecords } from '@/schemas/api/endpoints';

interface Props {
  notReceived: MetadataRecords[];
  received: MetadataRecords[];
  isLoading: boolean;
}

defineProps<Props>();
</script>

<template>
  <div
    class="space-y-8"
    v-cloak>
    <template v-if="isLoading">
      <!-- Add a loading indicator here -->
      <div class="text-justify">
        <p class="text-gray-600 dark:text-gray-400">
          {{ $t('loading_ellipses') }}
        </p>
      </div>
    </template>
    <template v-else>
      <section>
        <h3 class="mb-4 text-2xl font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.dashboard.title_not_received') }}
        </h3>
        <ul
          v-if="notReceived"
          class="space-y-1">
          <li
            v-for="item in notReceived"
            :key="item.key">
            <SecretMetadataTableItem :secret-metadata="item" />
          </li>
        </ul>
        <p
          v-else
          class="italic text-gray-600 dark:text-gray-400">
          {{ $t('go-on-then') }}
          <router-link
            to="/"
            class="text-brand-500 hover:underline">
            {{ $t('web.COMMON.share_a_secret') }}
          </router-link>
        </p>
      </section>

      <section>
        <h3 class="mb-4 text-2xl font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.dashboard.title_received') }}
        </h3>
        <ul
          v-if="received"
          class="space-y-1">
          <li
            v-for="item in received"
            :key="item.key">
            <SecretMetadataTableItem :secret-metadata="item" />
          </li>
        </ul>
        <p
          v-else
          class="italic text-gray-600 dark:text-gray-400">
          {{ $t('web.COMMON.word_none') }}
        </p>
      </section>
    </template>
  </div>
</template>
