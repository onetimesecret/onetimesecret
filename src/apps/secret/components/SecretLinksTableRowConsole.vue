<!-- src/apps/secret/components/SecretLinksTableRowConsole.vue -->
<!--
  Console-style feed item for recent secrets.
  Monospace precision design embracing the security/technical nature.
  Uses tree-style metadata display with ASCII characters.

  ENCRYPTION SIGNAL SYSTEM (Three-Layer):
  All secrets are encrypted (EO). Some also have passphrase protection (EAP).
  The UI distinguishes these with redundant visual cues:

  Layer 1 - Persistent iconography:
    - EO:  Single padlock icon (mid-gray)
    - EAP: Padlock + keyhole badge (outline, 1/4 size, lower-right)

  Layer 2 - Visual hierarchy:
    - Same saturation for both (no downgrading EO)
    - EAP: Subtle pulse animation on keyhole badge (opacity 0.6→1.0→0.6, 1.5s)

  Layer 3 - On-demand info:
    - Hover/tap shows tooltip with explanation
    - EO:  "Encrypted"
    - EAP: "Encrypted + passphrase protected"
-->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
  import { formatTTL } from '@/utils/formatters';
  import { formatDistanceToNow } from 'date-fns';
  import { storeToRefs } from 'pinia';
  import { ref, computed, nextTick, onMounted } from 'vue';

  // Layer 2: Track viewport entry for EAP pulse animation
  const rowRef = ref<HTMLElement | null>(null);
  const hasEnteredViewport = ref(false);

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

  // Layer 3: Encryption tooltip visibility
  const showEncryptionTooltip = ref(false);

  // Layer 2: Observe viewport entry for EAP pulse animation
  onMounted(() => {
    if (!rowRef.value) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting && !hasEnteredViewport.value) {
          hasEnteredViewport.value = true;
          observer.disconnect();
        }
      },
      { threshold: 0.5 }
    );

    observer.observe(rowRef.value);
  });

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

  // Console-style status configuration
  const statusConfig = computed(() => {
    switch (itemState.value) {
      case 'expired':
        return {
          symbol: '\u25CB', // ○
          label: 'EXPIRED',
          colorClass: 'text-gray-500 dark:text-gray-500',
          bgClass: '',
        };
      case 'burned':
        return {
          symbol: '\u2715', // ✕
          label: 'BURNED',
          colorClass: 'text-red-600 dark:text-red-400',
          bgClass: '',
        };
      case 'revealed':
        return {
          symbol: '\u2713', // ✓
          label: 'REVEALED',
          colorClass: 'text-gray-500 dark:text-gray-400',
          bgClass: '',
        };
      case 'previewed':
        return {
          symbol: '\u25D0', // ◐
          label: 'PREVIEWED',
          colorClass: 'text-amber-600 dark:text-amber-400',
          bgClass: '',
        };
      default: // active
        return {
          symbol: '\u25CF', // ●
          label: 'ACTIVE',
          colorClass: 'text-emerald-600 dark:text-emerald-400',
          bgClass: '',
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
    'font-mono text-sm',
    isTerminal.value && 'opacity-60',
  ]);
</script>

<template>
  <li ref="rowRef" :class="rowClasses">
    <!-- Header line: #N  🔒  SYMBOL STATUS  Memo/ID -->
    <div class="flex items-start gap-2">
      <!-- Index prefix -->
      <span class="select-none text-gray-400 dark:text-gray-500">
        #{{ index }}
      </span>

      <!--
        LAYER 1 & 2: Encryption iconography
        - All items show padlock (EO baseline)
        - EAP items add keyhole badge with pulse animation
      -->
      <div
        class="group/encrypt relative flex-shrink-0"
        @mouseenter="showEncryptionTooltip = true"
        @mouseleave="showEncryptionTooltip = false"
        @focus="showEncryptionTooltip = true"
        @blur="showEncryptionTooltip = false"
        tabindex="0"
        role="img"
        :aria-label="hasPassphrase ? `${t('web.LABELS.encrypted')} + ${t('web.LABELS.passphrase_protected')}` : t('web.LABELS.encrypted')">
        <!-- Padlock icon (always shown, mid-gray, same saturation for EO and EAP) -->
        <OIcon
            v-if="hasPassphrase"
            collection="tabler"
            name="lock-check"
            size="5"
        />
        <OIcon
            v-else
            collection="tabler"
            name="lock"
            size="5"
        />

        <!-- LAYER 3: Tooltip on hover/focus -->
        <Transition
          enter-active-class="transition duration-150 ease-out"
          enter-from-class="opacity-0 translate-y-1"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition duration-100 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 translate-y-1">
          <div
            v-if="showEncryptionTooltip"
            class="absolute -top-8 left-1/2 z-20 -translate-x-1/2 whitespace-nowrap rounded bg-gray-800 px-2 py-1 text-xs font-medium text-white shadow-lg dark:bg-gray-700">
            <template v-if="hasPassphrase">
              {{ t('web.LABELS.encrypted') }}
              <span class="text-teal-300"> + {{ t('web.LABELS.passphrase_protected') }}</span>
            </template>
            <template v-else>
              {{ t('web.LABELS.encrypted') }}
            </template>
            <!-- Tooltip arrow -->
            <div
              class="absolute -bottom-1 left-1/2 size-2 -translate-x-1/2 rotate-45 bg-gray-800 dark:bg-gray-700"
              aria-hidden="true"></div>
          </div>
        </Transition>
      </div>

      <!-- Status label -->
      <span :class="['font-semibold tracking-wide', statusConfig.colorClass]">
        {{ statusConfig.label }}
      </span>

      <!-- Memo or shortid -->
      <div class="min-w-0 flex-1">
        <template v-if="isEditingMemo">
          <input
            ref="memoInputRef"
            v-model="memoInputValue"
            type="text"
            maxlength="100"
            :placeholder="t('web.LABELS.add_memo')"
            class="w-full max-w-xs rounded border border-gray-300 bg-white px-2 py-0.5 font-mono text-sm text-gray-900 placeholder-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100 dark:placeholder-gray-500"
            @keydown="handleMemoKeydown"
            @blur="saveMemo" />
        </template>
        <template v-else>
          <button
            type="button"
            @click="startEditingMemo"
            class="group/memo inline-flex max-w-full items-center gap-1 text-left transition-colors hover:text-gray-600 dark:hover:text-gray-300"
            :title="t('web.LABELS.edit_memo')">
            <span
              v-if="record.memo"
              :class="[
                'truncate',
                isActive
                  ? 'text-gray-900 dark:text-gray-100'
                  : 'text-gray-600 dark:text-gray-400',
              ]">
              {{ record.memo }}
            </span>
            <span
              v-else
              class="text-gray-400 dark:text-gray-500">
              {{ displayKey }}
            </span>
            <span
              class="text-xs text-gray-300 opacity-0 transition-opacity group-hover/memo:opacity-100 dark:text-gray-600">
              [edit]
            </span>
          </button>
        </template>
      </div>

      <!-- Actions (header line, right side) -->
      <div v-if="isActive" class="flex flex-shrink-0 items-center gap-2">
        <!-- Copy button -->
        <button
          type="button"
          @click="handleCopy"
          :class="[
            'rounded border px-2 py-0.5 text-xs font-medium transition-colors',
            isCopied
              ? 'border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'
              : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700',
          ]"
          :title="t('web.LABELS.copy_to_clipboard')">
          {{ isCopied ? '[ COPIED ]' : '[ COPY ]' }}
        </button>

        <!-- Open link button -->
        <a
          :href="shareLink"
          target="_blank"
          rel="noopener noreferrer"
          class="rounded border border-gray-300 bg-white px-2 py-0.5 text-xs font-medium text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
          :title="t('web.COMMON.view_secret')">
          [ OPEN &#8599; ]
        </a>
      </div>
    </div>

    <!-- Metadata tree (full tree for active/previewed, minimal for terminal) -->
    <div class="ml-4 mt-1 space-y-0.5 text-gray-600 dark:text-gray-400">
      <template v-if="isActive">
        <!-- Expires line with timestamp on right -->
        <div class="flex items-center justify-between">
          <div class="flex items-center">
            <span class="mr-2 select-none text-gray-300 dark:text-gray-600" aria-hidden="true">└─</span>
            <span>expires:</span>
            <span
              :class="[
                'ml-1',
                isUrgent
                  ? 'font-semibold text-amber-600 dark:text-amber-400'
                  : 'text-gray-700 dark:text-gray-300',
              ]">
              {{ timeRemaining }}
            </span>
          </div>

          <!-- Created timestamp -->
          <router-link
            :to="`/receipt/${record.extid}`"
            class="text-xs text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
            <time :datetime="record.createdAt.toISOString()">
              {{ formattedDate }}
            </time>
          </router-link>
        </div>
      </template>

      <!-- Terminal states: minimal info -->
      <template v-else>
        <div class="flex items-center">
          <span class="mr-2 select-none text-gray-300 dark:text-gray-600" aria-hidden="true">└─</span>
          <span v-if="itemState === 'revealed'">viewed:</span>
          <span v-else-if="itemState === 'burned'">destroyed:</span>
          <span v-else>expired:</span>
          <router-link
            :to="`/receipt/${record.extid}`"
            class="ml-1 text-gray-500 transition-colors hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
            <time :datetime="record.createdAt.toISOString()">
              {{ formattedDate }}
            </time>
          </router-link>
        </div>
      </template>
    </div>

    <!-- Separator line (if not last item) -->
    <div
      v-if="!isLast"
      class="my-4 border-t border-dashed border-gray-200 dark:border-gray-700"
      aria-hidden="true"></div>
  </li>
</template>

<style scoped>
  /*
   * Layer 2: EAP pulse animation
   * Subtle opacity pulse (0.6 → 1.0 → 0.6) over 1.5s
   * Only triggers once when row enters viewport
   * Motion is unique to EAP, teaching users "motion = needs passphrase"
   */
  @keyframes eap-pulse {
    0%,
    100% {
      opacity: 0.6;
    }
    50% {
      opacity: 1;
    }
  }

  .animate-eap-pulse {
    animation: eap-pulse 1.5s ease-in-out 1;
  }
</style>
