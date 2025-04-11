<!-- src/components/secrets/SecretLinksTableRow.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { WindowService } from '@/services/window.service';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref } from 'vue';
  import CopyToClipboardButton from '@/components/ui/CopyToClipboardButton.vue';
  import { formatTTL } from '@/utils/formatters';
  import SecretLinksTableRowActions from '@/components/secrets/SecretLinksTableRowActions.vue';

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
      const share_domain = record.share_domain ?? site_host;
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
</script>

<template>
  <tr class="group hover:bg-gray-50 dark:hover:bg-slate-800/50 transition-colors">
    <td class="px-6 py-4">
      <div class="flex items-center gap-2">
        <span class="font-mono text-sm text-gray-900 dark:text-gray-100 truncate max-w-[12ch]">
          <router-link :to="`/private/${concealedMessage.metadata_key}`">
            {{ concealedMessage.metadata_key }}
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
          <span v-if="concealedMessage.clientInfo.hasPassphrase">
            {{ $t('web.private.requires_passphrase') }}
          </span>
          <span class="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400">
            <OIcon
              collection="material-symbols"
              name="timer"
              class="w-4 h-4" />
            {{ formatTTL(concealedMessage.clientInfo.ttl) }}
          </span>
        </div>
      </div>
    </td>
    <td class="px-6 py-4">
      <SecretLinksTableRowActions
        :concealed-message="concealedMessage"
        @delete="$emit('delete', concealedMessage)" />
    </td>
  </tr>
</template>
