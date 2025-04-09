<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref } from 'vue';
  import CopyToClipboardButton from '@/components/ui/CopyToClipboardButton.vue';
  import { formatTTL } from '@/utils/formatters';

  const props = defineProps<{
    concealedMessage: ConcealedMessage;
  }>();

  const emit = defineEmits<{
    copy: [];
  }>();

  // Track if this row's content was copied
  const isCopied = ref(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(props.concealedMessage.secret_key);
      isCopied.value = true;
      emit('copy');

      // Reset copy state after 2 seconds
      setTimeout(() => {
        isCopied.value = false;
      }, 2000);
    } catch (err) {
      console.error('Failed to copy text: ', err);
    }
  };
</script>

<template>
  <tr class="group hover:bg-gray-50 dark:hover:bg-slate-800/50 transition-colors">
    <td class="px-6 py-4">
      <div class="flex items-center gap-2">
        <span class="font-mono text-sm text-gray-900 dark:text-gray-100 truncate max-w-[300px]">
          <router-link :to="`/private/${concealedMessage.metadata_key}`">
            {{ concealedMessage.secret_key }}
          </router-link>
        </span>
        <CopyToClipboardButton
          :is-copied="isCopied"
          @click="handleCopy"
        />
      </div>
      <span class="text-sm text-gray-500 dark:text-gray-400">
        {{ formatDistanceToNow(concealedMessage.clientInfo.createdAt, { addSuffix: true }) }}
      </span>
    </td>
    <td class="px-6 py-4">
      <div class="flex items-center gap-2">
        <div
          class="flex items-center gap-1.5 text-sm"
          :class="
            concealedMessage.clientInfo.hasPassphrase
              ? 'text-amber-600 dark:text-amber-400'
              : 'text-gray-500 dark:text-gray-400'
          ">
          <OIcon
            collection="material-symbols"
            :name="concealedMessage.clientInfo.hasPassphrase ? 'key-vertical' : 'lock-open'"
            class="w-4 h-4" />
          <span>{{
            concealedMessage.clientInfo.hasPassphrase ? 'Protected' : 'No passphrase'
          }}</span>
        </div>
      </div>
    </td>
    <td class="px-6 py-4">
      <span class="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection="material-symbols"
          name="timer"
          class="w-4 h-4" />
        {{ formatTTL(concealedMessage.clientInfo.ttl) }}
      </span>
    </td>
  </tr>
</template>
