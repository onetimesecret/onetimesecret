<!-- src/apps/secret/components/SecretLinksTableRow.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { formatTTL } from '@/utils/formatters';
import { formatDistanceToNow } from 'date-fns';
import { storeToRefs } from 'pinia';
import { ref, computed } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  record: RecentSecretRecord;
  /** Row index (1-based) for visual reference */
  index: number;
}>();

const emit = defineEmits<{
  copy: [];
  delete: [record: RecentSecretRecord];
}>();

// Track if this row's content was copied
const isCopied = ref(false);

const bootstrapStore = useBootstrapStore();
const { site_host } = storeToRefs(bootstrapStore);

// Create shareable link with proper domain
const shareLink = computed(() => {
  const shareDomain = props.record.shareDomain ?? site_host.value;
  return `https://${shareDomain}/secret/${props.record.secretExtid}`;
});

const handleCopy = async () => {
  try {
    await navigator.clipboard.writeText(shareLink.value);
    isCopied.value = true;
    emit('copy');

    // Reset copy state after around 2 seconds
    setTimeout(() => {
      isCopied.value = false;
    }, 1500);
  } catch (err) {
    console.error('Failed to copy text: ', err);
  }
};

// Format creation date to be more readable
const formattedDate = computed(() =>
  formatDistanceToNow(props.record.createdAt, { addSuffix: true })
);

// Compute security status and time remaining
const hasPassphrase = computed(() => props.record.hasPassphrase);

const timeRemaining = computed(() => formatTTL(props.record.ttl));

// Secret state computations - use flat fields from RecentSecretRecord
const isExpired = computed(() => props.record.isExpired || props.record.ttl <= 0);
const isBurned = computed(() => props.record.isBurned);
const isViewed = computed(() => props.record.isViewed);
const isReceived = computed(() => props.record.isReceived);

// Calculate TTL percentage for background color
const getTtlPercentage = computed(() => {
  // Default max TTL to 7 days (604800 seconds)
  const maxTtl = 604800;
  return Math.floor((props.record.ttl / maxTtl) * 100);
});

// Card background color based on state
const cardBackgroundClass = computed(() => {
  if (isExpired.value || isBurned.value) {
    return 'bg-gray-50/60 dark:bg-slate-800/30';
  }
  return 'bg-white dark:bg-slate-900/80';
});

// Status dot color
const statusDotClass = computed(() => {
  if (isExpired.value) return 'bg-gray-400 dark:bg-gray-500';
  if (isBurned.value) return 'bg-red-500 dark:bg-red-400';
  if (isViewed.value) return 'bg-amber-500 dark:bg-amber-400';
  return 'bg-emerald-500 dark:bg-emerald-400';
});

// Status text color
const statusTextClass = computed(() => {
  if (isExpired.value) return 'text-gray-500 dark:text-gray-400';
  if (isBurned.value) return 'text-red-600 dark:text-red-400';
  if (isViewed.value) return 'text-amber-600 dark:text-amber-400';
  return 'text-emerald-600 dark:text-emerald-400';
});

// Get status label based on state
const statusLabel = computed(() => {
  if (isExpired.value) return t('web.STATUS.expired');
  if (isBurned.value) return t('web.STATUS.burned');
  if (isViewed.value) return t('web.STATUS.viewed');
  if (isReceived.value) return t('web.STATUS.received');
  return t('web.STATUS.active');
});

// Display key (truncated: first 4 + ... + last 4 chars)
const displayKey = computed(() => {
  const shortid = props.record.shortid;
  if (!shortid || shortid.length <= 8) return shortid;
  return `${shortid.slice(0, 4)}...${shortid.slice(-4)}`;
});

// Check if secret is still active (can be shared)
const isActive = computed(() => !isExpired.value && !isBurned.value);

// Time remaining with urgency indicator
const isUrgent = computed(() => {
  const percentage = getTtlPercentage.value;
  return percentage <= 25 && isActive.value;
});
</script>

