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
    props.record.expiration_in_seconds ?? 0
  );

  const showExpiration = computed(() => !props.record.is_burned && !props.record.is_received);
  const showFaded = computed(() => expirationState.value === 'expired' || !showExpiration.value);

  // Helper function for consistent time formatting
  const formatTimeAgo = (date: Date) => formatDistanceToNow(date, { addSuffix: true });
</script>

<template>
  <div
    class="relative pt-4"
    :class="{ 'opacity-60': showFaded }">
    <!-- Timeline Track with Gradient -->
    <!-- prettier-ignore-attribute class -->
    <div
      class="absolute left-6 top-8 h-[calc(100%-4rem)] w-px
        bg-gradient-to-b from-brand-200 to-gray-200
        dark:from-brand-700 dark:to-gray-700"></div>

    <!-- Timeline Events -->
    <div class="space-y-6">
      <!-- Created -->
      <div class="group flex gap-4">
        <!-- prettier-ignore-attribute class -->
        <div
          class="
          z-10 flex size-12 shrink-0 items-center
          justify-center rounded-full
          border border-brand-200
          bg-brand-100 shadow-sm transition-all duration-300
          group-hover:scale-110 group-hover:shadow-md
          dark:border-brand-800 dark:bg-brand-900">
          <!-- prettier-ignore-attribute class -->
          <OIcon
            collection="material-symbols"
            name="schedule-outline"
            class="size-6 text-brand-600 transition-transform duration-300
                  group-hover:rotate-12 dark:text-brand-400"
            aria-hidden="true" />
        </div>
        <div class="transition-transform duration-200 group-hover:translate-x-1">
          <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.created') }}
          </p>
          <time
            :datetime="record.created.toISOString()"
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.created.toLocaleString() }}
          </time>
        </div>
      </div>

      <!-- Received (if applicable) -->
      <div
        v-if="record.is_received"
        class="group flex gap-4">
        <!-- prettier-ignore-attribute class -->
        <div
          class="
          z-10 flex size-12 shrink-0
          items-center justify-center
          rounded-full border
          border-green-200 bg-green-100
          shadow-sm transition-all duration-300 group-hover:scale-110
          group-hover:shadow-md dark:border-green-800
          dark:bg-green-900">
          <!-- prettier-ignore-attribute class -->
          <OIcon
            collection="material-symbols"
            name="mark-email-read-outline"
            class="size-6 text-green-600 transition-transform duration-300
                        group-hover:rotate-12 dark:text-green-400"
            aria-hidden="true" />
        </div>
        <div class="transition-transform duration-200 group-hover:translate-x-1">
          <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.received') }}
          </p>
          <time
            :datetime="record.received?.toISOString()"
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.received?.toLocaleString() }}
          </time>
          <p
            v-if="record.received"
            class="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
            {{ formatTimeAgo(record.received) }}
          </p>
        </div>
      </div>

      <!-- Burned (if applicable) -->
      <div
        v-if="record.is_burned"
        class="group flex gap-4">
        <!-- prettier-ignore-attribute class -->
        <div
          class="z-10 flex size-12 shrink-0 items-center justify-center
            rounded-full border border-yellow-200 bg-yellow-100 shadow-sm transition-all duration-300
            group-hover:scale-110 group-hover:shadow-md dark:border-yellow-800 dark:bg-yellow-900">
          <!-- prettier-ignore-attribute class -->
          <OIcon
            collection="material-symbols"
            name="local-fire-department-rounded"
            class="size-6 text-yellow-600 transition-transform duration-300
              group-hover:rotate-12 dark:text-yellow-400"
            aria-hidden="true" />
        </div>
        <div class="transition-transform duration-200 group-hover:translate-x-1">
          <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
            {{ $t('web.STATUS.burned') }}
          </p>
          <time
            :datetime="record.burned?.toISOString()"
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ record.burned?.toLocaleString() }}
          </time>
          <p
            v-if="record.burned"
            class="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
            {{ formatTimeAgo(record.burned) }}
          </p>
        </div>
      </div>

      <!-- Expiration -->
      <div
        v-if="showExpiration"
        class="group flex gap-4">
        <!-- prettier-ignore-attribute class -->
        <div
          class="z-10 flex size-12 shrink-0 items-center justify-center
            rounded-full border border-red-200 bg-red-100 shadow-sm
            transition-all duration-300 group-hover:scale-110 group-hover:shadow-md
            dark:border-red-800 dark:bg-red-900">
          <OIcon
            collection="material-symbols"
            name="timer-outline"
            class="size-6 text-red-600 transition-transform duration-300 group-hover:rotate-12
              dark:text-red-400"
            aria-hidden="true" />
        </div>
        <div class="grow transition-transform duration-200 group-hover:translate-x-1">
          <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
            {{ progress >= 100 ? $t('web.STATUS.expired') : $t('web.STATUS.expires') }}
          </p>

          <!-- Expiration Progress Bar with Enhanced Design -->
          <div class="group/progress relative mt-2">
            <div class="h-2 overflow-hidden rounded-full bg-gray-200 shadow-inner dark:bg-gray-700">
              <!-- prettier-ignore-attribute class -->
              <div
                class="h-2 rounded-full bg-gradient-to-r from-red-400 to-red-500
                transition-[width] duration-1000 ease-linear"
                :style="{ width: `${progress}%` }"
                :class="{ 'animate-pulse': progress > 70 && progress < 100 }"></div>
            </div>

            <!-- Tooltip with Enhanced Design -->
            <!-- prettier-ignore-attribute class -->
            <div
              class="absolute bottom-full left-1/2 mb-2 -translate-x-1/2 whitespace-nowrap
              rounded-lg bg-gray-900 px-3 py-1.5 text-xs text-white opacity-0 shadow-lg
              transition-opacity duration-200 group-hover/progress:opacity-100
              dark:bg-gray-800 dark:text-gray-100">
              {{ timeRemaining }}
              <!-- prettier-ignore-attribute class -->
              <div
                class="absolute left-1/2 top-full -mt-px -translate-x-1/2
                border-4 border-transparent border-t-gray-900 dark:border-t-gray-800"></div>
            </div>
          </div>

          <time
            :datetime="expirationDate.toISOString()"
            class="mt-2 block text-sm text-gray-500 dark:text-gray-400">
            {{ expirationDate.toLocaleString() }}
          </time>
          <p class="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
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
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.8;
    }
  }
</style>
