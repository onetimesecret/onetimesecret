<!-- src/components/ApiTokenDisplay.vue -->
<template>
  <div v-if="apitoken" class="mb-4 p-4 bg-gradient-to-r from-pink-500 via-red-500 to-yellow-400 rounded-lg shadow-lg">
    <div class="font-mono text-lg text-white">
      <div class="bg-black bg-opacity-20 p-3 rounded flex items-center overflow-x-auto relative">
        <span class="break-all pr-10">{{ apitoken }}</span>
        <button
          @click.stop="handleCopy"
          type="button"
          class="absolute right-2 top-1/2 transform -translate-y-1/2 text-white hover:text-gray-200 transition-colors duration-200">
          <Icon :icon="copied ? 'heroicons-outline:check' : 'heroicons-outline:clipboard-copy'" class="w-6 h-6" />
        </button>
      </div>
    </div>
    <p class="text-white text-sm mt-2 font-semibold">
      🔐 Keep this token secure! It provides full access to your account.
    </p>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { Icon } from '@iconify/vue';

interface Props {
  apitoken: string | undefined;
  onCopy?: () => void;
}

const props = withDefaults(defineProps<Props>(), {
  apitoken: '',
  onCopy: () => {}
});

const copied = ref(false);

const handleCopy = () => {
  navigator.clipboard.writeText(props.apitoken)
    .then(() => {
      copied.value = true;
      setTimeout(() => {
        copied.value = false;
      }, 2000); // Reset after 2 seconds
      props.onCopy(); // Call the onCopy prop function if provided
    })
    .catch(err => {
      console.error('Failed to copy text: ', err);
    });
};
</script>

<style scoped>
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(-10px); }
  to { opacity: 1; transform: translateY(0); }
}

.api-token-container {
  animation: fadeIn 0.5s ease-out;
}
</style>
