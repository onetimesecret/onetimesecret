<!-- src/shared/components/ui/notifications/inline/InlineToast.vue -->
<!--
  Small dark toast positioned relative to a parent container (not the
  viewport). Used for ephemeral confirmations like "Copied!" inside a
  table row or card. The parent must have `position: relative`.

  Prop-driven, no store — the consumer manages show/hide with a local
  ref and setTimeout.

  Previously: ToastNotification.vue (in ui/)
-->

<script setup lang="ts">
defineProps<{
  show: boolean;
  message: string;
}>();
</script>

<template>
  <div
    v-if="show"
    role="status"
    aria-live="polite"
    class="absolute right-3 top-3 rounded-md bg-gray-900 px-3 py-1.5 text-sm text-white shadow-lg dark:bg-gray-700">
    {{ message }}
  </div>
</template>
