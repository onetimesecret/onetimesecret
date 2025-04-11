<!-- src/components/secrets/SecretLinksTableRow.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { WindowService } from '@/services/window.service';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref, computed } from 'vue';
  import { formatTTL } from '@/utils/formatters';
  import SecretLinksTableRowActions from '@/components/secrets/SecretLinksTableRowActions.vue';
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

  // Format creation date to be more readable
  const formattedDate = computed(() => {
    return formatDistanceToNow(props.concealedMessage.clientInfo.createdAt, { addSuffix: true });
  });

  // Compute security status label
  const securityStatusLabel = computed(() => {
    return props.concealedMessage.clientInfo.hasPassphrase
      ? t('web.private.requires_passphrase')
      : 'No passphrase';
  });

  // Compute security level class
  const securityLevelClass = computed(() => {
    return props.concealedMessage.clientInfo.hasPassphrase
      ? 'text-emerald-600 dark:text-emerald-400 font-medium'
      : 'text-amber-600 dark:text-amber-400';
  });

</script>

<template>
  <tr class="group border-b border-gray-200 dark:border-gray-700 transition-all duration-200 hover:bg-gray-50/80 dark:hover:bg-slate-800/70">
    <!-- Secret ID Column -->
    <td class="px-6 py-4 whitespace-nowrap">
      <div class="flex flex-col">
        <div class="flex items-center gap-2 mb-1.5">
          <div class="flex items-center p-1.5 rounded-md bg-blue-50 dark:bg-blue-500/10">
            <OIcon
              collection="heroicons"
              name="document-text-solid"
              class="size-4 text-blue-500 dark:text-blue-400" />
          </div>
          <span class="font-mono text-sm font-medium text-gray-900 dark:text-gray-100 truncate max-w-[15ch]">
            <router-link
              :to="`/private/${concealedMessage.metadata_key}`"
              class="hover:text-blue-600 dark:hover:text-blue-400 transition-colors flex items-center gap-1">
              {{ concealedMessage.response.record.metadata.shortkey }}
            </router-link>
          </span>
        </div>
        <div class="flex items-center text-xs text-gray-500 dark:text-gray-400 ml-10">
          <OIcon
            collection="heroicons"
            name="clock-solid"
            class="mr-1.5 size-3.5" />
          {{ formattedDate }}
        </div>
      </div>
    </td>

    <!-- Security & Expiration Column -->
    <td class="px-6 py-4">
      <div class="flex flex-col space-y-2.5">
        <div
          class="flex items-center gap-2"
          :class="securityLevelClass">
          <div class="flex items-center p-1.5 rounded-md" :class="concealedMessage.clientInfo.hasPassphrase ? 'bg-emerald-50 dark:bg-emerald-500/10' : 'bg-amber-50 dark:bg-amber-500/10'">
            <OIcon
              collection="heroicons"
              :name="concealedMessage.clientInfo.hasPassphrase ? 'key-solid' : 'lock-open-solid'"
              class="size-4" />
          </div>
          <span class="text-sm">{{ securityStatusLabel }}</span>
        </div>
        <div class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-300">
          <div class="flex items-center p-1.5 rounded-md bg-indigo-50 dark:bg-indigo-500/10">
            <OIcon
              collection="heroicons"
              name="clock-solid"
              class="size-4 text-indigo-500 dark:text-indigo-400" />
          </div>
          <span class="font-medium">{{ formatTTL(concealedMessage.clientInfo.ttl) }}</span>
        </div>
      </div>
    </td>

    <!-- Actions Column -->
    <td class="px-6 py-4 text-right">
      <div class="flex justify-end space-x-2">
        <!-- Split Button for Secret Link -->
        <div class="flex relative group/secret-link">
          <router-link
            :to="`/secret/${concealedMessage.secret_key}`"
            target="_blank"
            class="inline-flex items-center justify-center rounded-l-md bg-green-100 px-3 py-1.5 text-sm font-medium text-green-700 dark:bg-green-800/30 dark:text-green-300 hover:bg-green-200 dark:hover:bg-green-700/40 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 transition-all">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="mr-1.5 size-4" />

          </router-link>
          <button
            @click="handleCopy"
            class="inline-flex items-center justify-center rounded-r-md border-l border-green-200 dark:border-green-700/50 bg-green-100 dark:bg-green-800/30 p-1.5 text-sm font-medium text-green-700 dark:text-green-300 hover:bg-green-200 dark:hover:bg-green-700/40 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 transition-all">
            <OIcon
              collection="material-symbols"
              :name="isCopied ? 'check' : 'content-copy-outline'"
              class="size-4" />

            <!-- Tooltip that appears on hover -->
            <span class="absolute -top-9 right-0 px-2 py-1 bg-gray-800 text-white text-xs rounded opacity-0 group-hover/secret-link:opacity-100 whitespace-nowrap transition-opacity duration-200 z-10">
              {{ isCopied ? 'Copied!' : 'Copy secret link' }}
            </span>
          </button>
        </div>

        <!-- Actions Menu -->
        <SecretLinksTableRowActions
          :concealed-message="concealedMessage"
          @delete="$emit('delete', concealedMessage)" />
      </div>
    </td>
  </tr>
</template>
