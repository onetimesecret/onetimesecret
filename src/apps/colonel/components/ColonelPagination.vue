<!-- src/apps/colonel/components/ColonelPagination.vue -->

<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  pagination: {
    page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
  loading?: boolean;
}>();

const emit = defineEmits<{
  'update:page': [page: number];
  'update:perPage': [perPage: number];
}>();

const perPageOptions = [25, 50, 100];

const rangeStart = computed(() => {
  if (props.pagination.total_count === 0) return 0;
  return (props.pagination.page - 1) * props.pagination.per_page + 1;
});

const rangeEnd = computed(() => {
  const end = props.pagination.page * props.pagination.per_page;
  return Math.min(end, props.pagination.total_count);
});

const canGoPrev = computed(() => props.pagination.page > 1);
const canGoNext = computed(() => props.pagination.page < props.pagination.total_pages);

function handlePrev() {
  if (canGoPrev.value && !props.loading) {
    emit('update:page', props.pagination.page - 1);
  }
}

function handleNext() {
  if (canGoNext.value && !props.loading) {
    emit('update:page', props.pagination.page + 1);
  }
}

function handlePerPageChange(event: Event) {
  const target = event.target as HTMLSelectElement;
  emit('update:perPage', Number(target.value));
}
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-4 text-sm text-gray-600 dark:text-gray-400">
    <!-- Summary -->
    <div>
      Showing {{ rangeStart }}–{{ rangeEnd }} of {{ pagination.total_count }}
    </div>

    <div class="flex items-center gap-4">
      <!-- Per-page selector -->
      <div class="flex items-center gap-2">
        <label
          for="per-page-select"
          class="sr-only">
          Items per page
        </label>
        <select
          id="per-page-select"
          :value="pagination.per_page"
          :disabled="loading"
          class="rounded border border-gray-300 bg-white px-2 py-1 text-sm text-gray-700 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
          @change="handlePerPageChange">
          <option
            v-for="option in perPageOptions"
            :key="option"
            :value="option">
            {{ option }} per page
          </option>
        </select>
      </div>

      <!-- Page indicator -->
      <div>
        Page {{ pagination.page }} of {{ pagination.total_pages }}
      </div>

      <!-- Navigation buttons -->
      <div class="flex gap-1">
        <button
          type="button"
          :disabled="!canGoPrev || loading"
          class="rounded border border-gray-300 px-3 py-1 text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="handlePrev">
          Prev
        </button>
        <button
          type="button"
          :disabled="!canGoNext || loading"
          class="rounded border border-gray-300 px-3 py-1 text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="handleNext">
          Next
        </button>
      </div>
    </div>
  </div>
</template>
