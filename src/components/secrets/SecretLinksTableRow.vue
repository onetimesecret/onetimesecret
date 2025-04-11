<!-- src/components/secrets/SecretLinksTableRow.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { WindowService } from '@/services/window.service';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref, computed } from 'vue';
  import { formatTTL } from '@/utils/formatters';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    concealedMessage: ConcealedMessage;
  }>();

  const emit = defineEmits<{
    copy: [];
    delete: [concealedMessage: ConcealedMessage];
  }>();

  // Track if this row's content was copied
  const isCopied = ref(false);

  const site_host = WindowService.get('site_host');

  // Create shareable link with proper domain
  const shareLink = computed(() => {
    const record = props.concealedMessage;
    const share_domain = record.response.record.metadata.share_domain ?? site_host;
    return `https://${share_domain}/secret/${record.secret_key}`;
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
  const formattedDate = computed(() => {
    return formatDistanceToNow(props.concealedMessage.clientInfo.createdAt, { addSuffix: true });
  });

  // Compute security status and time remaining
  const hasPassphrase = computed(() => props.concealedMessage.clientInfo.hasPassphrase);

  const timeRemaining = computed(() => formatTTL(props.concealedMessage.response.record.metadata.secret_ttl ?? 0));

  // Secret state computations
  const isExpired = computed(() => props.concealedMessage.clientInfo.ttl <= 0);
  const isBurned = computed(() => !!props.concealedMessage.response.record.metadata?.burned);
  const isViewed = computed(() => !!props.concealedMessage.response.record.metadata?.viewed);
  const isReceived = computed(() => !!props.concealedMessage.response.record.metadata?.received);

  // Calculate TTL percentage for background color
  const getTtlPercentage = computed(() => {
    // Default max TTL to 7 days (604800 seconds)
    const maxTtl = 604800;
    // Get current TTL
    const currentTtl = props.concealedMessage.clientInfo.ttl;
    return Math.floor((currentTtl / maxTtl) * 100);
  });

  // Background color class based on TTL percentage and state
  const ttlBackgroundClass = computed(() => {
    if (isExpired.value) return 'bg-gray-50/80 dark:bg-slate-800/40';
    if (isBurned.value) return 'bg-red-50/30 dark:bg-red-900/5';
    if (isViewed.value) return 'bg-amber-50/30 dark:bg-amber-900/5';

    const percentage = getTtlPercentage.value;
    if (percentage > 75) return 'bg-opacity-0 dark:bg-opacity-0';
    if (percentage > 50) return 'bg-emerald-50/30 dark:bg-emerald-900/10';
    if (percentage > 25) return 'bg-amber-50/40 dark:bg-amber-900/15';
    return 'bg-red-50/40 dark:bg-red-900/10';
  });

  // Text status based on secret state
  const statusClass = computed(() => {
    if (isExpired.value) return 'text-gray-500 dark:text-gray-400';
    if (isBurned.value) return 'text-red-600 dark:text-red-400';
    if (isViewed.value) return 'text-amber-600 dark:text-amber-400';
    return 'text-emerald-600 dark:text-emerald-400';
  });

  // Get status label based on state and TTL percentage
  const statusLabel = computed(() => {
    if (isExpired.value) return t('web.STATUS.expired');
    if (isBurned.value) return t('web.STATUS.burned');
    if (isViewed.value) return t('web.STATUS.viewed');
    if (isReceived.value) return t('web.STATUS.received');

    const percentage = getTtlPercentage.value;
    if (percentage <= 25) return t('web.STATUS.expiring_soon');
    return '';
  });

  // Display key (shortened for clarity)
  const displayKey = computed(() => {
    return props.concealedMessage.response.record.secret.shortkey;
  });
</script>

<template>
  <tr
    :class="[
      'group border-b border-gray-200 dark:border-gray-700 transition-all duration-200 hover:bg-gray-50/80 dark:hover:bg-slate-800/70',
      ttlBackgroundClass,
      { 'opacity-70': isExpired || isBurned },
    ]">
    <!-- Secret ID Column -->
    <td class="px-6 py-4 whitespace-nowrap">
      <div class="flex flex-col">
        <div class="flex items-center gap-2 mb-1.5">
          <!-- Status icon changes based on secret state -->
          <OIcon
            collection="heroicons"
            name="document-text"
            class="size-4 text-gray-500" />
          <span
            :class="[
              'font-mono text-sm truncate max-w-[15ch] font-medium',
              isExpired || isBurned
                ? 'text-gray-500 dark:text-gray-400'
                : 'text-gray-800 dark:text-gray-200',
            ]">
            <router-link
              v-if="!isExpired && !isBurned"
              :to="`/receipt/${concealedMessage.metadata_key}`"
              class="hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
              {{ displayKey }}
            </router-link>
            <span v-else>{{ displayKey }}</span>
          </span>
          <!-- Status badge based on secret state -->
          <span
            v-if="statusLabel"
            :class="[
              'ml-1 text-xs px-1.5 py-0.5 rounded text-white dark:text-white font-medium',
              isExpired
                ? 'bg-gray-500 dark:bg-gray-600'
                : isBurned
                  ? 'bg-red-500 dark:bg-red-600'
                  : isViewed
                    ? 'bg-amber-500 dark:bg-amber-600'
                    : isReceived
                      ? 'bg-blue-500 dark:bg-blue-600'
                      : 'bg-amber-500 dark:bg-amber-600',
            ]">
            {{ statusLabel }}
          </span>
        </div>
        <!-- Time info rows - display creation date and lifespan on separate lines -->
        <div class="flex flex-col ml-6">
          <div class="text-xs text-gray-500 dark:text-gray-400 pl-1">

            <span class="sr-only">{{ $t('web.LABELS.lifespan') }}</span>
            {{ timeRemaining }} |
            <span class="sr-only">{{ $t('web.STATUS.created') }}</span>
            {{ formattedDate }}
          </div>
        </div>
      </div>
    </td>

    <!-- Time Remaining Column (hidden on mobile) -->
    <td class="px-6 py-4 hidden sm:table-cell">
      <div class="flex flex-col space-y-2">

        <!-- Security status -->
        <div
          v-if="hasPassphrase && !isExpired && !isBurned"
          class="flex items-center gap-1.5">
            <OIcon
              collection="heroicons"
              name="key"
              class="size-3 mr-1 text-emerald-500 dark:text-emerald-400" />
          <span class="text-sm text-emerald-600 dark:text-emerald-400 font-medium">
            {{ $t('web.LABELS.passphrase_protected') }}
          </span>
        </div>
      </div>
    </td>

    <!-- Share Column -->
    <td class="px-6 py-4 text-right">
      <div class="flex justify-end">
        <!-- Show Share only for active secrets -->
        <div
          v-if="!isExpired && !isBurned"
          class="relative group inline-block">
          <a
            :href="shareLink"
            target="_blank"
            class="flex items-center gap-2 px-3 py-1.5 rounded-lb-md rounded-rb-md bg-gray-100 text-sm font-medium text-gray-700 dark:bg-gray-800/50 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="size-4" />
            <span class="sr-only">{{ $t('web.COMMON.view_secret') }}</span>
          </a>
          <div class="relative">
            <button
              @click="handleCopy"
              class="flex items-center gap-2 px-3 py-1.5 rounded-tl-md rounded-tr-md bg-gray-100 text-sm font-medium text-gray-700 dark:bg-gray-800/50 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all border-r border-gray-200 dark:border-gray-700/50">
              <OIcon
                collection="material-symbols"
                :name="isCopied ? 'check' : 'content-copy-outline'"
                class="size-4" />
              <span class="sr-only">{{ $t('web.LABELS.copy_to_clipboard') }}</span>
            </button>
            <!-- Copy Feedback Tooltip -->
            <div
              v-if="isCopied"
              class="absolute -top-8 left-1/2 transform -translate-x-1/2 px-2 py-1 bg-gray-800 text-white text-xs rounded shadow-lg z-10 whitespace-nowrap">
              {{ $t('web.STATUS.copied') }}
              <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-2 h-2 bg-gray-800 rotate-45"></div>
            </div>
          </div>
        </div>

        <!-- Show status message for expired/burned secrets -->
        <div
          v-else
          class="text-sm">
          <span :class="statusClass">
            {{ isExpired ? $t('web.STATUS.expired') : $t('web.STATUS.burned') }}
          </span>
        </div>
      </div>
    </td>
  </tr>
</template>
