// src/components/secrets/metadata/TimelineDisplay.vue

<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models';
import OIcon from '@/components/icons/OIcon.vue';
import { useSecretExpiration } from '@/composables/useSecretExpiration';
import { formatDistanceToNow } from 'date-fns';

interface Props {
  record: Metadata;
  details: MetadataDetails;
}

const props = defineProps<Props>();

const { progress, timeRemaining, expirationDate } = useSecretExpiration(
  props.record.created,
  props.record.expiration_in_seconds ?? 0,
);

// Helper function for consistent time formatting
const formatTimeAgo = (date: Date) => formatDistanceToNow(date, { addSuffix: true });

</script>

<template>
  <div class="relative pt-4">
    <!-- Timeline Track -->
    <div class="absolute top-8 left-6 h-full w-px bg-gray-200 dark:bg-gray-700"></div>

    <!-- Timeline Events -->
    <div class="space-y-6">
      <!-- Created -->
      <div class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full
          bg-brand-100 dark:bg-brand-900
          transition-transform duration-200
          group-hover:scale-110">
          <OIcon collection="material-symbols"
                 name="schedule-outline"
                 class="w-6 h-6 text-brand-600 dark:text-brand-400"
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
          rounded-full
          bg-green-100 dark:bg-green-900
          transition-transform duration-200
          group-hover:scale-110">
          <OIcon collection="material-symbols"
                 name="mark-email-read-outline"
                 class="w-6 h-6 text-green-600 dark:text-green-400"
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
      <div v-if="details.is_burned"
           class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full
          bg-yellow-100 dark:bg-yellow-900
          transition-transform duration-200
          group-hover:scale-110">
          <OIcon collection="material-symbols"
                 name="local-fire-department-rounded"
                 class="w-6 h-6 text-yellow-600 dark:text-yellow-400"
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
      <div class="group flex gap-4">
        <div class="
          flex-shrink-0 w-12 h-12
          flex items-center justify-center
          rounded-full
          bg-red-100 dark:bg-red-900
          transition-transform duration-200
          group-hover:scale-110">
          <OIcon collection="material-symbols"
                 name="timer-outline"
                 class="w-6 h-6 text-red-600 dark:text-red-400"
                 aria-hidden="true" />
        </div>
        <div class="flex-grow group-hover:translate-x-1 transition-transform duration-200">
          <p class="text-sm font-brand text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.expires') }}
          </p>

          <!-- Expiration Progress Bar -->
          <div class="bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
            <div class="bg-red-500 h-1.5 rounded-full transition-all duration-300"
                 :style="{ width: `${progress}%` }"
                 :title="`${progress.toFixed(1)}% elapsed`"></div>
          </div>

          <time :datetime="expirationDate.toISOString()"
                class="text-sm text-gray-500 dark:text-gray-400">
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
