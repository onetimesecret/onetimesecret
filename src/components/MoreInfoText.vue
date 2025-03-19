<!-- src/components/MoreInfoText.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
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
  <div :class="`mb-4 ${props.bgColor} shadow sm:rounded-lg`">
    <div class="px-4 py-5 sm:p-4">
      <button
        @click="toggleExpand"
        :class="`flex items-center text-base font-medium ${props.textColor} hover:text-brandcomp-600 dark:hover:text-brandcomp-400 focus:outline-none`">
        <OIcon
          collection="heroicons"
          :name="isExpanded ? 'chevron-down' : 'chevron-right'"
          class="mr-2 size-5"
        />
        {{ isExpanded ? 'Hide details' : 'Expand for more info' }}
      </button>
      <div
        v-show="isExpanded"
        class="relative mt-2 overflow-hidden rounded-lg border border-gray-200 bg-gray-50 shadow-lg transition-all duration-300 ease-in-out dark:border-gray-600 dark:bg-gray-700">
        <div class="min-w-0 p-4">
          <slot></slot>
        </div>
      </div>
    </div>
  </div>
</template>
