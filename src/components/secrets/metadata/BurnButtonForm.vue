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
  <div v-if="!record.is_destroyed"
       class="w-full max-w-md mx-auto">
    <form class="space-y-6"
          @submit.prevent>
      <!-- Initial Burn Button -->
      <button v-if="!showConfirmation"
              type="button"
              @click="showConfirmation = true"
              class="group w-full flex items-center justify-center gap-3 px-6 py-3 text-base font-semibold bg-brand-500 hover:bg-brand-600 text-white rounded-lg transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900 disabled:opacity-50"
              :disabled="isLoading"
              :aria-label="$t('web.COMMON.burn_this_secret_aria')"
              :aria-busy="isLoading"
              role="button">
        <OIcon collection=""
               name="heroicons-fire-20-solid"
               class="w-5 h-5 transition-transform group-hover:scale-110"
               :class="{ 'animate-bounce': isHovered }"
               aria-hidden="true" />
        <span>{{ $t('web.COMMON.burn_this_secret') }}</span>
      </button>

      <!-- Confirmation Dialog -->
      <div v-else
           role="alertdialog"
           aria-labelledby="burn-dialog-title"
           aria-describedby="burn-dialog-desc"
           class="rounded-xl bg-white dark:bg-gray-800 shadow-lg border border-gray-200 dark:border-gray-700 p-6 animate-fade-in">
        <div class="text-center space-y-4">
          <OIcon collection=""
                 name="heroicons-exclamation-triangle-20-solid"
                 class="w-12 h-12 text-yellow-500 mx-auto"
                 aria-hidden="true" />
          <h3 id="burn-dialog-title"
              class="text-xl font-bold text-gray-900 dark:text-white">
            {{ $t('web.COMMON.burn_confirmation_title') }}
          </h3>
          <p id="burn-dialog-desc"
             class="text-sm text-gray-600 dark:text-gray-300">
            {{ $t('web.COMMON.burn_confirmation_message') }}
          </p>
        </div>

        <div v-if="details.has_passphrase"
             class="mt-6">
          <label for="passField"
                 class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            {{ $t('web.LABELS.passphrase_protected') }}
          </label>
          <input type="password"
                 v-model="passphrase"
                 id="passField"
                 autocomplete="current-password"
                 :placeholder="$t('web.COMMON.enter_passphrase_here')"
                 class="w-full px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-brand-500 focus:border-transparent" />
        </div>

        <div class="mt-6 flex flex-col sm:flex-row gap-3 justify-end">
          <button type="button"
                  @click="showConfirmation = false"
                  class="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-brand-500">
            {{ $t('web.LABELS.cancel') }}
          </button>
          <button type="submit"
                  @click="burn"
                  :disabled="isLoading"
                  class="px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:opacity-50">
            {{ $t('web.COMMON.confirm_burn') }}
          </button>
        </div>
      </div>

      <!-- Security Notice -->
      <div role="note"
           class="mt-6 p-4 rounded-lg bg-gray-50 dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700">
        <div class="flex items-start gap-3 text-sm text-gray-600 dark:text-gray-400">
          <OIcon collection="heroicons"
                 name="shield-exclamation"
                 class="w-5 h-5 flex-shrink-0"
                 aria-hidden="true" />
          <span>{{ $t('web.COMMON.burn_security_notice') }}</span>
        </div>
      </div>
    </form>
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
