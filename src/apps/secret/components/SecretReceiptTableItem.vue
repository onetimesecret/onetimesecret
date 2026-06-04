<!-- src/apps/secret/components/SecretReceiptTableItem.vue -->

<!--
  Console-style receipt item for dashboard.
  Monospace precision design matching SecretLinksTableRowConsole.
  Uses tree-style metadata display with ASCII characters.

  ENCRYPTION SIGNAL SYSTEM (Three-Layer):
  All secrets are encrypted (EO). Some also have passphrase protection (EAP).
  The UI distinguishes these with redundant visual cues:

  Layer 1 - Persistent iconography:
    - EO:  Single padlock icon (mid-gray)
    - EAP: Padlock + checkmark badge (lock-check icon)

  Layer 2 - Visual hierarchy:
    - Same saturation for both (no downgrading EO)

  Layer 3 - On-demand info:
    - Hover/tap shows tooltip with explanation
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { ReceiptList } from '@/schemas/shapes/v3/receipt';
import { formatTTL } from '@/utils/formatters';
import { formatDistanceToNow } from 'date-fns';
import { storeToRefs } from 'pinia';
import { useRouter } from 'vue-router';
import { ref, computed } from 'vue';

const router = useRouter();
const { t } = useI18n();

interface Props {
  secretReceipt: ReceiptList;
  /** Row index (1-based) for visual reference */
  index: number;
  /** Whether this is the last item (no connector line) */
  isLast?: boolean;
}

const props = defineProps<Props>();

const emit = defineEmits<{
  copy: [];
  burn: [receipt: ReceiptList];
}>();

// Track if this row's content was copied
const isCopied = ref(false);

// Layer 3: Encryption tooltip visibility
const showEncryptionTooltip = ref(false);

const bootstrapStore = useBootstrapStore();
const { site_host } = storeToRefs(bootstrapStore);

