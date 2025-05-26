<script setup lang="ts">
import { useColonelConfigStore } from '@/stores/colonelConfigStore';
import { onMounted, ref, watch, computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useI18n } from 'vue-i18n';
import { json } from '@codemirror/lang-json';
import { basicSetup } from 'codemirror';
import CodeMirror from 'vue-codemirror6';
import { colonelConfigSchema, type ColonelConfigDetails } from '@/schemas/api/endpoints/colonel';
import { z } from 'zod';

const { t } = useI18n();

// Main navigation tabs
const navTabs = [
  { name: t('Home'), href: '/colonel' },
  { name: t('stats'), href: '/colonel/info#stats' },
  { name: t('customers'), href: '/colonel/info#customers' },
  { name: t('feedback'), href: '/colonel/info#feedback' },
  { name: t('misc'), href: '/colonel/info#misc' },
];

// Config section tabs with typed keys
type ConfigSectionKey = keyof ColonelConfigDetails;

const configSections = [
  { key: 'interface' as ConfigSectionKey, label: 'Interface' },
  { key: 'secret_options' as ConfigSectionKey, label: 'Secret Options' },
  { key: 'mail' as ConfigSectionKey, label: 'Mail' },
  { key: 'diagnostics' as ConfigSectionKey, label: 'Diagnostics' },
  { key: 'limits' as ConfigSectionKey, label: 'Limits' },
  { key: 'development' as ConfigSectionKey, label: 'Development' },
];

const store = useColonelConfigStore();
const { isLoading, details: config } = storeToRefs(store);
const { fetch, update } = store;

// Currently active section
const activeSection = ref<ConfigSectionKey>(configSections[0].key);

// Editor contents for each section
const sectionEditors = ref<Record<ConfigSectionKey, string>>({} as Record<ConfigSectionKey, string>);

// Validation state
const validationState = ref<Record<ConfigSectionKey, boolean>>({} as Record<ConfigSectionKey, boolean>);
const validationMessages = ref<Record<ConfigSectionKey, string | null>>({} as Record<ConfigSectionKey, string | null>);

// Error messages
const errorMessage = ref<string | null>(null);
const saveSuccess = ref<boolean>(false);
const isSaving = ref<boolean>(false);

// Editor configuration
const lang = json();
const extensions = [basicSetup];

// Computed property for the current section's content
const currentSectionContent = computed({
  get: () => sectionEditors.value[activeSection.value] || '',
  set: (val) => {
    sectionEditors.value[activeSection.value] = val;
    validateJson(activeSection.value, val);
  }
});

// Check if JSON is valid
const validateJson = (section: ConfigSectionKey, content: string) => {
  try {
    // Handle empty string as valid (will be converted to empty object)
    if (content.trim() === '') {
      content = '{}';
      sectionEditors.value[section] = content;
    }

    // Parse to validate JSON
    const parsed = JSON.parse(content);

    // Additional check: ensure it's actually an object, not null, array, etc.
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error(t('colonel.mustBeObject'));
    }

    validationState.value[section] = true;
    validationMessages.value[section] = null;
  } catch (error) {
    validationState.value[section] = false;
    if (error instanceof Error) {
      validationMessages.value[section] = error.message;
    } else {
      validationMessages.value[section] = t('colonel.invalidJson', { section });
    }
  }
};

/**
 * Initialize section editors with config data
 */
const initializeSectionEditors = (configData: ColonelConfigDetails | null) => {
  console.debug('Initializing section editors with config data:', configData);
  // Always initialize all sections, falling back to empty objects as needed
  configSections.forEach(section => {
    try {
      // Get section data or use empty object as fallback
      const sectionData = configData && configData[section.key] ? configData[section.key] : {};
      // Format JSON with proper indentation
      const content = JSON.stringify(sectionData, null, 2);
      // Store in editor state
      sectionEditors.value[section.key] = content;
      // Validate (will be valid since we're using empty object as fallback)
      validateJson(section.key, content);
    } catch (error) {
      console.error(`Error initializing section ${section.key}:`, error);
      // Default to empty object on error
      sectionEditors.value[section.key] = '{}';
      validateJson(section.key, '{}');
    }
  });
};

// Update editor content when config changes
watch(() => config.value, initializeSectionEditors);

onMounted(async () => {
  try {

    // Then explicitly fetch config
    fetch();

    if (!config.value) {
      console.warn('Config data is null or undefined after fetching');
      // Initialize with empty objects to allow editing
      initializeSectionEditors({} as ColonelConfigDetails);
    } else {
      // Initial config setup after fetch completes
      initializeSectionEditors(config.value);
    }
  } catch (error) {
    console.error('Error fetching config:', error);
    errorMessage.value = t('colonel.errorFetchingConfig');
    // Initialize with empty objects to allow editing even after error
    initializeSectionEditors({} as ColonelConfigDetails);
  }
});

