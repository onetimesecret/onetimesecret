<!--

  USAGE EXAMPLE:

    <SecretFormDrawer
      title="Privacy Options"
      border="dashed"
      expandedBg="bg-blue-50 dark:bg-blue-900"
      collapsedBg="bg-gray-100 dark:bg-gray-800">
      ...
    </SecretFormDrawer>

  About the click Behaviour:

  * The @click="toggleExpanded" is on the header div that contains the
    title and chevron icon.
  * The div that contains the slot content has @click.stop to prevent
    click events within the slot from propagating up to parent elements.
  * The cursor-pointer class is on the header div.
  * These details ensure that:

  * The drawer can be collapsed by clicking on the header area (title or chevron icon).
  * Interactions with elements inside the expanded content (slot) won't cause the drawer to
    collapse.
  * The cursor changes to a pointer only when hovering over the header, indicating that only
    this area is clickable for expanding/collapsing.
  * This solution maintains the desired functionality while fixing the encountered bug.

-->
<template>
  <div :class="[
    'transition-all duration-200 ease-in-out rounded-lg',
    borderClass,
    isExpanded
      ? `mb-3 p-3 ${expandedBgClass}`
      : `mb-2 p-2 ${collapsedBgClass}`
  ]">
    <div @click="toggleExpanded"
         class="flex justify-between items-center cursor-pointer">
      <p class="text-base font-brand font-medium text-gray-700 dark:text-gray-300">
        {{ title }}
      </p>
      <Icon :icon="isExpanded ? 'mdi:chevron-up' : 'mdi:chevron-down'"
            class="w-5 h-5 text-gray-500 dark:text-gray-400" />
    </div>
    <div v-if="isExpanded"
         class="mt-2"
         @click.stop>
      <slot></slot>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { Icon } from '@iconify/vue';

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
  }
});

const isExpanded = ref(false);

const toggleExpanded = () => {
  isExpanded.value = !isExpanded.value;
  localStorage.setItem(`${props.title}Expanded`, isExpanded.value.toString());
};

// Load the expanded state from localStorage
isExpanded.value = localStorage.getItem(`${props.title}Expanded`) === 'true';

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
