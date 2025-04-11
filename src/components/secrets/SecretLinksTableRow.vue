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

  const handleCopy = async () => {
    try {
      const record = props.concealedMessage;
      const share_domain = record.response.record.metadata.share_domain ?? site_host;
      const share_link = `https://${share_domain}/secret/${record.secret_key}`;
      await navigator.clipboard.writeText(share_link);
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
  const timeRemaining = computed(() => formatTTL(props.concealedMessage.clientInfo.ttl));

  // Calculate TTL percentage for background color
  const getTtlPercentage = computed(() => {
    // Default max TTL to 7 days (604800 seconds)
    const maxTtl = 604800;
    // Get current TTL
    const currentTtl = props.concealedMessage.clientInfo.ttl;
    return Math.floor((currentTtl / maxTtl) * 100);
  });

  // Background color class based on TTL percentage
  const ttlBackgroundClass = computed(() => {
    const percentage = getTtlPercentage.value;
    if (percentage > 75) return 'bg-opacity-0 dark:bg-opacity-0';
    if (percentage > 50) return 'bg-emerald-50/30 dark:bg-emerald-900/10';
    if (percentage > 25) return 'bg-amber-50/40 dark:bg-amber-900/15';
    return 'bg-red-50/40 dark:bg-red-900/10';
  });

  // Get status label based on TTL percentage
  const statusLabel = computed(() => {
    const percentage = getTtlPercentage.value;
    if (percentage <= 25) return t('web.STATUS.expiring_soon');
    return '';
  });

  // Create shareable link with proper domain
  const secretLink = computed(() => {
    const record = props.concealedMessage;
    const shareDomain = record.response.record.metadata.share_domain ?? site_host;
    return `https://${shareDomain}/secret/${record.secret_key}`;
  });

  // Display key (shortened for clarity)
  const displayKey = computed(() => {
    return props.concealedMessage.response.record.metadata.shortkey;
  });
</script>

<template>
  <tr :class="[
      'group border-b border-gray-200 dark:border-gray-700 transition-all duration-200 hover:bg-gray-50/80 dark:hover:bg-slate-800/70',
      ttlBackgroundClass
    ]">
    <!-- Secret ID Column -->
    <td class="px-6 py-4 whitespace-nowrap">
      <div class="flex flex-col">
        <div class="flex items-center gap-2 mb-1.5">
          <OIcon
            v-if="hasPassphrase"
            collection="heroicons"
            name="key"
            class="size-4 text-emerald-500 dark:text-emerald-400" />
          <OIcon
            v-else
            collection="heroicons"
            name="document-text"
            class="size-4 text-gray-500 dark:text-gray-400" />
          <span class="font-mono text-sm text-gray-800 dark:text-gray-200 truncate max-w-[15ch] font-medium">
            <router-link
              :to="`/private/${concealedMessage.metadata_key}`"
              class="hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
              {{ displayKey }}
            </router-link>
          </span>
        </div>
        <span class="text-xs text-gray-500 dark:text-gray-400 ml-6">
          {{ formattedDate }}
        </span>
      </div>
    </td>

    <!-- Security & Expiration Column (hidden on mobile) -->
    <td class="px-6 py-4 hidden sm:table-cell">
      <div class="flex flex-col space-y-2">
        <div v-if="hasPassphrase"
          class="flex items-center gap-1.5">
          <span class="text-sm text-emerald-600 dark:text-emerald-400 font-medium">
            {{ $t('web.LABELS.passphrase_protected') }}
          </span>
        </div>
        <div class="flex items-center text-sm text-gray-600 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="clock"
            class="mr-1.5 size-3.5" />
          <span>{{ timeRemaining }}</span>
          <span v-if="statusLabel" class="ml-1.5 text-amber-600 dark:text-amber-400 text-xs px-1.5 py-0.5 bg-amber-50 dark:bg-amber-900/20 rounded">
            {{ statusLabel }}
          </span>
        </div>
      </div>
    </td>

    <!-- Actions Column -->
    <td class="px-6 py-4 text-right">
      <div class="flex justify-end">
        <!-- Combined Action Button -->
        <div class="relative group inline-block">
          <button
            @click="handleCopy"
            class="flex items-center gap-2 px-3 py-1.5 rounded-l-md bg-gray-100 text-sm font-medium text-gray-700 dark:bg-gray-800/50 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all border-r border-gray-200 dark:border-gray-700/50">
            <OIcon
              collection="material-symbols"
              :name="isCopied ? 'check' : 'content-copy-outline'"
              class="size-4" />
            <span class="sr-only">{{ isCopied ? $t('web.COMMON.copied_to_clipboard') : $t('copy-to-clipboard') }}</span>
          </button>
          <router-link
            :to="secretLink"
            target="_blank"
            class="flex items-center gap-2 px-3 py-1.5 rounded-r-md bg-gray-100 text-sm font-medium text-gray-700 dark:bg-gray-800/50 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="size-4" />
            <span class="sr-only">{{ $t('web.COMMON.view_secret') }}</span>
          </router-link>

        </div>
      </div>
    </td>
  </tr>
</template>
