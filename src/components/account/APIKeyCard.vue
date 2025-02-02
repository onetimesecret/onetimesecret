<!-- src/components/ApiTokenDisplay.vue -->
<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { ref } from 'vue';

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

<template>
  <div
    v-if="apitoken"
    class="mb-4 rounded-lg bg-gradient-to-r from-pink-500 via-red-500 to-yellow-400 p-4 shadow-lg">
    <div class="font-mono text-lg text-white">
      <div class="relative flex items-center overflow-x-auto rounded bg-black bg-opacity-20 p-3">
        <span class="break-all pr-10">{{ apitoken }}</span>
        <button
          @click.stop="handleCopy"
          type="button"
          class="absolute right-2 top-1/2 -translate-y-1/2 text-white transition-colors duration-200 hover:text-gray-200">
          <OIcon
            collection="heroicons"
            :name="copied ? 'check' : 'clipboard'"
            class="size-6"
          />
        </button>
      </div>
    </div>
    <p class="mt-2 text-sm font-semibold text-white">
      {{ $t('keep-this-token-secure-it-provides-full-access-t') }}
    </p>
  </div>
</template>

<style scoped>
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(-10px); }
  to { opacity: 1; transform: translateY(0); }
}

.api-token-container {
  animation: fadeIn 0.5s ease-out;
}
</style>
