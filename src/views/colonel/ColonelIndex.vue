<!-- src/views/colonel/ColonelIndex.vue -->

<!-- https://codemirror.net/docs/guide/ -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelConfigStore } from '@/stores/colonelConfigStore';
  import { onMounted, computed } from 'vue';
  import { storeToRefs } from 'pinia';
  import { useI18n } from 'vue-i18n';
  import { json } from '@codemirror/lang-json';
  import { basicSetup } from 'codemirror';
  import CodeMirror from 'vue-codemirror6';
  import { type ColonelConfigDetails } from '@/schemas/api/endpoints/colonel';
  import { useColonelConfig, type ConfigSectionKey } from '@/composables/useColonelConfig';

  const { t } = useI18n();

  // Main navigation tabs
  const navTabs = [
    { name: t('Config'), href: '/colonel' },
    { name: t('Info'), href: '/colonel/info#stats' },
  ];

  // Config section tabs with typed keys
  const configSections = [
    { key: 'interface' as ConfigSectionKey, label: 'Interface' },
    { key: 'secret_options' as ConfigSectionKey, label: 'Secret Options' },
    { key: 'mail' as ConfigSectionKey, label: 'Mail' },
    { key: 'diagnostics' as ConfigSectionKey, label: 'Diagnostics' },
    { key: 'limits' as ConfigSectionKey, label: 'Limits' },
  ];

  const store = useColonelConfigStore();
  const { details: config } = storeToRefs(store);
  const { fetch } = store;

  // Use the colonel config composable
  const {
    activeSection,
    sectionEditors,
    validationState,
    validationMessages,
    errorMessage,
    saveSuccess,
    isSaving,
    isLoading,
    //hasValidationErrors,
    sectionsWithErrors,
    currentSectionHasError,
    modifiedSections,
    currentSectionCanSave,
    validateJson,
    initializeSectionEditors,
    //saveConfig,
    saveCurrentSection,
    markSectionModified,
    switchToSection,
    isProgrammaticChange,
  } = useColonelConfig();

  // Set initial active section
  activeSection.value = configSections[0].key;

  // Editor configuration
  const lang = json();
  const extensions = [basicSetup];

  // Computed property for the current section's content
  const currentSectionContent = computed({
    get: () => (activeSection.value ? sectionEditors.value[activeSection.value] || '' : ''),
    set: (val) => {
      console.log('currentSectionContent setter called:', {
        activeSection: activeSection.value,
        newValue: val,
        isProgrammatic: isProgrammaticChange.value
      });
      if (activeSection.value) {
        sectionEditors.value[activeSection.value] = val;
        // Only mark as modified and validate if the change wasn't programmatic
        if (!isProgrammaticChange.value) {
          markSectionModified(activeSection.value);
          validateJson(activeSection.value, val);
        }
      }
    },
  });

  // Update editor content when config changes
  // watch(() => config.value, (newConfig) => initializeSectionEditors(newConfig, configSections));

  onMounted(async () => {
    try {
      // Initialize with empty objects first
      initializeSectionEditors({} as ColonelConfigDetails, configSections);

      // Fetch config
      await fetch();

      if (config.value) {
        initializeSectionEditors(config.value, configSections);
      }
    } catch (error) {
      console.error('Error fetching config:', error);
      errorMessage.value = t('web.colonel.errorFetchingConfig');
    }
  });

  // Handle save actions
  //const handleSaveAll = () => saveConfig(configSections);
  const handleSaveSection = () => saveCurrentSection(configSections);

  // Handle section switching
  const handleSectionSwitch = (sectionKey: ConfigSectionKey) => {
    switchToSection(sectionKey);
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
            class="px-4 py-3 text-sm font-semibold transition-colors duration-150 border-b-2 mx-1 first:ml-0
            border-transparent hover:border-brand-500 hover:text-brand-600 focus:outline-none focus:border-brand-500
            dark:hover:text-brand-400 dark:hover:border-brand-400
            text-gray-700 dark:text-gray-200">
            {{ tab.name }}
          </a>
        </nav>
    </div>

    <div
      v-if="isLoading"
      class="p-6 text-center">
        {{t('web.LABELS.loading')}}
      </div>

    <div
      v-else
      class="p-6">
      <div class="mb-4">
        <h2 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.colonel.configEditor') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.colonel.configEditorDescription') }}
        </p>
      </div>

      <!-- Config section tabs -->
      <div class="mb-4 border-b border-gray-200">
        <nav class="-mb-px flex flex-wrap">
          <button
            v-for="section in configSections"
            :key="section.key"
            @click="handleSectionSwitch(section.key)"
            class="relative px-4 py-2 text-sm font-medium"
            :class="[
              activeSection === section.key
                ? 'border-b-2 border-brand-500 text-brand-600 dark:text-brand-400'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300',
            ]">
            {{ section.label }}

            <!-- Error indicator -->
            <span
              v-if="sectionsWithErrors.includes(section.key)"
              class="absolute -top-1 -right-1 size-2 rounded-full bg-red-500"
              :title="`${section.label} has validation errors`">
            </span>

            <!-- Modified indicator -->
            <span
              v-else-if="modifiedSections.has(section.key)"
              class="absolute -top-1 -right-1 size-2 rounded-full bg-blue-500"
              :title="`${section.label} has unsaved changes`">
            </span>
          </button>
        </nav>
      </div>

      <!-- Section status indicator -->
      <div v-if="activeSection" class="mb-2 text-sm">
        <span
          v-if="modifiedSections.has(activeSection)"
          class="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-medium text-blue-800 dark:bg-blue-900 dark:text-blue-200">
          <span class="mr-1 h-1.5 w-1.5 rounded-full bg-blue-400"></span>
          {{ t('web.colonel.unsavedChanges') }}
        </span>
        <span
          v-else-if="saveSuccess"
          class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900 dark:text-green-200">
          <span class="mr-1 h-1.5 w-1.5 rounded-full bg-green-400"></span>
          {{ t('web.LABELS.saved') }}
        </span>
      </div>

      <!-- Editor for current section -->
      <div class="mb-4">
        <div
          class="min-h-[400px] max-h-[600px] overflow-auto rounded-md border"
          :class="[
            currentSectionHasError
              ? 'border-red-500'
              : activeSection && validationState[activeSection] === true
                ? 'border-green-500'
                : 'border-gray-300',
          ]">

          <CodeMirror
            v-model="currentSectionContent"
            :lang="lang"
            :extensions="extensions"
            basic
            :placeholder="`Enter configuration for ${activeSection}`"
            class="min-h-[400px] max-h-[600px]" />
        </div>
        <div
          v-if="activeSection && validationMessages[activeSection]"
          class="mt-2 text-sm text-red-600 dark:text-red-400">
          {{ validationMessages[activeSection] }}
        </div>
      </div>

      <!-- Error and Success messages -->
      <div class="mb-4 space-y-3">
        <!-- Error message -->
        <div
          v-if="errorMessage"
          class="rounded-md border border-red-400 bg-red-100 p-3 text-red-700">
          <div class="flex items-start justify-between">
            <div class="flex items-center">
              <span class="mr-2">⚠️</span>
              <span>{{ errorMessage }}</span>
            </div>
            <button
              @click="errorMessage = null"
              class="ml-3 text-sm text-red-700 hover:underline focus:outline-none">
              {{ t('web.LABELS.dismiss') }}
            </button>
          </div>
        </div>

        <!-- Success message -->
        <div
          v-if="saveSuccess"
          class="rounded-md border border-green-400 bg-green-100 p-3 text-green-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <span class="mr-2">✅</span>
              <span>{{ t('web.colonel.configSaved') }}</span>
            </div>
            <button
              @click="saveSuccess = false"
              class="ml-3 text-sm text-green-700 hover:underline focus:outline-none">
              <OIcon collection="heroicons" name="x-mark" />
            </button>
          </div>
        </div>
      </div>

      <!-- Action buttons -->
      <div class="flex space-x-3">
        <!-- Save current section button -->
        <button
          v-if="currentSectionCanSave"
          @click="handleSaveSection"
          class="rounded-md bg-brand-600 px-4 py-2 text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          :disabled="isSaving">
          {{ isSaving ? t('web.LABELS.saving') : t('web.colonel.saveSection', { section: configSections.find(s => s.key === activeSection)?.label }) }}
        </button>

        <!-- Save all button -->
        <!-- <button
          @click="handleSaveAll"
          class="rounded-md bg-brand-500 px-4 py-2 text-white hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
          :disabled="isSaving || hasValidationErrors">
          {{ isSaving ? t('web.LABELS.saving') : t('web.colonel.saveAll') }}
        </button> -->
      </div>
    </div>
  </div>
</template>
