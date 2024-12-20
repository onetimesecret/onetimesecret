<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { computed } from 'vue';

// Types and interfaces
interface Props {
  metadata: Metadata;
  details: MetadataDetails;
}

type StateType = 'viewable' | 'burned' | 'received' | 'protected' | 'destroyed';

interface CurrentState {
  type: StateType;
  icon: string;
  color: string;
  message: string;
}

// Component props
const props = defineProps<Props>();

/**
 * Icon path configurations for different states
 */
const iconPaths = {
  viewable: "M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z",
  burned: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
  protected: "M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z",
  viewed: "M6 18L18 6M6 6l12 12",
  destroyed: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
} as const;

/**
 * Status label mappings
 */
const statusLabels: Record<StateType, string> = {
  viewable: 'New',
  burned: 'Burned',
  received: 'Viewed',
  protected: 'Encrypted',
  destroyed: 'Destroyed'
} as const;

/**
 * Core computed state properties
 */
const isUnread = computed(() => props.details.show_secret);
const isViewable = computed(() => isUnread.value && props.details.can_decrypt);
const isBurned = computed(() => props.details.is_burned);
const isReceived = computed(() => props.details.is_received);
const isDestroyed = computed(() => props.details.is_destroyed);
const hasPassphrase = computed(() => !props.details.can_decrypt && !isReceived.value && !isDestroyed.value);

/**
 * Date formatting utilities
 */
const formatDate = (date: Date | undefined): string => {
  if (!date) return '';

  return new Intl.DateTimeFormat('default', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short'
  }).format(date);
};

const formatRelativeTime = (date: Date | undefined): string => {
  if (!date) return '';

  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 60) return 'just now';
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)} minutes ago`;
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)} hours ago`;
  return `${Math.floor(diffInSeconds / 86400)} days ago`;
};

/**
 * State configuration for different secret states
 */
const stateConfig = computed<Record<StateType, { icon: string; color: string; message: string }>>(() => ({
  viewable: {
    icon: iconPaths.viewable,
    color: 'emerald',
    message: 'New secret created successfully!'
  },
  burned: {
    icon: iconPaths.burned,
    color: 'red',
    message: `Burned ${formatRelativeTime(props.metadata.burned)}`
  },
  received: {
    icon: iconPaths.viewed,
    color: 'gray',
    message: `This secret was viewed ${formatRelativeTime(props.metadata.received)}`
  },
  protected: {
    icon: iconPaths.protected,
    color: 'amber',
    message: hasPassphrase.value
      ? 'This secret requires a passphrase to decrypt'
      : 'This secret is encrypted and can only be viewed once'
  },
  destroyed: {
    icon: iconPaths.destroyed,
    color: 'red',
    message: `Destroyed ${formatRelativeTime(props.metadata.updated)}`
  }
}));

/**
 * Determines the current state of the secret based on computed properties
 * Priority: viewable > burned > received > protected > destroyed
 */
const currentState = computed<CurrentState>(() => {
  if (isViewable.value) return { type: 'viewable', ...stateConfig.value.viewable };
  if (isBurned.value) return { type: 'burned', ...stateConfig.value.burned };
  if (isReceived.value) return { type: 'received', ...stateConfig.value.received };
  if (!isDestroyed.value) return { type: 'protected', ...stateConfig.value.protected };

  return { type: 'destroyed', ...stateConfig.value.destroyed };
});

/**
 * Determines if the encrypted placeholder should be shown
 */
const showEncryptedPlaceholder = computed(() =>
  !isViewable.value &&
  !isBurned.value &&
  !isReceived.value &&
  !isDestroyed.value &&
  !props.details.has_passphrase
);
</script>

<template>
  <div class="rounded-lg border dark:border-gray-800">
    <!-- Header -->
    <div class="flex items-center justify-between border-b border-gray-100 px-4 py-3 dark:border-gray-800">
      <h2 class="flex items-center gap-2">
        <span class="font-mono text-sm text-gray-500 dark:text-gray-400">Secret</span>
        <code
          class="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-sm font-medium text-brand-600
                   dark:bg-gray-800 dark:text-brand-400">
          {{ metadata.secret_shortkey }}
        </code>
      </h2>

      <!-- Status Indicator -->
      <div class="flex items-center gap-2">
        <div :class="`size-2 rounded-full bg-${currentState.color}-400`"></div>
        <span :class="`text-sm font-medium text-${currentState.color}-600 dark:text-${currentState.color}-400`">
          {{ statusLabels[currentState.type] }}
        </span>
      </div>
    </div>

    <!-- Content -->
    <div class="space-y-4 p-4">
      <!-- Status Message -->
      <div
        :class="`flex items-start gap-3 rounded-md bg-${currentState.color}-50 p-3
                    dark:bg-${currentState.color}-950/30`">
        <svg
          class="mt-0.5 size-5"
          :class="`text-${currentState.color}-500`"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            :d="currentState.icon"
          />
        </svg>
        <div>
          <p
            :class="`text-sm font-medium text-${currentState.color}-700
                    dark:text-${currentState.color}-300`">
            {{ currentState.message }}
          </p>
          <p
            v-if="isViewable"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ $t('web.private.only_see_once') }}
          </p>
        </div>
      </div>

      <!-- Secret Content -->
      <div class="relative space-y-4">
        <template v-if="isViewable">
          <textarea
            class="w-full resize-none rounded-md border-2 border-emerald-200 bg-white px-3 py-2
                   font-mono text-base leading-relaxed shadow-sm focus:border-emerald-300
                   focus:outline-none focus:ring-2 focus:ring-emerald-500/20
                   dark:border-emerald-900 dark:bg-gray-900 dark:text-white"
            readonly
            :value="details.secret_value"
            :rows="details.display_lines || 3">
          </textarea>
        </template>

        <template v-else-if="showEncryptedPlaceholder">
          <div
            class="rounded-md border border-gray-200 bg-gray-50 px-3 py-2.5
                      dark:border-gray-800 dark:bg-gray-900">
            <div class="flex items-center justify-between">
              <div class="font-mono text-gray-400 dark:text-gray-500">
                •••••••••••••••••••
              </div>
              <span class="text-xs font-medium text-gray-400 dark:text-gray-500">
                Encrypted
              </span>
            </div>
          </div>
        </template>

        <!-- Timing Information -->
        <details class="group">
          <summary
            class="flex cursor-pointer items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <svg
              class="size-4 transition-transform group-open:rotate-90"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5l7 7-7 7"
              />
            </svg>
            View timing information
          </summary>

          <div class="mt-2 grid gap-1 pl-6 text-sm text-gray-500 dark:text-gray-400">
            <p>
              <span class="inline-block w-24">Lifespan:</span>
              {{ metadata.natural_expiration }}
            </p>
            <p v-if="!isDestroyed">
              <span class="inline-block w-24">Expires:</span>
              {{ formatDate(metadata.expiration) }}
            </p>
            <p v-if="isBurned">
              <span class="inline-block w-24">Burned:</span>
              {{ formatDate(metadata.burned) }}
            </p>
            <p>
              <span class="inline-block w-24">Created:</span>
              {{ formatDate(metadata.created) }}
            </p>
            <p>
              <span class="inline-block w-24">Updated:</span>
              {{ formatDate(metadata.updated) }}
            </p>
          </div>
        </details>
      </div>
    </div>
  </div>
</template>
