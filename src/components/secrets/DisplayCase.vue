<script setup lang="ts">
import { defineProps } from 'vue'


interface Props {

  // Legacy props
  recipients?: string;
  secret_value?: string;
  secret_value_size?: string;
  secret_shortkey?: string;
  display_lines?: string;
}

defineProps<Props>()

</script>

<template>

  <div class="mb-4">
    <!--{{^can_decrypt}}-->
    <p class="mb-2 italic text-gray-600 dark:text-gray-400">
      {{ $t('web.COMMON.secret') }} ({{ secret_shortkey }}):
    </p>
    <input id="displayedsecret"
           class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
           value="{{$t('web.private.this_msg_is_encrypted')}}"
           readonly />
    <!--{{/can_decrypt}} -->
    <!--{{#can_decrypt}} {{#truncated}}-->
    <div
         class="bg-blue-100 border-l-4 border-blue-500 text-blue-700 p-4 mb-4 text-sm dark:bg-blue-800 dark:text-blue-200">
      <button type="button"
              class="float-right"
              onclick="this.parentElement.remove()">
        &times;
      </button>
      <strong>{{ $t('web.COMMON.warning') }}</strong> {{ $t('web.COMMON.secret_was_truncated') }}
      {{ secret_value_size }}. <!-- to_bytes -->
      <!--{{^authenticated}}-->
      <a href="/signup"
         class="text-brand-500 hover:underline">{{ $t('web.COMMON.signup_for_more') }}</a>
      <!--{{/authenticated}}.-->
    </div>
    <!--{{/truncated}}-->
    <p class="mb-2 italic text-gray-600 dark:text-gray-400">
      {{ $t('web.COMMON.secret') }} ({{ secret_shortkey }}):
      <span class="text-sm text-gray-500 dark:text-gray-400">({{ $t('web.private.only_see_once') }})</span>
    </p>
    <textarea class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white font-mono text-base leading-[1.2] tracking-wider resize-none"
              readonly
              :value="secret_value"
              :rows="display_lines"></textarea>

    <!--{{/can_decrypt}}-->
  </div>

</template>
