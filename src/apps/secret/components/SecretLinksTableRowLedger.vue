<!-- src/apps/secret/components/SecretLinksTableRowLedger.vue -->
<!--
  Ledger variant: The Index as Medallion design.
  Row identity is instantly communicated through a prominent, state-colored medallion.
  Terminal states use distinct visual treatments (muted fills, hatched patterns).

  A/B Test Variant: "ledger"
-->

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
    if (!isActive.value) return;
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
  // isViewed means the secret link page was opened (but not yet revealed)
  const isViewed = computed(() => props.record.isViewed);
  // isReceived means the secret was actually revealed to the recipient
  const isReceived = computed(() => props.record.isReceived);

  // Calculate TTL percentage for urgency
  const getTtlPercentage = computed(() => {
    const maxTtl = 604800; // 7 days
    return Math.floor((props.record.ttl / maxTtl) * 100);
  });

  /**
   * Determine item state based on receipt state.
   * Priority: expired > burned > revealed > previewed > active (new)
   *
   * STATE TERMINOLOGY MIGRATION:
   *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
   *   'received' -> 'revealed'   (secret content decrypted/consumed)
   *
   * Internal state uses new terminology; locale keys support both.
   */
  const itemState = computed((): 'active' | 'previewed' | 'revealed' | 'burned' | 'expired' => {
    if (isExpired.value) return 'expired';
    if (isBurned.value) return 'burned';
    // isReceived/isViewed check both new and legacy API fields
    if (isReceived.value) return 'revealed';
    if (isViewed.value) return 'previewed';
    return 'active';
  });

  /**
   * Medallion configuration based on item state.
   * Active states: filled backgrounds, ring border
   * Terminal states: distinct treatment with shadow/double border effect
   */
  const medallionConfig = computed(() => {
    switch (itemState.value) {
      case 'expired':
        return {
          bgClass: 'bg-gray-100 dark:bg-gray-800',
          textClass: 'text-gray-400 dark:text-gray-500',
          borderClass: 'ring-1 ring-gray-200 dark:ring-gray-700 shadow-inner',
        };
      case 'burned':
        return {
          bgClass: 'bg-red-50 dark:bg-red-900/20 medallion-burned',
          textClass: 'text-red-600 dark:text-red-400',
          borderClass: 'ring-2 ring-red-200 dark:ring-red-800 shadow-inner',
        };
      case 'revealed':
        return {
          bgClass: 'bg-gray-200 dark:bg-gray-700',
          textClass: 'text-gray-600 dark:text-gray-400',
          borderClass: 'ring-1 ring-gray-300 dark:ring-gray-600 shadow-inner',
        };
      case 'previewed':
        return {
          bgClass: 'bg-transparent',
          textClass: 'text-amber-600 dark:text-amber-400',
          borderClass: 'ring-2 ring-amber-400 dark:ring-amber-500',
        };
      default: // active
        return {
          bgClass: 'bg-emerald-500 dark:bg-emerald-600',
          textClass: 'text-white',
          borderClass: 'ring-0',
        };
    }
  });

  // Status configuration for the status line
  const statusConfig = computed(() => {
    switch (itemState.value) {
      case 'expired':
        return {
          symbol: '\u25CB', // ○
          label: t('web.STATUS.expired'),
          colorClass: 'text-gray-500 dark:text-gray-500',
        };
      case 'burned':
        return {
          symbol: '\uD83D\uDD25', // 🔥
          label: t('web.STATUS.burned'),
          colorClass: 'text-red-600 dark:text-red-400',
        };
      case 'revealed':
        return {
          symbol: '\u2713', // ✓
          label: t('web.STATUS.revealed'),
          colorClass: 'text-gray-500 dark:text-gray-400',
        };
      case 'previewed':
        return {
          symbol: '\u25D0', // ◐
          label: t('web.STATUS.previewed'),
          colorClass: 'text-amber-600 dark:text-amber-400',
        };
      default: // active
        return {
          symbol: '\u25CF', // ●
          label: t('web.STATUS.active'),
          colorClass: 'text-emerald-600 dark:text-emerald-400',
        };
    }
  });

  // Display key (truncated shortid)
  const displayKey = computed(() => {
    const shortid = props.record.shortid;
    if (!shortid) return '';
    if (shortid.length <= 4) return shortid;
    return shortid.slice(0, 4);
  });

  // Check if secret is still active (shareable/actionable)
  // Both 'active' (new) and 'previewed' (link opened) states are actionable
  const isActive = computed(() => itemState.value === 'active' || itemState.value === 'previewed');

  // Check if this is a terminal state (no actions available)
  const isTerminal = computed(() => !isActive.value);

  // Time remaining urgency
  const isUrgent = computed(() => getTtlPercentage.value <= 25 && isActive.value);

  // Row styling based on state
  const rowClasses = computed(() => [
    'flex items-start gap-4 py-4',
    isTerminal.value && 'opacity-75',
  ]);
</script>

