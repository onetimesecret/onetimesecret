<!--
  Usage:

  <InfoTooltip>
    <p>This is some information inside the tooltip modal.</p>
  </InfoTooltip>
 -->

<!--
  ## FEATURE: Click outside to close.

  This tooltip dialog can be closed by clicking outside the content
  area due to the `@click="closeModal"` event listener on the outer
  div with the class
  `fixed inset-0 bg-black bg-opacity-30 flex items-center justify-center z-50`.
  This event listener triggers the `closeModal` method, which sets
  `isModalVisible` to false.

  ### Explanation

  * Outer div with `@click="closeModal"`: This div covers the entire
    screen when the modal is visible. Clicking anywhere on this div
    (outside the modal content) will trigger the closeModal method.

  * Inner div with `@click.stop`: This div contains the modal content
    and has the @click.stop directive to stop the click event from
    propagating to the outer div. This prevents the modal from
    closing when clicking inside the content area.
-->

<template>
  <div class="relative inline-block mx-1">
    <Icon icon="heroicons:information-circle"
          class="inline align-baseline cursor-pointer text-base"
          @click="toggleModal" />

    <Transition name="fade">
      <div v-if="isModalVisible"
           class="fixed inset-0 bg-black bg-opacity-70 flex items-center justify-center z-50"
           @click="closeModal">
        <div :class="['relative max-w-md p-6 rounded-lg shadow-lg', modalClasses]"
             @click.stop>
          <button @click="closeModal"
                  class="absolute top-2 right-2 text-gray-500 hover:text-gray-700">
            <Icon icon="heroicons:x-mark-20-solid" />
          </button>
          <slot></slot>
        </div>
      </div>
    </Transition>

  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { ref, computed } from 'vue';

const props = defineProps({
  color: {
    type: String,
    default: 'bg-white text-gray-800'
  }
});

const isModalVisible = ref(false);

const toggleModal = () => {
  isModalVisible.value = !isModalVisible.value;
};

const closeModal = () => {
  isModalVisible.value = false;
};

const modalClasses = computed(() => {
  return `${props.color} border-2 border-dashed`;
});
</script>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Add this new rule */
.fade-enter-to,
.fade-leave-from {
  opacity: 1;
}
</style>