/**
 * Save the configuration after validating with Zod schema
 */
const saveConfig = async () => {
  errorMessage.value = null;
  saveSuccess.value = false;
  isSaving.value = true;

  try {
    // Validate all sections first
    let hasInvalidSection = false;

    for (const section of configSections) {
      validateJson(section.key, sectionEditors.value[section.key] || '{}');
      if (validationState.value[section.key] === false) {
        hasInvalidSection = true;
        activeSection.value = section.key; // Switch to invalid section
        errorMessage.value = t('colonel.invalidJson', { section: section.label });
        console.error(`Invalid JSON in section ${section.key}:`, validationMessages.value[section.key]);
        isSaving.value = false;
        return;
      }
    }

    // Combine all section editors into a single config object
    const combinedConfig: Partial<ColonelConfigDetails> = {};

    for (const section of configSections) {
      const sectionContent = sectionEditors.value[section.key];
      if (sectionContent) {
        combinedConfig[section.key] = JSON.parse(sectionContent);
      }
    }

    console.debug('Combined config before validation:', combinedConfig);

    // Validate the combined config against the schema
    try {
      colonelConfigSchema.parse(combinedConfig);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        const firstError = validationError.errors[0];
        const errorPath = firstError.path.length > 0 ? firstError.path.join('.') : 'root';
        errorMessage.value = `${t('colonel.validationError')}: ${errorPath} - ${firstError.message}`;
        console.error('Validation error:', validationError);

        // Try to set active section to the one with the error if possible
        const errorSection = firstError.path[0];
        if (errorSection && typeof errorSection === 'string') {
          const matchingSection = configSections.find(s => s.key === errorSection as ConfigSectionKey);
          if (matchingSection) {
            activeSection.value = matchingSection.key;
          }
        }

        isSaving.value = false;
        return;
      }
      throw validationError;
    }

    try {
      await update(combinedConfig as ColonelConfigDetails);

      // Refetch config to ensure we have the latest data
      fetch();

      saveSuccess.value = true;
      console.log('Config saved successfully');
    } catch (updateError) {
      console.error('Error updating config:', updateError);
      errorMessage.value = t('colonel.errorSavingConfig');
      if (updateError instanceof Error) {
        errorMessage.value += `: ${updateError.message}`;
      }
    }
  } catch (error) {
    errorMessage.value = t('colonel.errorSavingConfig');
    console.error('Error saving config:', error);
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
    <!-- Main navigation tabs -->
    <div
      id="primaryTabs"
      class="sticky top-0 z-10 border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <nav class="flex overflow-x-auto">
        <a
          v-for="tab in navTabs"
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

      <!-- Config section tabs -->
      <div class="mb-4 border-b border-gray-200">
        <nav class="flex flex-wrap -mb-px">
          <button
            v-for="section in configSections"
            :key="section.key"
            @click="activeSection = section.key"
            class="px-4 py-2 text-sm font-medium"
            :class="[
              activeSection === section.key
                ? 'border-b-2 border-brand-500 text-brand-600 dark:text-brand-400'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
            ]">
            {{ section.label }}
          </button>
        </nav>
      </div>

      <!-- Editor for current section -->
      <div class="mb-4">
        <div
          class="border rounded-md min-h-[400px]"
          :class="[
            validationState.value[activeSection] === false
              ? 'border-red-500'
              : validationState.value[activeSection] === true
                ? 'border-green-500'
                : 'border-gray-300'
          ]"
        >
          <CodeMirror
            v-model="currentSectionContent"
            :lang="lang"
            :extensions="extensions"
            basic
            :placeholder="`Enter configuration for ${activeSection}`"
            class="min-h-[400px]"
          />
        </div>
        <div
          v-if="validationMessages.value[activeSection]"
          class="mt-2 text-sm text-red-600 dark:text-red-400"
        >
          {{ validationMessages.value[activeSection] }}
        </div>
      </div>

      <!-- Error message -->
      <div v-if="errorMessage" class="mt-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded-md">
        <div class="flex items-center">
          <span class="mr-2">⚠️</span>
          <span>{{ errorMessage }}</span>
        </div>
        <button
          v-if="errorMessage"
          @click="errorMessage = null"
          class="mt-2 text-sm text-red-700 hover:underline"
        >
          {{ t('dismiss') }}
        </button>
      </div>

      <!-- Success message -->
      <div v-if="saveSuccess" class="mt-4 p-3 bg-green-100 border border-green-400 text-green-700 rounded-md">
        <div class="flex items-center">
          <span class="mr-2">✅</span>
          <span>{{ t('colonel.configSaved') }}</span>
        </div>
      </div>

      <button
        @click="saveConfig"
        class="px-4 py-2 bg-brand-500 text-white rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
        :disabled="isSaving || Object.values(validationState.value).some(state => state === false)">
        {{ isSaving ? t('saving') : t('save') }}
      </button>
    </div>
  </div>
</template>