<template>
  <div
    role="listitem"
    :class="[
      'group relative rounded-xl border transition-all duration-200',
      cardBackgroundClass,
      isActive
        ? 'border-gray-200 shadow-sm hover:border-gray-300 hover:shadow-md dark:border-gray-700/60 dark:hover:border-gray-600'
        : 'border-gray-200/60 dark:border-gray-700/40',
      { 'opacity-75': !isActive },
    ]">
    <!-- Main card content -->
    <div class="flex items-start gap-4 p-4">
      <!-- Index number - large visual anchor -->
      <div class="flex-shrink-0 pt-0.5">
        <span
          class="select-none font-mono text-3xl font-bold tabular-nums text-gray-200 dark:text-gray-700">
          {{ index }}
        </span>
      </div>

      <!-- Content area -->
      <div class="min-w-0 flex-1">
        <!-- Row 1: Creation time (primary context) -->
        <div class="mb-1.5 flex items-center gap-2">
          <span class="text-sm text-gray-600 dark:text-gray-300">
            {{ t('web.STATUS.created') }}
          </span>
          <span class="text-sm font-medium text-gray-800 dark:text-gray-200">
            {{ formattedDate }}
          </span>
        </div>

        <!-- Row 2: Status indicators -->
        <div class="mb-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
          <!-- Status dot + label -->
          <div class="flex items-center gap-1.5">
            <span
              :class="['size-2 rounded-full', statusDotClass]"
              aria-hidden="true"></span>
            <span :class="['font-medium', statusTextClass]">
              {{ statusLabel }}
            </span>
          </div>

          <!-- Separator -->
          <span
            v-if="isActive"
            class="text-gray-300 dark:text-gray-600"
            aria-hidden="true">
            &bull;
          </span>

          <!-- Time remaining -->
          <span
            v-if="isActive"
            :class="[
              'tabular-nums',
              isUrgent
                ? 'font-medium text-amber-600 dark:text-amber-400'
                : 'text-gray-500 dark:text-gray-400',
            ]">
            {{ timeRemaining }}
            <span class="sr-only">{{ t('web.STATUS.time_remaining') }}</span>
          </span>

          <!-- Separator -->
          <span
            v-if="hasPassphrase && isActive"
            class="text-gray-300 dark:text-gray-600"
            aria-hidden="true">
            &bull;
          </span>

          <!-- Passphrase indicator -->
          <div
            v-if="hasPassphrase && isActive"
            class="flex items-center gap-1 text-emerald-600 dark:text-emerald-400">
            <OIcon
              collection="heroicons"
              name="key"
              class="size-3.5" />
            <span class="text-xs font-medium">
              {{ t('web.LABELS.passphrase_protected') }}
            </span>
          </div>
        </div>

        <!-- Row 3: Secret identifier (subdued technical detail) -->
        <div class="flex items-center gap-2">
          <router-link
            v-if="isActive"
            :to="`/receipt/${record.extid}`"
            class="font-mono text-xs text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
            {{ displayKey }}
          </router-link>
          <span
            v-else
            class="font-mono text-xs text-gray-400 dark:text-gray-600">
            {{ displayKey }}
          </span>
        </div>
      </div>

      <!-- Actions area - right side -->
      <div class="flex flex-shrink-0 items-center gap-1">
        <template v-if="isActive">
          <!-- Open link button -->
          <a
            :href="shareLink"
            target="_blank"
            rel="noopener noreferrer"
            class="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-300 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300 dark:focus:ring-gray-600"
            :title="t('web.COMMON.view_secret')">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="size-5" />
            <span class="sr-only">{{ t('web.COMMON.view_secret') }}</span>
          </a>

          <!-- Copy button with feedback -->
          <div class="relative">
            <button
              type="button"
              @click="handleCopy"
              class="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-300 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300 dark:focus:ring-gray-600"
              :title="t('web.LABELS.copy_to_clipboard')">
              <OIcon
                collection="material-symbols"
                :name="isCopied ? 'check' : 'content-copy-outline'"
                :class="['size-5', { 'text-emerald-500 dark:text-emerald-400': isCopied }]" />
              <span class="sr-only">{{ t('web.LABELS.copy_to_clipboard') }}</span>
            </button>

            <!-- Copy feedback tooltip -->
            <Transition
              enter-active-class="transition duration-100 ease-out"
              enter-from-class="opacity-0 scale-95"
              enter-to-class="opacity-100 scale-100"
              leave-active-class="transition duration-75 ease-in"
              leave-from-class="opacity-100 scale-100"
              leave-to-class="opacity-0 scale-95">
              <div
                v-if="isCopied"
                class="absolute -top-9 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap rounded-md bg-gray-800 px-2.5 py-1 text-xs font-medium text-white shadow-lg dark:bg-gray-700">
                {{ t('web.STATUS.copied') }}
                <div
                  class="absolute left-1/2 top-full -translate-x-1/2"
                  aria-hidden="true">
                  <div class="size-2 -translate-y-1 rotate-45 bg-gray-800 dark:bg-gray-700"></div>
                </div>
              </div>
            </Transition>
          </div>
        </template>

        <!-- Inactive state indicator -->
        <div
          v-else
          class="px-2 py-1 text-xs text-gray-400 dark:text-gray-500">
          <span :class="statusTextClass">
            {{ statusLabel }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