<template>
  <li :class="rowClasses">
    <!-- Medallion: 48x48px state-colored index -->
    <div
      :class="[
        'flex size-12 flex-shrink-0 items-center justify-center rounded-lg text-lg font-bold tabular-nums transition-all',
        medallionConfig.bgClass,
        medallionConfig.textClass,
        medallionConfig.borderClass,
      ]">
      {{ index }}
    </div>

    <!-- Content area -->
    <div class="min-w-0 flex-1">
      <!-- Line 1: Memo or shortid (editable) -->
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0 flex-1">
          <template v-if="isEditingMemo">
            <input
              ref="memoInputRef"
              v-model="memoInputValue"
              type="text"
              maxlength="100"
              :placeholder="t('web.LABELS.add_memo')"
              class="w-full max-w-sm rounded border border-gray-300 bg-white px-2 py-1 text-sm text-gray-900 placeholder-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100 dark:placeholder-gray-500"
              @keydown="handleMemoKeydown"
              @blur="saveMemo" />
          </template>
          <template v-else>
            <button
              type="button"
              @click="startEditingMemo"
              class="group/memo -ml-0.5 inline-flex max-w-full items-center gap-1.5 rounded px-0.5 text-left transition-colors hover:bg-gray-50 dark:hover:bg-gray-800/50"
              :title="t('web.LABELS.edit_memo')">
              <span
                v-if="record.memo"
                :class="[
                  'line-clamp-1 font-medium',
                  isActive
                    ? 'text-gray-900 dark:text-white'
                    : 'text-gray-600 dark:text-gray-400',
                ]">
                {{ record.memo }}
              </span>
              <span
                v-else
                class="font-mono text-gray-400 dark:text-gray-500">
                {{ displayKey }}
              </span>
              <OIcon
                collection="heroicons"
                name="pencil-square"
                class="size-3 flex-shrink-0 text-gray-300 opacity-0 transition-opacity group-hover/memo:opacity-100 dark:text-gray-600" />
            </button>
          </template>
        </div>

        <!-- Timestamp (top right) -->
        <router-link
          :to="`/receipt/${record.extid}`"
          class="flex-shrink-0 whitespace-nowrap text-xs tabular-nums text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
          <time :datetime="record.createdAt.toISOString()">
            {{ formattedDate }}
          </time>
        </router-link>
      </div>

      <!-- Line 2: Status symbol + label + metadata -->
      <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
        <!-- Status -->
        <span :class="['inline-flex items-center gap-1 font-medium', statusConfig.colorClass]">
          <span aria-hidden="true">{{ statusConfig.symbol }}</span>
          {{ statusConfig.label }}
        </span>

        <!-- Time remaining (only for active states) -->
        <template v-if="isActive">
          <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&middot;</span>
          <span
            :class="[
              isUrgent
                ? 'font-medium text-amber-600 dark:text-amber-400'
                : 'text-gray-500 dark:text-gray-400',
            ]">
            {{ timeRemaining }}
          </span>
        </template>

        <!-- Passphrase indicator -->
        <template v-if="hasPassphrase">
          <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&middot;</span>
          <span
            class="inline-flex items-center gap-1 text-emerald-600 dark:text-emerald-400"
            :title="t('web.LABELS.passphrase_protected')">
            <OIcon
              collection="heroicons"
              name="key"
              class="size-3.5" />
          </span>
        </template>
      </div>

      <!-- Line 3: Actions (only for active/previewed states) -->
      <div
        v-if="isActive"
        class="mt-2 flex items-center gap-1">
        <!-- Open link -->
        <a
          :href="shareLink"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
          :title="t('web.COMMON.view_secret')">
          <OIcon
            collection="heroicons"
            name="arrow-top-right-on-square"
            class="size-3.5" />
          <span class="sr-only">{{ t('web.COMMON.view_secret') }}</span>
        </a>

        <!-- Copy button -->
        <div class="relative">
          <button
            type="button"
            @click="handleCopy"
            :class="[
              'inline-flex items-center gap-1 rounded px-2 py-1 text-xs transition-colors',
              isCopied
                ? 'bg-emerald-50 text-emerald-600 dark:bg-emerald-900/30 dark:text-emerald-400'
                : 'text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200',
            ]"
            :title="t('web.LABELS.copy_to_clipboard')">
            <OIcon
              collection="material-symbols"
              :name="isCopied ? 'check' : 'content-copy-outline'"
              class="size-3.5" />
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
              class="absolute -top-8 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap rounded bg-gray-800 px-2 py-1 text-xs font-medium text-white shadow-lg dark:bg-gray-700">
              {{ t('web.STATUS.copied') }}
            </div>
          </Transition>
        </div>
      </div>
    </div>
  </li>

  <!-- Row separator (if not last item) -->
  <div
    v-if="!isLast"
    class="border-b border-gray-100 dark:border-gray-800"
    aria-hidden="true"></div>
</template>

<style scoped>
  /*
   * Burned state: CSS hatched/striped pattern for medallion
   * Creates diagonal lines to indicate destruction
   */
  .medallion-burned {
    background-image: repeating-linear-gradient(
      135deg,
      transparent,
      transparent 2px,
      rgb(254 202 202 / 0.5) 2px,
      rgb(254 202 202 / 0.5) 4px
    );
  }

  :root.dark .medallion-burned {
    background-image: repeating-linear-gradient(
      135deg,
      transparent,
      transparent 2px,
      rgb(127 29 29 / 0.3) 2px,
      rgb(127 29 29 / 0.3) 4px
    );
  }
</style>
