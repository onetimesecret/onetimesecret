<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models';
import OIcon from '@/components/icons/OIcon.vue';
import { useSecretExpiration } from '@/composables/useSecretExpiration';
import { formatDistanceToNow } from 'date-fns';
import { computed } from 'vue';

interface Props {
  record: Metadata;
  details: MetadataDetails;
}

const props = defineProps<Props>();

const { progress, timeRemaining, expirationDate, expirationState } = useSecretExpiration(
  props.record.created,
  props.record.expiration_in_seconds ?? 0,
);

const showExpiration = computed(() => !props.record.is_burned && !props.record.is_received);
const showFaded = computed(() => expirationState.value === 'expired' || !showExpiration.value);

// Helper function for consistent time formatting
const formatTimeAgo = (date: Date) => formatDistanceToNow(date, { addSuffix: true });

</script>

<template>
  <div class="relative pt-4"
    :class="{ 'opacity-60': showFaded }">
    <!-- Timeline Track with Gradient -->
    <div class="absolute top-8 left-6 h-[calc(100%-4rem)] w-px bg-gradient-to-b from-brand-200 to-gray-200 dark:from-brand-700 dark:to-gray-700"></div>

    <!-- Timeline Events -->
    <div class="space-y-6">
      <!-- Created -->
      <div class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full z-10
          bg-brand-100 dark:bg-brand-900
          shadow-sm border border-brand-200 dark:border-brand-800
          transition-all duration-300
          group-hover:scale-110 group-hover:shadow-md">
          <OIcon collection="material-symbols"
                 name="schedule-outline"
                 class="w-6 h-6 text-brand-600 dark:text-brand-400
                        transition-transform duration-300 group-hover:rotate-12"
                 aria-hidden="true" />
        </div>
        <div class="group-hover:translate-x-1 transition-transform duration-200">
          <p class="text-sm font-brand text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.created') }}
          </p>
          <time :datetime="record.created.toISOString()"
                class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.created.toLocaleString() }}
          </time>
        </div>
      </div>

      <!-- Received (if applicable) -->
      <div v-if="record.is_received"
           class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full z-10
          bg-green-100 dark:bg-green-900
          shadow-sm border border-green-200 dark:border-green-800
          transition-all duration-300
          group-hover:scale-110 group-hover:shadow-md">
          <OIcon collection="material-symbols"
                 name="mark-email-read-outline"
                 class="w-6 h-6 text-green-600 dark:text-green-400
                        transition-transform duration-300 group-hover:rotate-12"
                 aria-hidden="true" />
        </div>
        <div class="group-hover:translate-x-1 transition-transform duration-200">
          <p class="text-sm font-brand text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.received') }}
          </p>
          <time :datetime="record.received?.toISOString()"
                class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.received?.toLocaleString() }}
          </time>
          <p v-if="record.received"
             class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
            {{ formatTimeAgo(record.received) }}
          </p>
        </div>
      </div>

      <!-- Burned (if applicable) -->
      <div v-if="record.is_burned"
           class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full z-10
          bg-yellow-100 dark:bg-yellow-900
          shadow-sm border border-yellow-200 dark:border-yellow-800
          transition-all duration-300
          group-hover:scale-110 group-hover:shadow-md">
          <OIcon collection="material-symbols"
                 name="local-fire-department-rounded"
                 class="w-6 h-6 text-yellow-600 dark:text-yellow-400
                        transition-transform duration-300 group-hover:rotate-12"
                 aria-hidden="true" />
        </div>
        <div class="group-hover:translate-x-1 transition-transform duration-200">
          <p class="text-sm font-brand text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.burned') }}
          </p>
          <time :datetime="record.burned?.toISOString()"
                class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.burned?.toLocaleString() }}
          </time>
          <p v-if="record.burned"
             class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
            {{ formatTimeAgo(record.burned) }}
          </p>
        </div>
      </div>

      <!-- Expiration -->
      <div v-if="showExpiration"
      class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full z-10
          bg-red-100 dark:bg-red-900
          shadow-sm border border-red-200 dark:border-red-800
          transition-all duration-300
          group-hover:scale-110 group-hover:shadow-md">
          <OIcon collection="material-symbols"
                 name="timer-outline"
                 class="w-6 h-6 text-red-600 dark:text-red-400
                        transition-transform duration-300 group-hover:rotate-12"
                 aria-hidden="true" />
        </div>
        <div class="flex-grow group-hover:translate-x-1 transition-transform duration-200">
          <p class="text-sm font-brand text-gray-900 dark:text-gray-100">
          {{ progress >= 100 ? $t('web.STATUS.expired') : $t('web.STATUS.expires') }}
          </p>

          <!-- Expiration Progress Bar with Enhanced Design -->
          <div class="relative group/progress mt-2">
            <div class="bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden shadow-inner">
              <div class="bg-gradient-to-r from-red-400 to-red-500 h-2 rounded-full transition-[width] duration-1000 ease-linear"
                   :style="{ width: `${progress}%` }"
                   :class="{ 'animate-pulse': progress > 70 && progress < 100 }"></div>
            </div>

            <!-- Tooltip with Enhanced Design -->
            <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2
                        opacity-0 group-hover/progress:opacity-100
                        transition-opacity duration-200
                        whitespace-nowrap
                        px-3 py-1.5 text-xs
                        bg-gray-900 dark:bg-gray-800
                        text-white dark:text-gray-100
                        rounded-lg shadow-lg">
                        {{ timeRemaining }}
              <div class="absolute top-full left-1/2 -translate-x-1/2 -mt-px
                          border-4 border-transparent
                          border-t-gray-900 dark:border-t-gray-800"></div>
            </div>
          </div>

          <time :datetime="expirationDate.toISOString()"
                class="text-sm text-gray-500 dark:text-gray-400 mt-2 block">
            {{ expirationDate.toLocaleString() }}
          </time>
          <p class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
            {{ timeRemaining }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Enhanced progress bar animation */
@keyframes progress-pulse {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0.8;
  }
}
</style>
