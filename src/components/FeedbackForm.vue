<template>
  <div class="container">

    <div class="mb-6 bg-gray-100 dark:bg-gray-700 p-4 rounded-lg">
      <h3 class="font-semibold mb-2 text-gray-700 dark:text-gray-300 text-sm">
        Information included with your feedback
      </h3>
      <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
        <li class="flex items-center">
          <svg class="h-4 w-4 mr-2 text-brand-500"
               width="16"
               height="16"
               fill="none"
               viewBox="0 0 24 24"
               stroke="currentColor">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          Timezone: {{ userTimezone }}
        </li>
        <li class="flex items-center">
          <svg class="h-4 w-4 mr-2 text-brand-500"
               width="16"
               height="16"
               fill="none"
               viewBox="0 0 24 24"
               stroke="currentColor">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
          </svg>
          Version: v{{ ot_version }}
        </li>
        <li v-if="cust"
            class="flex items-center">
          <svg class="h-4 w-4 mr-2 text-brand-500"
               width="16"
               height="16"
               fill="none"
               viewBox="0 0 24 24"
               stroke="currentColor">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
          </svg>
          Customer ID: {{ cust?.custid }}
        </li>
      </ul>
    </div>

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
              : 'bg-gray-400 hover:bg-gray-500 dark:bg-gray-500 dark:hover:bg-gray-600']"
                  type="submit">
            {{ $t('web.COMMON.button_send_feedback') }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useCsrfStore } from '@/stores/csrfStore';
import { useWindowProps } from '@/composables/useWindowProps';

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

const userTimezone = ref('');

onMounted(() => {
  userTimezone.value = Intl.DateTimeFormat().resolvedOptions().timeZone;
});

// We use this to determine whether to include the authenticity check
const { cust, ot_version } = useWindowProps(['cust', 'ot_version']);

</script>
