<template>
  <div class="relative inline-block">
    <Icon icon="heroicons:information-circle-20-solid"
          class="inline align-baseline cursor-pointer"
          @click="toggleModal" />
    <Transition name="fade">
      <div v-if="isModalVisible"
           class="fixed inset-0 bg-black bg-opacity-30 flex items-center justify-center z-50"
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
import { ref, computed } from 'vue';
import { Icon } from '@iconify/vue';

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
</style>
