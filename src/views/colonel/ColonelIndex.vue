<script setup lang="ts">
import { useColonelStore } from '@/stores/colonelStore';
import { onMounted, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import { useI18n } from 'vue-i18n';
import { json } from '@codemirror/lang-json';
import { basicSetup } from 'codemirror';
import CodeMirror from 'vue-codemirror6';

const { t } = useI18n();

const tabs = [
  { name: t('Home'), href: '/colonel' },
  { name: t('stats'), href: '/colonel/info#stats' },
  { name: t('customers'), href: '/colonel/info#customers' },
  { name: t('feedback'), href: '/colonel/info#feedback' },
  { name: t('misc'), href: '/colonel/info#misc' },
];

const store = useColonelStore();
const { isLoading, config } = storeToRefs(store);
const { fetch, updateConfig } = store;

// Reference to the CodeMirror component
const cm = ref();

// Editor content for v-model
const editorContent = ref('');

// Editor configuration
const lang = json();
const extensions = [basicSetup];

// Update editor content when config changes
watch(
  () => config.value,
  (newConfig) => {
    if (newConfig) {
      editorContent.value = JSON.stringify(newConfig, null, 2);
      console.log('Config loaded:', editorContent.value);
    } else {
      console.warn('Config is null or undefined');
      editorContent.value = '';
    }
  }
);

onMounted(async () => {
  try {
    await fetch();
    // Initial config setup after fetch completes
    if (config.value) {
      editorContent.value = JSON.stringify(config.value, null, 2);
      console.log('Initial config loaded:', editorContent.value);
    } else {
      console.warn('No config available after fetch');
    }
  } catch (error) {
    console.error('Error fetching config:', error);
  }
});

const saveConfig = () => {
  try {
    const configValue = JSON.parse(editorContent.value);
    updateConfig(configValue);
    console.log('Config saved:', configValue);
  } catch (error) {
    console.error('Invalid JSON:', error);
    // Handle error - could show an error message to the user
  }
};
</script>

<template>
  <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
    <div
      id="primaryTabs"
      class="sticky top-0 z-10 border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <nav class="flex overflow-x-auto">
        <a
          v-for="tab in tabs"
          :key="tab.href"
          :href="tab.href"
          class="px-3 py-2 text-sm font-medium text-gray-600 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-400">
          {{ tab.name }}
        </a>
      </nav>
    </div>

    <div v-if="isLoading" class="p-6 text-center">Loading...</div>

    <div v-else class="p-6">
      <div class="mb-4">
        <h2 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('colonel.configEditor') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('colonel.configEditorDescription') }}
        </p>
      </div>

      <div class="border border-gray-300 rounded-md min-h-[400px] mb-4">
        <CodeMirror
          ref="cm"
          v-model="editorContent"
          :lang="lang"
          :extensions="extensions"
          basic
          placeholder="Enter configuration JSON"
          class="min-h-[400px]"
        />
      </div>

      <button
        @click="saveConfig"
        class="px-4 py-2 bg-brand-500 text-white rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
        {{ t('save') }}
      </button>
    </div>
  </div>
</template>
