<!-- src/apps/secret/components/SecretLinksTableRow.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { formatTTL } from '@/utils/formatters';
import { formatDistanceToNow } from 'date-fns';
import { storeToRefs } from 'pinia';
import { ref, computed, nextTick } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  record: RecentSecretRecord;
  /** Row index (1-based) for visual reference */
  index: number;
  /** Whether this is the last item (no connector line) */
  isLast?: boolean;
}>();

const emit = defineEmits<{
  copy: [];
  delete: [record: RecentSecretRecord];
  'update:memo': [id: string, memo: string];
}>();

// Track if this row's content was copied
const isCopied = ref(false);

// Memo editing state
const isEditingMemo = ref(false);
const memoInputValue = ref('');
const memoInputRef = ref<HTMLInputElement | null>(null);

const startEditingMemo = async () => {
  memoInputValue.value = props.record.memo || '';
  isEditingMemo.value = true;
  await nextTick();
  memoInputRef.value?.focus();
};

const saveMemo = () => {
  const trimmed = memoInputValue.value.trim();
  if (trimmed !== (props.record.memo || '')) {
    emit('update:memo', props.record.id, trimmed);
  }
  isEditingMemo.value = false;
};

const cancelEditingMemo = () => {
  isEditingMemo.value = false;
  memoInputValue.value = props.record.memo || '';
};

const handleMemoKeydown = (event: KeyboardEvent) => {
  if (event.key === 'Enter') {
    saveMemo();
  } else if (event.key === 'Escape') {
    cancelEditingMemo();
  }
};

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
    setTimeout(() => {
      isCopied.value = false;
    }, 1500);
  } catch (err) {
    console.error('Failed to copy text: ', err);
  }
};

// Format creation date
const formattedDate = computed(() =>
  formatDistanceToNow(props.record.createdAt, { addSuffix: true })
);

// Compute security status and time remaining
const hasPassphrase = computed(() => props.record.hasPassphrase);
const timeRemaining = computed(() => formatTTL(props.record.ttl));

// Secret state computations
const isExpired = computed(() => props.record.isExpired || props.record.ttl <= 0);
const isBurned = computed(() => props.record.isBurned);
const isViewed = computed(() => props.record.isViewed);
const isReceived = computed(() => props.record.isReceived);

// Calculate TTL percentage for urgency
const getTtlPercentage = computed(() => {
  const maxTtl = 604800; // 7 days
  return Math.floor((props.record.ttl / maxTtl) * 100);
});

// Status icon and colors
const statusConfig = computed(() => {
  if (isExpired.value) {
    return {
      icon: 'clock',
      bgClass: 'bg-gray-100 dark:bg-gray-800',
      iconClass: 'text-gray-400 dark:text-gray-500',
      label: t('web.STATUS.expired'),
    };
  }
  if (isBurned.value) {
    return {
      icon: 'fire',
      bgClass: 'bg-red-50 dark:bg-red-900/20',
      iconClass: 'text-red-500 dark:text-red-400',
      label: t('web.STATUS.burned'),
    };
  }
  if (isViewed.value) {
    return {
      icon: 'eye',
      bgClass: 'bg-amber-50 dark:bg-amber-900/20',
      iconClass: 'text-amber-500 dark:text-amber-400',
      label: t('web.STATUS.viewed'),
    };
  }
  if (isReceived.value) {
    return {
      icon: 'check-circle',
      bgClass: 'bg-emerald-50 dark:bg-emerald-900/20',
      iconClass: 'text-emerald-500 dark:text-emerald-400',
      label: t('web.STATUS.received'),
    };
  }
  return {
    icon: 'paper-airplane',
    bgClass: 'bg-brand-50 dark:bg-brand-900/20',
    iconClass: 'text-brand-500 dark:text-brand-400',
    label: t('web.STATUS.active'),
  };
});

// Display key (truncated)
const displayKey = computed(() => {
  const shortid = props.record.shortid;
  if (!shortid || shortid.length <= 8) return shortid;
  return `${shortid.slice(0, 4)}...${shortid.slice(-4)}`;
});

// Check if secret is still active
const isActive = computed(() => !isExpired.value && !isBurned.value);

// Time remaining urgency
const isUrgent = computed(() => getTtlPercentage.value <= 25 && isActive.value);
</script>

