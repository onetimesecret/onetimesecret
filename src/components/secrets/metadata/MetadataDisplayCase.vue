<script setup lang="ts">
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { computed } from 'vue';

interface ExtendedMetadataDetails extends MetadataDetails {
  is_truncated?: boolean;
}

interface Props {
  metadata: Metadata;
  details: ExtendedMetadataDetails;
}

const props = defineProps<Props>();

// Core state management
const isUnread = computed(() => props.details.show_secret)
const isViewable = computed(() => isUnread.value && props.details.can_decrypt)
const isBurned = computed(() => props.details.is_burned)
const isReceived = computed(() => props.details.is_received)
const hasPassphrase = computed(() => !props.details.can_decrypt && !isReceived.value)

const iconPaths = {
  viewable: "M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z",
  burned: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
  protected: "M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z",
  viewed: "M6 18L18 6M6 6l12 12" // X icon
}

// Define the possible state types
type StateType = 'viewable' | 'burned' | 'received' | 'protected';

const statusLabels: Record<StateType, string> = {
  viewable: 'New',
  burned: 'Burned',
  received: 'Viewed',
  protected: 'Encrypted'
};

const stateConfig = computed<Record<StateType, { icon: string; color: string; message: string }>>(() => ({
  viewable: {
    icon: iconPaths.viewable,
    color: 'emerald',
    message: 'New secret created successfully!'
  },
  burned: {
    icon: iconPaths.burned,
    color: 'red',
    message: 'This secret was permanently deleted before it was read'
  },
  received: {
    icon: iconPaths.viewed,
    color: 'gray',
    message: 'This secret has already been viewed'
  },
  protected: {
    icon: iconPaths.protected,
    color: 'amber',
    message: hasPassphrase.value
      ? 'This secret requires a passphrase to decrypt'
      : 'This secret is encrypted and can only be viewed once'
  }
}));

// Define the structure of currentState
interface CurrentState {
  type: StateType;
  icon: string;
  color: string;
  message: string;
}

const currentState = computed<CurrentState>(() => {
  if (isViewable.value) return { type: 'viewable', ...stateConfig.value.viewable };
  if (isBurned.value) return { type: 'burned', ...stateConfig.value.burned };
  if (isReceived.value) return { type: 'received', ...stateConfig.value.received };
  return { type: 'protected', ...stateConfig.value.protected };
});

const showEncryptedPlaceholder = computed(() =>
  !isViewable.value && !isBurned.value && !isReceived.value
)
</script>

<template>
  <div class="rounded-lg border dark:border-gray-800">
    <div class="border-b border-gray-100 px-4 py-3 dark:border-gray-800">
      <div class="flex items-center justify-between">
        <h2 class="flex items-center gap-2 font-mono text-sm text-gray-500 dark:text-gray-400">
          <span>Secret</span>
          <code
            class="rounded bg-gray-100 px-1.5 py-0.5 font-medium text-brand-600
                     dark:bg-gray-800 dark:text-brand-400">
            {{ metadata.secret_shortkey }}
          </code>
        </h2>
        <div class="flex items-center gap-1.5">
          <div :class="`size-1.5 rounded-full bg-${currentState.color}-400`"></div>
          <span
            :class="`text-xs font-medium text-${currentState.color}-600
                        dark:text-${currentState.color}-400`">
            {{ statusLabels[currentState.type] }}
          </span>
        </div>
      </div>
    </div>

    <!-- Content -->
    <div class="p-4">
      <div
        :class="`mb-4 flex items-start gap-3 rounded-md bg-${currentState.color}-50
                    p-3 dark:bg-${currentState.color}-950/30`">
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
            :class="`text-sm font-medium
                      text-${currentState.color}-700 bg-${currentState.color}-50/10
                      dark:text-${currentState.color}-300 dark:bg-${currentState.color}-950/30`">
            {{ currentState.message }}
          </p>
          <p
            v-if="isViewable"
            class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {{ $t('web.private.only_see_once') }}
          </p>
        </div>
      </div>

      <!-- Secret Content -->
      <div class="relative">
        <template v-if="isViewable">
          <textarea
            class="w-full resize-none rounded-md border-2 border-emerald-200 bg-white
                   px-3 py-2 font-mono text-base leading-relaxed shadow-sm
                   focus:border-emerald-300 focus:outline-none focus:ring-2
                   focus:ring-emerald-500/20 dark:border-emerald-900
                   dark:bg-gray-900 dark:text-white"
            readonly
            :value="details.secret_value"
            :rows="details.display_lines || 3"></textarea>
        </template>
        <template v-else>
          <!-- Secret Content -->
          <div
            v-if="showEncryptedPlaceholder"
            class="relative">
            <div
              class="relative rounded-md border border-gray-200 bg-gray-50 px-3 py-2.5
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
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
