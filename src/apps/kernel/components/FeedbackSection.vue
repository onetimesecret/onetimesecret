<!-- src/apps/kernel/components/FeedbackSection.vue -->

<script setup lang="ts">
import { Feedback } from '@/schemas/models/feedback'
defineProps<{
  title: string;
  count?: number;
  feedback?: Feedback[];
}>();
</script>

<template>
  <div class="p-2">
    <h4 class="mb-1 text-sm font-semibold text-gray-700 dark:text-gray-300">
      {{ title }} ({{ count }})
    </h4>
    <ul class="space-y-1">
      <li
        v-for="item in feedback"
        :key="item.msg"
        class="flex items-start justify-between rounded bg-gray-50 px-2 py-1 dark:bg-gray-900">
        <span class="grow text-gray-800 dark:text-gray-200">{{ item.msg }}</span>
        <span class="ml-2 whitespace-nowrap text-xs text-gray-500 dark:text-gray-400">{{ item.stamp }}</span>
      </li>
    </ul>
  </div>
</template>
