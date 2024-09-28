<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  showRedButton: boolean | null;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  showRedButton: false,
})

// We use this to determine whether to include the authenticity check
const cust = window.cust;

</script>

<template>
  <div class="container">
    <form class="form form-inline"
          action="/feedback"
          method="post">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="csrfStore.shrimp" />
      <div class="flex mb-4">
        <AltchaChallenge v-if="!cust" />
        <div class="flex flex-grow">
          <input type="text"
                 name="msg"
                 class="flex-grow px-4 py-2 border border-gray-300 rounded-l-md
                   focus:border-brandcomp-500 focus:ring-2 focus:ring-brandcomp-500 focus:outline-none
                   dark:bg-gray-700 dark:border-gray-600 dark:text-gray-200"
                 autocomplete="off"
                 :placeholder="$t('web.COMMON.feedback_text')">
          <button :class="[
            'px-4 py-2 font-medium text-white transition duration-150 ease-in-out rounded-r-md',
            showRedButton
              ? 'bg-brand-500 hover:bg-brand-600'
              : 'bg-gray-400 hover:bg-gray-500 dark:bg-gray-500 dark:hover:bg-gray-600'
          ]"
                  type="submit">
            {{ $t('web.COMMON.button_send_feedback') }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
