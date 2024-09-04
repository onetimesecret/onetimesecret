<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';

export interface Props {
  enabled?: boolean;
  shrimp: string | null;
  showRedButton: boolean | null;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  shrimp: null,
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
             :value="shrimp" />
      <div class="flex mb-4">

        <AltchaChallenge v-if="!cust" />

        <div class="flex flex-grow focus-within:ring-1 focus-within:ring-brandcomp-500 rounded-md overflow-hidden">
          <input type="text"
                 name="msg"
                 class="flex-grow px-4 py-2 border-y border-l
                              focus:border-brandcomp-500
                              dark:bg-gray-700 dark:border-gray-600 dark:text-gray-200
                              focus:outline-none"
                 autocomplete="off"
                 placeholder="">
                 <!--i18n.COMMON.feedback_text-->

          <button :class="[
              'px-4 py-2 font-light text-white transition duration-150 ease-in-out',
              showRedButton
                ? 'bg-brand-500 hover:bg-brand-600'
                : 'bg-gray-500 hover:bg-gray-600 dark:bg-gray-600 dark:hover:bg-gray-700'
            ]"
                  type="submit">
            <!--{{i18n.COMMON.button_send_feedback}}-->
            Send Feedback
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
