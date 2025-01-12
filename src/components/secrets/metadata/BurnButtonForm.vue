<script setup lang="ts">
  import { ref } from 'vue';
  import type { Metadata, MetadataDetails } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useMetadata } from '@/composables/useMetadata';

  interface Props {
    record: Metadata;
    details: MetadataDetails;
  }

  const props = defineProps<Props>();

  const { burn, isLoading } = useMetadata(props.record.key);

  const showConfirmation = ref(false);
  const isHovered = ref(false);
  const passphrase = ref('');
</script>

<template>
  <div
    v-if="!details.is_destroyed"
    class="flex flex-col items-center">
    <!-- Initial Burn Button -->
    <button
      v-if="!showConfirmation"
      @click="showConfirmation = true"
      class="w-full px-4 py-3 inline-flex items-center justify-center gap-2 text-base font-medium text-gray-800 bg-yellow-400 hover:bg-yellow-300 dark:text-gray-900 dark:hover:bg-yellow-300 rounded-lg transition-all duration-200 transform hover:scale-[1.02] focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800 relative overflow-hidden"
      :aria-label="$t('web.COMMON.burn_this_secret_aria')">
      <OIcon
        collection=""
        name="heroicons-fire-20-solid"
        class="w-5 h-5"
        :class="{ 'animate-bounce': isHovered }" />
      <span>{{ $t('web.COMMON.burn_this_secret') }}</span>
    </button>

    <!-- Confirmation Dialog -->
    <div
      v-else
      class="w-full bg-gray-50 dark:bg-gray-800 rounded-lg p-4 animate-fade-in">
      <div class="text-center mb-4">
        <OIcon
          collection=""
          name="heroicons-exclamation-triangle-20-solid"
          class="w-12 h-12 text-yellow-500 mx-auto mb-2" />
        <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100">
          {{ $t('web.COMMON.burn_confirmation_title') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ $t('web.COMMON.burn_confirmation_message') }}
        </p>
      </div>

      <div v-if="details.has_passphrase">
        <input
          type="password"
          v-model="passphrase"
          name="passphrase"
          id="passField"
          class="w-full px-3 py-2 border rounded-md border-gray-300 bg-white dark:bg-gray-800 dark:border-gray-600 dark:text-gray-200 focus:outline-none focus:ring-2 focus:ring-brand-500"
          :placeholder="$t('web.private.enter_passphrase')" />
      </div>

      <div class="flex flex-col gap-3 sm:flex-row sm:justify-center">
        <!-- Confirm Burn -->
        <button
          type="submit"
          @click="burn"
          :disabled="isLoading"
          class="inline-flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium text-white bg-red-600 hover:bg-red-700 rounded-md transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800">
          <OIcon
            collection=""
            name="heroicons-fire-20-solid"
            class="w-5 h-5" />
          {{ $t('web.COMMON.confirm_burn') }}
        </button>

        <!-- Cancel Button -->
        <button
          @click="showConfirmation = false"
          type="button"
          class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 border border-gray-300 rounded-md transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-700 dark:text-gray-200 dark:border-gray-600 dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800">
          {{ $t('web.COMMON.cancel') }}
        </button>
      </div>
    </div>

    <!-- Security Notice -->
    <div
      class="w-full mt-6 space-y-4"
      role="note">
      <p class="text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection=""
          name="heroicons-shield-exclamation"
          class="w-4 h-4 inline-block mr-1" />
        {{ $t('web.COMMON.burn_security_notice') }}
      </p>

      <div
        class="flex items-center gap-4"
        role="separator"
        aria-hidden="true">
        <div class="flex-grow h-px bg-gray-200 dark:bg-gray-700"></div>
        <OIcon
          collection=""
          name="heroicons-lock-closed"
          class="w-4 h-4 text-gray-400 dark:text-gray-600" />
        <div class="flex-grow h-px bg-gray-200 dark:bg-gray-700"></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
  .animate-fade-in {
    animation: fadeIn 0.3s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .animate-bounce {
    animation: bounce 1s ease-in-out;
  }

  @keyframes bounce {
    0%,
    100% {
      transform: translateY(0);
    }
    50% {
      transform: translateY(-25%);
    }
  }
</style>