<template>
  <li class="relative">
    <!-- Timeline connector line -->
    <span
      v-if="!isLast"
      class="absolute left-4 top-9 -ml-px h-[calc(100%-0.5rem)] w-0.5 bg-gray-200 dark:bg-gray-700"
      aria-hidden="true" ></span>

    <div class="relative flex gap-4 pb-6">
      <!-- Status icon node -->
      <div class="relative flex-shrink-0">
        <span
          :class="[
            statusConfig.bgClass,
            'flex size-8 items-center justify-center rounded-full ring-4 ring-white dark:ring-gray-900',
          ]">
          <OIcon
            collection="heroicons"
            :name="statusConfig.icon"
            :class="['size-4', statusConfig.iconClass]"
            aria-hidden="true" />
        </span>
      </div>

      <!-- Content area -->
      <div class="min-w-0 flex-1 pt-0.5">
        <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
          <!-- Left: Primary info -->
          <div class="min-w-0 flex-1">
            <!-- Memo or "Add note" -->
            <div class="mb-1">
              <template v-if="isEditingMemo">
                <input
                  ref="memoInputRef"
                  v-model="memoInputValue"
                  type="text"
                  maxlength="100"
                  :placeholder="t('web.LABELS.add_note')"
                  class="w-full max-w-xs rounded-md border border-gray-300 bg-white px-2 py-1 text-sm text-gray-900 placeholder-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100 dark:placeholder-gray-500"
                  @keydown="handleMemoKeydown"
                  @blur="saveMemo" />
              </template>
              <button
                v-else
                type="button"
                @click="startEditingMemo"
                class="group/memo inline-flex items-center gap-1.5 rounded-md px-1 py-0.5 text-left transition-colors hover:bg-gray-100 dark:hover:bg-gray-800"
                :title="t('web.LABELS.edit_note')">
                <span
                  v-if="record.memo"
                  class="line-clamp-1 text-sm font-medium text-gray-900 dark:text-white">
                  {{ record.memo }}
                </span>
                <span
                  v-else
                  class="text-sm text-gray-400 dark:text-gray-500">
                  {{ t('web.LABELS.add_note') }}
                </span>
                <OIcon
                  collection="heroicons"
                  name="pencil-square"
                  class="size-3 flex-shrink-0 text-gray-300 transition-colors group-hover/memo:text-gray-500 dark:text-gray-600 dark:group-hover/memo:text-gray-400" />
              </button>
            </div>

            <!-- Secondary info: status, time, passphrase -->
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-gray-500 dark:text-gray-400">
              <span :class="statusConfig.iconClass" class="font-medium">
                {{ statusConfig.label }}
              </span>

              <template v-if="isActive">
                <span aria-hidden="true">&middot;</span>
                <span :class="{ 'font-medium text-amber-600 dark:text-amber-400': isUrgent }">
                  {{ timeRemaining }}
                </span>
              </template>

              <template v-if="hasPassphrase">
                <span aria-hidden="true">&middot;</span>
                <span class="inline-flex items-center gap-1 text-emerald-600 dark:text-emerald-400">
                  <OIcon
                    collection="heroicons"
                    name="key"
                    class="size-3" />
                  <span class="text-xs font-medium">{{ t('web.LABELS.passphrase_protected') }}</span>
                </span>
              </template>
            </div>
          </div>

          <!-- Right: Timestamp and actions -->
          <div class="flex flex-shrink-0 items-center gap-3">
            <!-- Timestamp -->
            <time
              :datetime="record.createdAt.toISOString()"
              class="text-sm tabular-nums text-gray-500 dark:text-gray-400">
              {{ formattedDate }}
            </time>

            <!-- Actions -->
            <div v-if="isActive" class="flex items-center gap-1">
              <!-- Open link -->
              <a
                :href="shareLink"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-md p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
                :title="t('web.COMMON.view_secret')">
                <OIcon
                  collection="heroicons"
                  name="arrow-top-right-on-square"
                  class="size-4" />
                <span class="sr-only">{{ t('web.COMMON.view_secret') }}</span>
              </a>

              <!-- Copy button -->
              <div class="relative">
                <button
                  type="button"
                  @click="handleCopy"
                  class="rounded-md p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
                  :title="t('web.LABELS.copy_to_clipboard')">
                  <OIcon
                    collection="material-symbols"
                    :name="isCopied ? 'check' : 'content-copy-outline'"
                    :class="['size-4', { 'text-emerald-500 dark:text-emerald-400': isCopied }]" />
                  <span class="sr-only">{{ t('web.LABELS.copy_to_clipboard') }}</span>
                </button>

                <!-- Copy tooltip -->
                <Transition
                  enter-active-class="transition duration-100 ease-out"
                  enter-from-class="opacity-0 scale-95"
                  enter-to-class="opacity-100 scale-100"
                  leave-active-class="transition duration-75 ease-in"
                  leave-from-class="opacity-100 scale-100"
                  leave-to-class="opacity-0 scale-95">
                  <div
                    v-if="isCopied"
                    class="absolute -top-8 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap rounded-md bg-gray-800 px-2 py-1 text-xs font-medium text-white shadow-lg dark:bg-gray-700">
                    {{ t('web.STATUS.copied') }}
                  </div>
                </Transition>
              </div>
            </div>
          </div>
        </div>

        <!-- Secret ID (subtle, tertiary info) -->
        <div class="mt-1">
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
    </div>
  </li>
</template>
