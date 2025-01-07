<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { ref } from 'vue';

const isExpanded = ref(false);
const toggleExpand = (event: Event) => {
  event.preventDefault();
  isExpanded.value = !isExpanded.value;
};

interface Props {
  textColor?: string;
  bgColor?: string;
}

const props = withDefaults(defineProps<Props>(), {
  textColor: 'text-brandcomp-800 dark:text-gray-100',
  bgColor: 'bg-white dark:bg-gray-800',
});
</script>

<template>
  <div :class="`mb-4 ${props.bgColor} shadow sm:rounded-lg relative`">
    <div class="px-4 py-5 sm:p-4">
      <button
        @click="toggleExpand"
        :class="`flex items-center text-base font-medium ${props.textColor} hover:text-brandcomp-600 dark:hover:text-brandcomp-400 focus:outline-none`">
        <Icon
          :icon="isExpanded ? 'heroicons:chevron-down' : 'heroicons:chevron-right'"
          class="mr-2 size-5"
        />
        {{ isExpanded ? 'Hide details' : 'Expand for more info' }}
      </button>

      <div
        v-show="isExpanded"
        class="absolute inset-x-4 z-10 mt-2 overflow-hidden rounded-lg border border-gray-200 bg-gray-50 shadow-lg transition-all duration-300 ease-in-out dark:border-gray-600 dark:bg-gray-700"
        :class="{ 'max-h-0': !isExpanded, 'max-h-[500px]': isExpanded }">
        <slot></slot>
      </div>
    </div>
  </div>
</template>
