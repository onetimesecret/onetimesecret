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

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { ref, computed } from 'vue';

  const props = defineProps({
    color: {
      type: String,
      default: 'bg-white text-gray-800',
    },
  });

  const isModalVisible = ref(false);

  const toggleModal = () => {
    isModalVisible.value = !isModalVisible.value;
  };

  const closeModal = () => {
    isModalVisible.value = false;
  };

  const modalClasses = computed(() => `${props.color} border-2 border-dashed`);
</script>

<template>
  <div class="relative mx-1 inline-block">
    <OIcon
      collection="heroicons"
      name="information-circle"
      class="inline cursor-pointer align-baseline text-base"
      @click="toggleModal"
    />

    <Transition name="fade">
      <div
        v-if="isModalVisible"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
        @click="closeModal">
        <div
          :class="['relative max-w-md rounded-lg p-6 shadow-lg', modalClasses]"
          @click.stop>
          <button
            @click="closeModal"
            class="absolute right-2 top-2 text-gray-500 hover:text-gray-700">
            <OIcon collection="heroicons" name="x-mark-20-solid" />
          </button>
          <slot></slot>
        </div>
      </div>
    </Transition>
  </div>
</template>

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
