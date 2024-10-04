
<template>
  <!-- Move to a separate component -->
  <div class="space-y-8" v-cloak>
    <template v-if="isLoading">
      <!-- Add a loading indicator here -->
      <div class="text-justify">
        <p class="text-gray-600 dark:text-gray-400">Loading...</p>
      </div>
    </template>
    <template v-else>
      <template v-if="hasItems">
        <section>
          <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
              {{ $t('web.dashboard.title_not_received') }}
          </h3>
          <ul v-if="notReceived" class="space-y-1">
            <li v-for="item in notReceived" :key="item.identifier">
              <!-- Assuming there's a component for li_metadata -->
              <SecretMetadataTableItem :secretMetadata="item" />
            </li>
          </ul>
          <p v-else class="text-gray-600 dark:text-gray-400 italic">
            Go on then.
              <router-link to="/" class="text-brand-500 hover:underline">{{ $t('web.COMMON.share_a_secret') }}</router-link>!
          </p>
        </section>

        <section>
          <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
              {{ $t('web.dashboard.title_received') }}
          </h3>
            <ul v-if="received" class="space-y-1">
              <li v-for="item in received" :key="item.identifier">
                <!-- Assuming there's a component for li_metadata -->
                <SecretMetadataTableItem :secretMetadata="item" />
              </li>
          </ul>
            <p v-else class="text-gray-600 dark:text-gray-400 italic">{{ $t('web.COMMON.word_none') }}</p>
        </section>
      </template>

      <template v-if="!hasItems">
        <section>
          <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
            {{ $t('web.dashboard.title_no_recent_secrets') }}
          </h3>
          <p class="text-gray-600 dark:text-gray-400 italic">
            Go on then.
            <router-link to="/" class="text-brand-500 hover:underline">{{ $t('web.COMMON.share_a_secret') }}</router-link>!
          </p>
        </section>
      </template>
    </template>
  </div>
</template>

<script setup lang="ts">
import { Metadata } from '@/types/onetime';
import SecretMetadataTableItem from '@/components/secrets/SecretMetadataTableItem.vue';

interface Props {
  hasItems?: boolean;
  notReceived?: Metadata[];
  received?: Metadata[];
  isLoading: boolean;
}

defineProps<Props>();
</script>
