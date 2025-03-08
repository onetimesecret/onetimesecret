<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { ref, watch, computed, onMounted } from 'vue';

const props = defineProps({
  title: {
    type: String,
    required: true
  },
  border: {
    type: String,
    default: 'default',
    validator: (value: string) => ['none', 'default', 'dashed'].includes(value)
  },
  expandedBg: {
    type: String,
    default: 'bg-white dark:bg-gray-800'
  },
  collapsedBg: {
    type: String,
    default: 'bg-gray-50 dark:bg-gray-700'
  },
  cornerClass: {
    type: String,
    default: ''
  },
  id: {
    type: String,
    default: ''
  }
});

const isExpanded = ref(false);
const headerId = computed(() => `${uniqueId.value}-header`);
const contentId = computed(() => `${uniqueId.value}-content`);
const uniqueId = computed(() => props.id || `drawer-${props.title.replace(/\s+/g, '-').toLowerCase()}`);

const toggleExpanded = () => {
  isExpanded.value = !isExpanded.value;
  localStorage.setItem(`${props.title}Expanded`, isExpanded.value.toString());
};

// Handle keyboard events
const handleKeyDown = (event: KeyboardEvent) => {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    toggleExpanded();
  }
};

onMounted(() => {
  // Load the expanded state from localStorage
  isExpanded.value = localStorage.getItem(`${props.title}Expanded`) === 'true';
});

// Watch for changes in isExpanded and save to localStorage
watch(isExpanded, (newValue) => {
  localStorage.setItem(`${props.title}Expanded`, newValue.toString());
});

const borderClass = computed(() => {
  switch (props.border) {
    case 'none':
      return '';
    case 'dashed':
      return 'border-2 border-dashed border-gray-300 dark:border-gray-600';
    default:
      return 'border border-gray-300 dark:border-gray-600';
  }
});

const expandedBgClass = computed(() => props.expandedBg);
const collapsedBgClass = computed(() => props.collapsedBg);
</script>

<template>
  <div :class="[
      'rounded-lg transition-all duration-200 ease-in-out',
      cornerClass,
      borderClass,
      isExpanded
        ? `mb-3 p-3 ${expandedBgClass}`
        : `mb-2 p-2 ${collapsedBgClass}`
    ]">
    <div :id="headerId"
         role="button"
         tabindex="0"
         :aria-expanded="isExpanded"
         :aria-controls="contentId"
         @click="toggleExpanded"
         @keydown="handleKeyDown"
         class="flex cursor-pointer items-center justify-between">
      <p class="font-brand text-base font-medium text-gray-700 dark:text-gray-300">
        {{ title }}
      </p>
      <OIcon collection="mdi"
             :name="isExpanded ? 'chevron-up' : 'chevron-down'"
             class="size-5 text-gray-500 dark:text-gray-400"
             aria-hidden="true" />
    </div>
    <div v-if="isExpanded"
         :id="contentId"
         role="region"
         :aria-labelledby="headerId"
         class="mt-2"
         @click.stop>
      <slot></slot>
    </div>
  </div>
</template>

<style scoped>
.v-enter-active,
.v-leave-active {
  transition: opacity 0.3s ease, max-height 0.3s ease;
}

.v-enter-from,
.v-leave-to {
  opacity: 0;
}
</style>
