<!-- src/apps/colonel/components/DomainContextSwitcher.vue -->

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';

const STORAGE_KEY = 'domainContext';

const domainInput = ref('');
const currentContext = ref<string | null>(null);

// Load current context from sessionStorage on mount
onMounted(() => {
  try {
    currentContext.value = sessionStorage.getItem(STORAGE_KEY);
    if (currentContext.value) {
      domainInput.value = currentContext.value;
    }
  } catch {
    // sessionStorage may not be available
  }
});

const isActive = computed(() => !!currentContext.value);

const applyContext = () => {
  const domain = domainInput.value.trim();
  if (!domain) return;

  try {
    sessionStorage.setItem(STORAGE_KEY, domain);
    currentContext.value = domain;
  } catch (error) {
    console.error('Failed to set domain context:', error);
  }
};

const clearContext = () => {
  try {
    sessionStorage.removeItem(STORAGE_KEY);
    currentContext.value = null;
    domainInput.value = '';
  } catch (error) {
    console.error('Failed to clear domain context:', error);
  }
};

const handleKeydown = (event: KeyboardEvent) => {
  if (event.key === 'Enter') {
    applyContext();
  }
};
</script>

<template>
  <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
    <div class="mb-3 flex items-center justify-between">
      <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
        Domain Context Override
      </h3>
      <span
        v-if="isActive"
        class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/30 dark:text-amber-400">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mr-1 size-3" />
        Active
      </span>
    </div>

    <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
      Simulate a custom domain experience without DNS setup.
      Enter a domain to override the request context.
    </p>

    <!-- Current Context Display -->
    <div
      v-if="currentContext"
      class="mb-4 rounded-md border border-amber-200 bg-amber-50 p-3 dark:border-amber-700 dark:bg-amber-900/20">
      <div class="flex items-center justify-between">
        <div>
          <span class="text-xs font-medium text-amber-800 dark:text-amber-300">
            Current Override
          </span>
          <p class="mt-0.5 font-mono text-sm text-amber-900 dark:text-amber-100">
            {{ currentContext }}
          </p>
        </div>
        <OIcon
          collection="heroicons"
          name="globe-alt"
          class="size-5 text-amber-600 dark:text-amber-400" />
      </div>
    </div>

    <!-- Input and Actions -->
    <div class="space-y-3">
      <div>
        <label
          for="domain-context-input"
          class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
          Domain
        </label>
        <input
          id="domain-context-input"
          v-model="domainInput"
          type="text"
          placeholder="e.g., secrets.acme.com"
          class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-500 dark:focus:border-brand-400 dark:focus:ring-brand-400"
          @keydown="handleKeydown" />
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          :disabled="!domainInput.trim()"
          class="inline-flex flex-1 items-center justify-center rounded-md border border-transparent bg-brand-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition-colors hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600 dark:focus:ring-offset-gray-800"
          @click="applyContext">
          <OIcon
            collection="heroicons"
            name="check"
            class="mr-1.5 size-4" />
          Apply
        </button>
        <button
          v-if="isActive"
          type="button"
          class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm transition-colors hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800"
          @click="clearContext">
          <OIcon
            collection="heroicons"
            name="x-mark"
            class="mr-1.5 size-4" />
          Clear
        </button>
      </div>
    </div>

    <!-- Help Text -->
    <div class="mt-4 rounded-md bg-gray-50 p-3 dark:bg-gray-700/50">
      <h4 class="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
        How it works
      </h4>
      <ul class="space-y-1 text-xs text-gray-600 dark:text-gray-400">
        <li class="flex items-start">
          <span class="mr-1.5 text-gray-400">1.</span>
          Set a domain to simulate (real or fictional)
        </li>
        <li class="flex items-start">
          <span class="mr-1.5 text-gray-400">2.</span>
          All API requests will include the O-Domain-Context header
        </li>
        <li class="flex items-start">
          <span class="mr-1.5 text-gray-400">3.</span>
          Backend returns branding for that domain context
        </li>
        <li class="flex items-start">
          <span class="mr-1.5 text-gray-400">4.</span>
          Persists in sessionStorage until cleared
        </li>
      </ul>
    </div>
  </div>
</template>
