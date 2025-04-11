<!-- src/components/secrets/SecretLinksTableRow.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { WindowService } from '@/services/window.service';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref, computed } from 'vue';
  import { formatTTL } from '@/utils/formatters';
  // import SecretLinksTableRowActions from '@/components/secrets/SecretLinksTableRowActions.vue';
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

  // Compute security status label
  const securityStatusLabel = computed(() => {
    return props.concealedMessage.clientInfo.hasPassphrase
      ? t('web.private.requires_passphrase')
      : '';
  });

  // Compute security level class
  // const securityLevelClass = computed(() => {
  //   return props.concealedMessage.clientInfo.hasPassphrase
  //     ? 'text-emerald-600 dark:text-emerald-400 font-medium'
  //     : 'text-amber-600 dark:text-amber-400';
  // });

</script>

<template>
  <tr class="group border-b border-gray-200 dark:border-gray-700 transition-all duration-200 hover:bg-gray-50/80 dark:hover:bg-slate-800/70">
    <!-- Secret ID Column -->
    <td class="px-6 py-3 whitespace-nowrap">
      <div class="flex flex-col">
        <div class="flex items-center gap-2 mb-1">
          <OIcon
            collection="heroicons"
            name="document-text-solid"
            class="size-4 text-gray-500 dark:text-gray-400" />
          <span class="font-mono text-sm text-gray-800 dark:text-gray-200 truncate max-w-[15ch]">
            <router-link
              :to="`/private/${concealedMessage.metadata_key}`"
              class="hover:text-gray-600 dark:hover:text-gray-300 transition-colors flex items-center gap-1">
              {{ concealedMessage.response.record.metadata.shortkey }}
            </router-link>
          </span>
        </div>
        <div class="flex items-center text-xs text-gray-500 dark:text-gray-400 ml-6">
          <OIcon
            collection="heroicons"
            name="clock-solid"
            class="mr-1.5 size-3" />
          {{ formattedDate }}
        </div>
      </div>
    </td>

    <!-- Security & Expiration Column -->
    <td class="px-6 py-3">
      <div class="flex flex-col space-y-2">
        <div v-if="securityStatusLabel"
          class="flex items-center gap-1.5">
          <OIcon
            collection="heroicons"
            :name="concealedMessage.clientInfo.hasPassphrase ? 'key-solid' : 'lock-open-solid'"
            class="size-3.5 text-gray-500 dark:text-gray-400" />
          <span class="text-sm text-gray-700 dark:text-gray-300">{{ securityStatusLabel }}</span>
        </div>
        <div class="flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="clock-solid"
            class="size-3.5 text-gray-500 dark:text-gray-400" />
          <span>{{ formatTTL(concealedMessage.clientInfo.ttl) }}</span>
        </div>
      </div>
    </td>

    <!-- Actions Column -->
    <td class="px-6 py-3 text-right">
      <div class="flex justify-end space-x-2">
        <!-- Split Button for Secret Link -->
        <div class="flex relative group/secret-link">
          <button
            @click="handleCopy"
            class="inline-flex items-center justify-center rounded-r-md border-l border-gray-200 dark:border-gray-700/50 bg-gray-100 dark:bg-gray-800/50 p-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all">
            <OIcon
              collection="material-symbols"
              :name="isCopied ? 'check' : 'content-copy-outline'"
              class="size-4" />

            <!-- Tooltip that appears on hover -->
            <span class="absolute -top-9 right-0 px-2 py-1 bg-gray-800 text-white text-xs rounded opacity-0 group-hover/secret-link:opacity-100 whitespace-nowrap transition-opacity duration-200 z-10">
              {{ isCopied ? 'Copied!' : 'Copy secret link' }}
            </span>
          </button>
          <router-link
            :to="`/secret/${concealedMessage.secret_key}`"
            target="_blank"
            class="inline-flex items-center justify-center rounded-l-md bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 dark:bg-gray-800/50 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700/40 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2 transition-all">
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square"
              class="mr-1.5 size-4" />
          </router-link>
        </div>

        <!-- Actions Menu -->
        <!-- <SecretLinksTableRowActions
          :concealed-message="concealedMessage"
          @delete="$emit('delete', concealedMessage)" /> -->
      </div>
    </td>
  </tr>
</template>

<style scoped>
</style>