// Create shareable link with proper domain
const shareLink = computed(() => {
  const shareDomain = props.secretReceipt.share_domain ?? site_host.value;
  return `https://${shareDomain}/secret/${props.secretReceipt.secret_shortid}`;
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
  formatDistanceToNow(props.secretReceipt.created, { addSuffix: true })
);

// Compute security status and time remaining
const hasPassphrase = computed(() => props.secretReceipt.has_passphrase);
const timeRemaining = computed(() => formatTTL(props.secretReceipt.secret_ttl));

// Secret state computations
const isExpired = computed(() => props.secretReceipt.is_expired || props.secretReceipt.secret_ttl <= 0);
const isBurned = computed(() => props.secretReceipt.is_burned);
const isPreviewed = computed(() => props.secretReceipt.is_previewed);
const isRevealed = computed(() => props.secretReceipt.is_revealed);
const isDestroyed = computed(() => props.secretReceipt.is_destroyed);

// Calculate TTL percentage for urgency
const getTtlPercentage = computed(() => {
  const maxTtl = 604800; // 7 days
  return Math.floor((props.secretReceipt.secret_ttl / maxTtl) * 100);
});

/**
 * Determine item state based on receipt state.
 * Priority: burned > revealed > expired > previewed > new
 *
 * Burned and revealed must take precedence over expired/destroyed because
 * the backend sets multiple flags simultaneously:
 * - Burned secrets have is_burned=true AND is_destroyed=true AND secret_ttl=0
 * - Revealed secrets have is_revealed=true AND is_destroyed=true AND secret_ttl=-1
 *
 * The UI should show the actual state (burned/revealed) not the side effect.
 */
const itemState = computed((): 'new' | 'previewed' | 'revealed' | 'burned' | 'expired' => {
  if (isBurned.value) return 'burned';
  if (isRevealed.value) return 'revealed';
  if (isExpired.value || isDestroyed.value) return 'expired';
  if (isPreviewed.value) return 'previewed';
  return 'new';
});

// Console-style status configuration
const statusConfig = computed(() => {
  switch (itemState.value) {
    case 'expired':
      return {
        symbol: '○', // open circle
        label: t('web.STATUS.expired').toUpperCase(),
        colorClass: 'text-gray-500 dark:text-gray-500',
      };
    case 'burned':
      return {
        symbol: '✕', // multiplication sign (X)
        label: t('web.STATUS.burned').toUpperCase(),
        colorClass: 'text-red-600 dark:text-red-400',
      };
    case 'revealed':
      return {
        symbol: '✓', // check mark
        label: t('web.STATUS.revealed').toUpperCase(),
        colorClass: 'text-gray-500 dark:text-gray-400',
      };
    case 'previewed':
      return {
        symbol: '◐', // half-filled circle
        label: t('web.STATUS.previewed').toUpperCase(),
        colorClass: 'text-amber-600 dark:text-amber-400',
      };
    default: // new
      return {
        symbol: '●', // filled circle
        label: t('web.STATUS.new').toUpperCase(),
        colorClass: 'text-emerald-600 dark:text-emerald-400',
      };
  }
});

// Display key (truncated shortid)
const displayKey = computed(() => {
  const shortid = props.secretReceipt.secret_shortid;
  if (!shortid) return '';
  if (shortid.length <= 4) return shortid;
  return shortid.slice(0, 4);
});

// Check if secret is still actionable
const isActive = computed(() => itemState.value === 'new' || itemState.value === 'previewed');

// Check if this is a terminal state (no actions available)
const isTerminal = computed(() => !isActive.value);

// Time remaining urgency
const isUrgent = computed(() => getTtlPercentage.value <= 25 && isActive.value);

// Whether the secret was created on a different domain
const hasDifferentDomain = computed(
  () => !!props.secretReceipt.share_domain && props.secretReceipt.share_domain !== site_host.value
);

// Receipt route for this record
const receiptRoute = computed(() => ({
  name: 'Receipt link',
  params: { receiptIdentifier: props.secretReceipt.identifier }
}));

// Navigate to receipt when clicking the row background
const handleRowClick = () => {
  router.push(receiptRoute.value);
};

const rowClasses = computed(() => ['font-mono text-sm', isTerminal.value && 'opacity-60']);
</script>

<template>
  <li
    :class="rowClasses"
    class="group/row relative cursor-pointer transition-all duration-150 hover:shadow-sm"
    @click="handleRowClick">
    <!-- Content wrapper: contains everything except separator, for watermark positioning -->
    <div class="relative">
      <!-- Background watermark: oversized shortid, centered (hidden on mobile) -->
      <div
        class="pointer-events-none absolute inset-0 hidden select-none items-center justify-center sm:flex"
        aria-hidden="true">
        <span
          :class="[
            'font-mono text-[clamp(3.5rem,8vw,4.5rem)] font-light uppercase leading-none tracking-[0.3em] transition-colors duration-150',
            isTerminal
              ? 'dark:text-gray-500/12 text-gray-400/15 group-hover/row:text-gray-400/30 dark:group-hover/row:text-gray-500/25'
              : 'dark:text-gray-500/18 text-gray-400/20 group-hover/row:text-gray-400/40 dark:group-hover/row:text-gray-500/35',
          ]">
          {{ displayKey }}
        </span>
      </div>

      <!-- Header line: #N  padlock  SYMBOL STATUS  Memo/ID -->
      <div class="relative flex items-start gap-2">
        <!-- Index prefix (links to receipt) -->
        <router-link
          :to="receiptRoute"
          :aria-label="`${t('web.receipt.view_receipt')} #${index}`"
          class="cursor-pointer select-none px-1 py-0.5 text-gray-400 no-underline hover:underline dark:text-gray-500"
          @click.stop>
          #{{ index }}
        </router-link>

        <!--
          LAYER 1 & 2: Encryption iconography
          - All items show padlock (EO baseline)
          - EAP items add lock-check icon
        -->
        <div
          class="group/encrypt relative flex-shrink-0"
          @mouseenter="showEncryptionTooltip = true"
          @mouseleave="showEncryptionTooltip = false"
          @focus="showEncryptionTooltip = true"
          @blur="showEncryptionTooltip = false"
          tabindex="0"
          role="img"
          :aria-label="
            hasPassphrase
              ? `${t('web.LABELS.encrypted')} + ${t('web.LABELS.passphrase_protected')}`
              : t('web.LABELS.encrypted')
          ">
          <!-- Padlock icon (always shown, mid-gray, same saturation for EO and EAP) -->
          <OIcon
            v-if="hasPassphrase"
            collection="tabler"
            name="lock-check"
            size="5" />
          <OIcon
            v-else
            collection="tabler"
            name="lock"
            size="5" />

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

        <!-- Memo or shortid display -->
        <div class="min-w-0 flex-1">
          <span
            v-if="secretReceipt.memo"
            :class="[
              'truncate',
              isActive
                ? 'text-gray-900 dark:text-gray-100'
                : 'text-gray-600 dark:text-gray-400',
            ]">
            {{ secretReceipt.memo }}
          </span>
          <span
            v-else
            class="text-gray-400 dark:text-gray-500">
            {{ displayKey }}
          </span>
        </div>

        <!-- Actions (header line, right side) — stop propagation to prevent row click -->
        <div
          v-if="isActive"
          class="flex flex-shrink-0 items-center gap-1 sm:gap-2"
          @click.stop>
          <!-- Copy button: icon-only on mobile, text on sm+ -->
          <button
            type="button"
            @click="handleCopy"
            :class="[
              'rounded border transition-colors',
              'p-1.5 sm:px-2 sm:py-0.5',
              isCopied
                ? 'border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'
                : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700',
            ]"
            :title="t('web.LABELS.copy_to_clipboard')">
            <!-- Mobile: icon only -->
            <OIcon
              v-if="isCopied"
              collection="heroicons"
              name="check"
              class="size-4 sm:hidden" />
            <OIcon
              v-else
              collection="heroicons"
              name="clipboard"
              class="size-4 sm:hidden" />
            <!-- Desktop: text label -->
            <span class="hidden text-xs font-medium sm:inline">
              {{ isCopied ? '[ COPIED ]' : '[ COPY ]' }}
            </span>
          </button>

          <!-- Open link button: icon-only on mobile, text on sm+ -->
          <a
            :href="shareLink"
            target="_blank"
            rel="noopener noreferrer"
            class="rounded border border-gray-300 bg-white p-1.5 text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 sm:px-2 sm:py-0.5"
            :title="t('web.COMMON.view_secret')"
            @click.stop>
            <!-- Mobile: icon only -->
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="size-4 sm:hidden" />
            <!-- Desktop: text label -->
            <span class="hidden text-xs font-medium sm:inline">[ OPEN &#8599; ]</span>
          </a>

          <!-- Burn button: icon-only on mobile, text on sm+ -->
          <router-link
            :to="{ name: 'Burn secret', params: { receiptIdentifier: secretReceipt.identifier } }"
            class="rounded border border-red-300 bg-red-50 p-1.5 text-red-700 transition-colors hover:bg-red-100 dark:border-red-700 dark:bg-red-900/30 dark:text-red-400 dark:hover:bg-red-900/50 sm:px-2 sm:py-0.5"
            :title="t('web.COMMON.burn')"
            @click.stop>
            <!-- Mobile: icon only -->
            <OIcon
              collection="heroicons"
              name="fire"
              class="size-4 sm:hidden" />
            <!-- Desktop: text label -->
            <span class="hidden text-xs font-medium sm:inline">[ BURN ]</span>
          </router-link>
        </div>
      </div>

      <!-- Metadata tree (full tree for active/previewed, minimal for terminal) -->
      <div class="relative ml-4 mt-1 space-y-0.5 text-gray-600 dark:text-gray-400">
        <template v-if="isActive">
          <!-- Domain line (only when share domain differs from site host) -->
          <div
            v-if="hasDifferentDomain"
            class="flex items-center">
            <span
              class="mr-2 select-none text-gray-300 dark:text-gray-600"
              aria-hidden="true"
              >&#9500;&#9472;</span
            >
            <span class="text-gray-400 dark:text-gray-500">via:</span>
            <span class="ml-1 text-gray-500 dark:text-gray-400">{{ secretReceipt.share_domain }}</span>
          </div>

          <!-- Recipients line (if shown) -->
          <div
            v-if="secretReceipt.show_recipients && secretReceipt.recipients"
            class="flex items-center">
            <span
              class="mr-2 select-none text-gray-300 dark:text-gray-600"
              aria-hidden="true"
              >&#9500;&#9472;</span
            >
            <span class="text-gray-400 dark:text-gray-500">to:</span>
            <span class="ml-1 text-gray-500 dark:text-gray-400">{{ secretReceipt.recipients }}</span>
          </div>

          <!-- Expires line with timestamp on right -->
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <span
                class="mr-2 select-none text-gray-300 dark:text-gray-600"
                aria-hidden="true"
                >&#9492;&#9472;</span
              >
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

            <!-- Timestamp -->
            <div class="flex items-center gap-2">
              <span
                data-test-id="created-timestamp"
                class="text-xs text-gray-400 dark:text-gray-500">
                <time :datetime="secretReceipt.created.toISOString()">
                  {{ formattedDate }}
                </time>
              </span>
            </div>
          </div>
        </template>

        <!-- Terminal states: minimal info -->
        <template v-else>
          <!-- Domain line (only when share domain differs from site host) -->
          <div
            v-if="hasDifferentDomain"
            class="flex items-center">
            <span
              class="mr-2 select-none text-gray-300 dark:text-gray-600"
              aria-hidden="true"
              >&#9500;&#9472;</span
            >
            <span class="text-gray-400 dark:text-gray-500">via:</span>
            <span class="ml-1 text-gray-500 dark:text-gray-400">{{ secretReceipt.share_domain }}</span>
          </div>

          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <span
                class="mr-2 select-none text-gray-300 dark:text-gray-600"
                aria-hidden="true"
                >&#9492;&#9472;</span
              >
              <span v-if="itemState === 'revealed'">viewed:</span>
              <span v-else-if="itemState === 'burned'">destroyed:</span>
              <span v-else>expired:</span>
              <span class="ml-1 text-gray-500 dark:text-gray-400">
                <time :datetime="secretReceipt.created.toISOString()">
                  {{ formattedDate }}
                </time>
              </span>
            </div>
          </div>
        </template>
      </div>
    </div>
    <!-- /Content wrapper -->

    <!-- Separator line (if not last item) -->
    <div
      v-if="!isLast"
      class="my-4 border-t border-gray-200/60 transition-colors duration-150 group-hover/row:border-gray-300/80 dark:border-gray-700/60 dark:group-hover/row:border-gray-600/80"
      aria-hidden="true"></div>
  </li>
</template>
