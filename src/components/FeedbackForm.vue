<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';

export interface Props {
  enabled?: boolean;
  shrimp: string | null;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  shrimp: null,
})

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

        <AltchaChallenge />

        <input type="text"
               name="msg"
               class="flex-grow px-4 py-2 border rounded-l-md
          border-gray-300 focus:ring-gray-300 focus:border-transparent
          dark:bg-gray-700 dark:border-gray-600 dark:text-gray-200
          focus:outline-none focus:ring-2"
               autocomplete="off"
               placeholder="{{i18n.COMMON.feedback_text}}">

        <button class="px-4 py-2 font-light rounded-r-md
            bg-gray-300
            dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-800 dark:text-gray-200
            hover:bg-gray-400"
                type="submit">
          <!--{{i18n.COMMON.button_send_feedback}}-->
          Send Feedback
        </button>

      </div>
    </form>
  </div>
</template>
