<!-- src/apps/secret/components/SecretLinksTableRowTimeline.vue -->

<!--
  Timeline variant: Feed item for recent secrets with consistent layout across all states.
  States are communicated through status badges and subtle visual cues
  rather than dramatic layout changes.

  A/B Test Variant: "timeline" (original design)
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

  // Status configuration based on item state
  const statusConfig = computed(() => {
    switch (itemState.value) {
      case 'expired':
        return {
          icon: 'clock',
          badgeClass: 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400',
          label: t('web.STATUS.expired'),
        };
      case 'burned':
        return {
          icon: 'fire',
          badgeClass: 'bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-400',
          label: t('web.STATUS.burned'),
        };
      case 'revealed':
        return {
          icon: 'check-circle',
          badgeClass: 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400',
          label: t('web.STATUS.revealed'),
        };
      case 'previewed':
        return {
          icon: 'eye',
          badgeClass: 'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
          label: t('web.STATUS.previewed'),
        };
      default: // active (new)
        return {
          icon: 'paper-airplane',
          badgeClass: 'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400',
          label: t('web.STATUS.active'),
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

  // Time remaining urgency
  const isUrgent = computed(() => getTtlPercentage.value <= 25 && isActive.value);

  // Row styling based on state
  const rowClasses = computed(() => [
    'relative flex items-start gap-4 pb-6',
    !isActive.value && 'opacity-60',
  ]);

  // Index number styling based on state
  const indexClasses = computed(() => [
    'flex size-8 select-none items-center justify-center font-mono text-xl font-semibold tabular-nums transition-colors',
    isActive.value ? 'text-gray-300 dark:text-gray-600' : 'text-gray-200 dark:text-gray-700',
  ]);
</script>

<template>
  <li class="relative">
    <!-- Timeline connector line -->
    <span
      v-if="!isLast"
      class="absolute left-4 top-9 -ml-px h-[calc(100%-0.5rem)] w-0.5 bg-gradient-to-b from-gray-200 to-transparent dark:from-gray-700/50"
      aria-hidden="true" ></span>

    <div :class="rowClasses">
      <!-- Index number -->
      <div class="flex-shrink-0 pt-0.5">
        <span :class="indexClasses">
          {{ index }}
        </span>
      </div>

      <!-- Content area - consistent layout for all states -->
      <div class="min-w-0 flex-1 pt-0.5">
        <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
          <!-- Left: memo, status, metadata -->
          <div class="min-w-0 flex-1 space-y-1.5">
            <!-- Memo row - always editable -->
            <div class="flex items-center gap-2">
              <template v-if="isEditingMemo">
                <input
                  ref="memoInputRef"
                  v-model="memoInputValue"
                  type="text"
                  maxlength="100"
                  :placeholder="t('web.LABELS.add_memo')"
                  class="w-full max-w-xs rounded border border-gray-300 bg-white px-2 py-1 text-sm text-gray-900 placeholder-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100 dark:placeholder-gray-500"
                  @keydown="handleMemoKeydown"
                  @blur="saveMemo" />
              </template>
              <template v-else>
                <button
                  type="button"
                  @click="startEditingMemo"
                  class="group/memo -ml-0.5 inline-flex max-w-full items-center gap-1.5 rounded px-0.5 py-0.5 text-left transition-colors hover:bg-gray-50 dark:hover:bg-gray-800/50"
                  :title="t('web.LABELS.edit_memo')">
                  <span
                    v-if="record.memo"
                    :class="[
                      'line-clamp-1 text-sm font-medium',
                      isActive
                        ? 'text-gray-900 dark:text-white'
                        : 'text-gray-700 dark:text-gray-300',
                    ]">
                    {{ record.memo }}
                    <!-- Short ID - always shown -->
                    <span
                      class="text-gray-300 dark:text-gray-600"
                      aria-hidden="true"
                      >&middot;</span
                    >
                    <router-link
                      :to="`/receipt/${record.extid}`"
                      class="font-mono text-xs text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
                      {{ displayKey }}
                    </router-link>
                  </span>
                  <span
                    v-else
                    class="text-sm text-gray-400 dark:text-gray-500">
                    {{ displayKey }}
                  </span>
                  <OIcon
                    collection="heroicons"
                    name="pencil-square"
                    class="size-3 flex-shrink-0 text-gray-300 opacity-0 transition-opacity group-hover/memo:opacity-100 dark:text-gray-600" />
                </button>
              </template>
            </div>

            <!-- Status row: badge + metadata - consistent for all states -->
            <div class="flex flex-wrap items-center gap-2 text-sm">
              <!-- Status badge -->
              <span
                :class="[
                  'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
                  statusConfig.badgeClass,
                ]">
                {{ statusConfig.label }}
              </span>

              <!-- Time remaining (only for active) -->
              <template v-if="isActive">
                <span
                  class="text-gray-300 dark:text-gray-600"
                  aria-hidden="true"
                  >&middot;</span
                >
                <span
                  :class="[
                    'text-sm',
                    isUrgent
                      ? 'font-medium text-amber-600 dark:text-amber-400'
                      : 'text-gray-500 dark:text-gray-400',
                  ]">
                  {{ timeRemaining }}
                </span>
              </template>

              <!-- Passphrase indicator -->
              <template v-if="hasPassphrase">
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

          <!-- Right: timestamp + actions -->
          <div class="flex flex-shrink-0 items-center gap-2">
            <!-- Timestamp - always shown -->
            <router-link :to="`/receipt/${record.extid}`">
              <time
                :datetime="record.createdAt.toISOString()"
                class="whitespace-nowrap text-xs tabular-nums text-gray-400 dark:text-gray-500">
                {{ formattedDate }}
              </time>
            </router-link>

            <!-- Actions (only for active secrets) -->
            <div
              v-if="isActive"
              class="flex items-center">
              <!-- Open link -->
              <a
                :href="shareLink"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
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
                  class="rounded p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-800 dark:hover:text-gray-300"
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
            </div>
          </div>
        </div>
      </div>
    </div>
  </li>
</template>
