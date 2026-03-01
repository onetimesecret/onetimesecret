<!-- src/apps/workspace/components/account/APIKeyCard.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { ref } from 'vue';

const { t } = useI18n();

interface Props {
  apitoken: string | undefined;
  onCopy?: () => void;
}

const props = withDefaults(defineProps<Props>(), {
  apitoken: '',
  onCopy: () => {}
});

const copied = ref(false);

const handleCopy = () => {
  navigator.clipboard.writeText(props.apitoken)
    .then(() => {
      copied.value = true;
      setTimeout(() => {
        copied.value = false;
      }, 2000); // Reset after 2 seconds
      props.onCopy(); // Call the onCopy prop function if provided
    })
    .catch(err => {
      console.error('Failed to copy text: ', err);
    });
};
</script>

<template>
  <div
    v-if="apitoken"
    class="mb-4 rounded-lg border border-gray-200/60 bg-white/60 p-4 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
    <div class="font-mono text-sm text-gray-800 dark:text-gray-200">
      <div class="relative flex items-center overflow-x-auto rounded-md border border-gray-200 bg-gray-50 p-3 dark:border-gray-600 dark:bg-gray-900/50">
        <span class="break-all pr-10">{{ apitoken }}</span>
        <button
          @click.stop="handleCopy"
          type="button"
          class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 transition-colors duration-200 hover:text-brand-600 dark:text-gray-500 dark:hover:text-brand-400">
          <OIcon
            collection="heroicons"
            :name="copied ? 'check' : 'clipboard'"
            class="size-5" />
        </button>
      </div>
    </div>
    <p class="mt-2 text-xs font-medium text-gray-500 dark:text-gray-400">
      {{ t('web.account.keep_this_token_secure_it_provides_full_access_t') }}
    </p>
  </div>
</template>
