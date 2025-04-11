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
      <!-- Initial Burn Button with Enhanced Design -->
      <button v-if="!showConfirmation"
              type="button"
              @click="showConfirmation = true"
              class="group w-full flex items-center justify-center gap-3 px-6 py-3 text-base font-medium bg-gradient-to-r from-brand-500 to-brand-600 hover:from-brand-600 hover:to-brand-700 text-white rounded-lg shadow-sm hover:shadow transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900 disabled:opacity-50"
              :disabled="isLoading"
              :aria-label="$t('web.COMMON.burn_this_secret_aria')"
              :aria-busy="isLoading"
              role="button">
        <OIcon collection=""
               name="heroicons-fire-20-solid"
               class="w-5 h-5 transition-all group-hover:scale-125 group-hover:rotate-12"
               :class="{ 'animate-burn': isHovered }"
               aria-hidden="true" />
        <span>{{ $t('web.COMMON.burn_this_secret') }}</span>
      </button>

      <!-- Confirmation Dialog with Enhanced Design -->
      <div v-else
           role="alertdialog"
           aria-labelledby="burn-dialog-title"
           aria-describedby="burn-dialog-desc"
           class="rounded-xl bg-white dark:bg-gray-800 shadow-lg border border-gray-200 dark:border-gray-700 p-6 animate-rise-in">
        <div class="text-center space-y-4">
          <div class="relative w-16 h-16 mx-auto">
            <OIcon collection=""
                   name="heroicons-exclamation-triangle-20-solid"
                   class="w-16 h-16 text-yellow-500 mx-auto animate-attention"
                   aria-hidden="true" />
            <div class="absolute opacity-30 rounded-full animate-ping-slow"></div>
          </div>
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
                 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2 flex items-center gap-2">
            <OIcon collection=""
                   name="mdi-lock"
                   class="w-4 h-4 text-amber-500 dark:text-amber-400" />
            {{ $t('web.LABELS.passphrase_protected') }}
          </label>
          <div class="relative">
            <input type="password"
                   v-model="passphrase"
                   id="passField"
                   autocomplete="current-password"
                   :placeholder="$t('web.COMMON.enter_passphrase_here')"
                   class="w-full pl-10 pr-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-brand-500 focus:border-transparent shadow-sm" />
            <OIcon collection="material-symbols"
                   name="password"
                   class="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400 dark:text-gray-500" />
          </div>
        </div>

        <div class="mt-6 flex flex-col sm:flex-row gap-3 justify-end">
          <button type="button"
                  @click="showConfirmation = false"
                  class="px-4 py-2.5 text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-colors duration-200">
            {{ $t('web.LABELS.cancel') }}
          </button>
          <button type="submit"
                  @click="burn"
                  :disabled="isLoading"
                  class="px-4 py-2.5 text-sm font-medium text-white bg-gradient-to-r from-brand-500 to-brand-600 hover:from-brand-600 hover:to-brand-700 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:opacity-50 shadow-sm hover:shadow transition-all duration-200 flex items-center gap-2">
            <span>{{ $t('web.COMMON.confirm_burn') }}</span>
            <OIcon collection="material-symbols"
                   name="local-fire-department-rounded"
                   class="w-4 h-4"
                   :class="{ 'animate-spin': isLoading }" />
          </button>
        </div>
      </div>

      <!-- Security Notice with Enhanced Design -->
      <div role="note"
           class="mt-6 p-4 rounded-lg bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-800/60 dark:to-gray-800/30 border border-gray-200 dark:border-gray-700/50 shadow-sm">
        <div class="flex items-start gap-3 text-sm text-gray-600 dark:text-gray-400">
          <OIcon collection="heroicons"
                 name="shield-exclamation"
                 class="w-5 h-5 flex-shrink-0 text-amber-500 dark:text-amber-400"
                 aria-hidden="true" />
          <span>{{ $t('web.COMMON.burn_security_notice') }}</span>
        </div>
      </div>
    </form>
  </div>
</template>

<style scoped>

</style>
