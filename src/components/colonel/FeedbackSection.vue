<template>
  <div class="p-2">
    <h4 class="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-1">
      {{ title }} ({{ count }})
    </h4>
    <ul class="space-y-1">
      <li
        v-for="item in feedback"
        :key="item.stamp"
        class="bg-gray-50 dark:bg-gray-900 rounded px-2 py-1 flex justify-between items-start"
      >
        <span class="text-gray-800 dark:text-gray-200 flex-grow">{{ item.msg }}</span>
        <span class="text-xs text-gray-500 dark:text-gray-400 ml-2 whitespace-nowrap">{{ item.stamp }}</span>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  title: string;
  count: number;
  feedback: { msg: string; stamp: string }[];
}>();
</script>
