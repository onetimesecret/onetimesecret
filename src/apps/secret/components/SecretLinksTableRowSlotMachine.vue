<!-- src/apps/secret/components/SecretLinksTableRowSlotMachine.vue -->

<!--
  Slot Machine variant: The entire row takes on the character of its state.
  Each row is a card with state-specific border and background treatment.
  Index is bold, prominent, in a left gutter.

  A/B Test Variant: "slotmachine"

  State visual treatments:
  - Active: solid border, white/transparent bg, full opacity
  - Previewed: dashed border (amber), subtle amber tint bg
  - Revealed: subtle gray fill, muted colors
  - Burned: heavier fill (red-tinted), red border
  - Expired: gray fill similar to revealed
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
  // isPreviewed means the secret link page was opened (confirmation shown)
  const isPreviewed = computed(() => props.record.isPreviewed);
  // isRevealed means the secret was actually decrypted/consumed
  const isRevealed = computed(() => props.record.isRevealed);

  // Calculate TTL percentage for urgency
  const getTtlPercentage = computed(() => {
    const maxTtl = 604800; // 7 days
    return Math.floor((props.record.ttl / maxTtl) * 100);
  });

  /**
   * Determine item state based on receipt state.
   * Priority: expired > burned > revealed > previewed > active (new)
   */
  const itemState = computed((): 'active' | 'previewed' | 'revealed' | 'burned' | 'expired' => {
    if (isExpired.value) return 'expired';
    if (isBurned.value) return 'burned';
    if (isRevealed.value) return 'revealed';
    if (isPreviewed.value) return 'previewed';
    return 'active';
  });

  // Slot Machine status configuration with symbols and explanations
  const statusConfig = computed(() => {
    switch (itemState.value) {
      case 'expired':
        return {
          symbol: '\u25CB', // Circle (empty)
          label: t('web.STATUS.expired'),
          explanation: t('web.STATUS.expired_description'),
          colorClass: 'text-gray-500 dark:text-gray-400',
        };
      case 'burned':
        return {
          symbol: '\uD83D\uDD25', // Fire emoji
          label: t('web.STATUS.burned'),
          explanation: t('web.STATUS.burned_description'),
          colorClass: 'text-red-600 dark:text-red-400',
        };
      case 'revealed':
        return {
          symbol: '\u2713', // Checkmark
          label: t('web.STATUS.revealed'),
          explanation: t('web.STATUS.revealed_description'),
          colorClass: 'text-gray-500 dark:text-gray-400',
        };
      case 'previewed':
        return {
          symbol: '\u25D0', // Half circle
          label: t('web.STATUS.previewed'),
          explanation: t('web.STATUS.previewed_description'),
          colorClass: 'text-amber-600 dark:text-amber-400',
        };
      default: // active
        return {
          symbol: '\u25CF', // Filled circle
          label: t('web.STATUS.active'),
          explanation: '',
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

  // Card styling based on state - the "slot machine" atmosphere
  const cardClasses = computed(() => {
    const base = 'rounded-lg p-4 transition-all duration-200';

    switch (itemState.value) {
      case 'active':
        return [
          base,
          'border border-gray-200 dark:border-gray-700',
          'bg-white dark:bg-gray-900',
        ];
      case 'previewed':
        return [
          base,
          'border border-dashed border-amber-300 dark:border-amber-600',
          'bg-amber-50/30 dark:bg-amber-900/10',
        ];
      case 'revealed':
        return [
          base,
          'border border-gray-200 dark:border-gray-700',
          'bg-gray-100 dark:bg-gray-800/50',
          'opacity-75',
        ];
      case 'burned':
        return [
          base,
          'border border-red-200 dark:border-red-800',
          'bg-red-50 dark:bg-red-900/20',
          'opacity-75',
        ];
      case 'expired':
        return [
          base,
          'border border-gray-200 dark:border-gray-700',
          'bg-gray-100 dark:bg-gray-800/50',
          'opacity-60',
        ];
      default:
        return [base, 'border border-gray-200 dark:border-gray-700'];
    }
  });

  // Index number styling - large and bold in the gutter
  const indexClasses = computed(() => [
    'flex-shrink-0 text-2xl font-bold tabular-nums select-none w-10 text-center',
    isActive.value
      ? 'text-gray-400 dark:text-gray-500'
      : 'text-gray-300 dark:text-gray-600',
  ]);
</script>

<template>
  <li :class="['mb-3', isLast && 'mb-0']">
    <div :class="cardClasses">
      <div class="flex gap-4">
        <!-- Index gutter -->
        <div :class="indexClasses">
          {{ index }}
        </div>

        <!-- Main content area -->
        <div class="min-w-0 flex-1">
          <!-- Line 1: Memo/ID | time remaining | timestamp | actions -->
          <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
            <!-- Left: Memo or shortid -->
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
                  class="group/memo inline-flex max-w-full items-center gap-1.5 text-left transition-colors hover:text-gray-600 dark:hover:text-gray-300"
                  :title="t('web.LABELS.edit_memo')">
                  <span
                    v-if="record.memo"
                    :class="[
                      'truncate text-sm font-medium',
                      isActive
                        ? 'text-gray-900 dark:text-white'
                        : 'text-gray-600 dark:text-gray-400',
                    ]">
                    {{ record.memo }}
                  </span>
                  <span
                    v-else
                    class="font-mono text-sm text-gray-400 dark:text-gray-500">
                    {{ displayKey }}
                  </span>
                  <OIcon
                    collection="heroicons"
                    name="pencil-square"
                    class="size-3 flex-shrink-0 text-gray-300 opacity-0 transition-opacity group-hover/memo:opacity-100 dark:text-gray-600" />
                </button>
              </template>
            </div>

            <!-- Center/Right: Time remaining + timestamp + actions -->
            <div class="flex flex-shrink-0 items-center gap-3 text-sm">
              <!-- Time remaining (only for active states) -->
              <span
                v-if="isActive"
                :class="[
                  isUrgent
                    ? 'font-medium text-amber-600 dark:text-amber-400'
                    : 'text-gray-500 dark:text-gray-400',
                ]">
                {{ timeRemaining }}
              </span>

              <!-- Timestamp -->
              <router-link
                :to="`/receipt/${record.extid}`"
                class="whitespace-nowrap text-xs tabular-nums text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
                <time :datetime="record.createdAt.toISOString()">
                  {{ formattedDate }}
                </time>
              </router-link>

              <!-- Actions for active states -->
              <template v-if="isActive">
                <!-- Open link -->
                <a
                  :href="shareLink"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
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
                    class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
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
                      class="absolute -top-8 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap rounded bg-gray-800 px-2 py-1 text-xs font-medium text-white shadow-lg dark:bg-gray-700">
                      {{ t('web.STATUS.copied') }}
                    </div>
                  </Transition>
                </div>
              </template>
            </div>
          </div>

          <!-- Line 2: Status symbol + label + explanation | passphrase indicator -->
          <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
            <!-- Status indicator -->
            <div class="flex items-center gap-2">
              <span
                :class="['text-base', statusConfig.colorClass]"
                aria-hidden="true">
                {{ statusConfig.symbol }}
              </span>
              <span :class="['font-medium', statusConfig.colorClass]">
                {{ statusConfig.label }}
              </span>
              <span
                v-if="statusConfig.explanation && isTerminal"
                class="text-gray-500 dark:text-gray-400">
                &mdash; {{ statusConfig.explanation }}
              </span>
            </div>

            <!-- Passphrase indicator (for active states) -->
            <template v-if="hasPassphrase && isActive">
              <span
                class="text-gray-300 dark:text-gray-600"
                aria-hidden="true"
                >&middot;</span
              >
              <span class="inline-flex items-center gap-1 text-emerald-600 dark:text-emerald-400">
                <OIcon
                  collection="heroicons"
                  name="key"
                  class="size-3" />
                <span class="text-xs font-medium">{{
                  t('web.LABELS.passphrase_protected')
                }}</span>
              </span>
            </template>
          </div>
        </div>
      </div>
    </div>
  </li>
</template>
