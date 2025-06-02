<!-- src/views/colonel/SystemSettings.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import ColonelNavigation from '@/components/colonel/ColonelNavigation.vue';
  import { useSystemSettingsStore } from '@/stores/systemSettingsStore';
  import { onMounted, computed } from 'vue';
  import { storeToRefs } from 'pinia';
  import { useI18n } from 'vue-i18n';
  import { json } from '@codemirror/lang-json';
  import { basicSetup } from 'codemirror';
  import { oneDark } from '@codemirror/theme-one-dark';
  import { EditorView } from '@codemirror/view';
  import CodeMirror from 'vue-codemirror6';
  import { type SystemSettingsDetails } from '@/schemas/api/endpoints/colonel';
  import { useSystemSettings, type ConfigSectionKey } from '@/composables/useSystemSettings';
  import { useTheme } from '@/composables/useTheme';

  const { t } = useI18n();
  const { isDarkMode } = useTheme();

  // Config section tabs with typed keys
  const configSections = [
    { key: 'interface' as ConfigSectionKey, label: 'Interface' },
    { key: 'secret_options' as ConfigSectionKey, label: 'Secret Options' },
    { key: 'mail' as ConfigSectionKey, label: 'Mail' },
    { key: 'diagnostics' as ConfigSectionKey, label: 'Diagnostics' },
    { key: 'limits' as ConfigSectionKey, label: 'Limits' },
  ];

  const store = useSystemSettingsStore();
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
    sectionsWithErrors,
    currentSectionHasError,
    modifiedSections,
    currentSectionCanSave,
    validateJson,
    initializeSectionEditors,
    saveCurrentSection,
    markSectionModified,
    switchToSection,
    isProgrammaticChange,
    setInitialActiveSection,
  } = useSystemSettings();



  // Editor configuration
  const lang = json();

  // Light theme configuration
const lightTheme = EditorView.theme({});

  // Computed extensions that include theme
  const extensions = computed(() => [
    basicSetup,
    isDarkMode.value ? oneDark : lightTheme,
  ]);

  // Computed property for the current section's content
  const currentSectionContent = computed({
    get: () => (activeSection.value ? sectionEditors.value[activeSection.value] || '' : ''),
    set: (val) => {
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

  onMounted(async () => {
    try {
      // Fetch config first, then initialize once with the real data
      await fetch();

      if (config.value) {
        initializeSectionEditors(config.value, configSections);
      } else {
        // Only initialize with empty if no config was returned
        initializeSectionEditors({} as SystemSettingsDetails, configSections);
      }

      // Set active section after initialization using the programmatic method
      setInitialActiveSection(configSections[0].key);
    } catch (error) {
      console.error('Error fetching config:', error);
      errorMessage.value = t('web.colonel.errorFetchingConfig');
    }
  });

  // Handle save actions
  const handleSaveSection = () => saveCurrentSection(configSections);

  // Handle section switching
  const handleSectionSwitch = (sectionKey: ConfigSectionKey) => {
    switchToSection(sectionKey);
  };
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header with navigation -->
    <ColonelNavigation />

    <!-- Main content -->
    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="space-y-6">
        <div
          v-if="isLoading"
          class="p-6 text-center">
            {{ t('web.LABELS.loading') }}
        </div>

        <div v-else>
          <div class="mb-6">
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ t('web.colonel.configEditorTitle') }}
            </h1>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.configEditorDescription') }}
            </p>
          </div>

          <!-- Config section tabs -->
          <div class="mb-6 border-b border-gray-200 dark:border-gray-700">
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
          <div v-if="activeSection" class="mb-4 text-sm">
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
          <div class="mb-6">
            <div
              class="min-h-[400px] max-h-[900px] overflow-auto rounded-md border"
              :class="[
                currentSectionHasError
                  ? 'border-red-500'
                  : activeSection && validationState[activeSection] === true
                    ? 'border-green-500'
                    : 'border-gray-300 dark:border-gray-600',
              ]">

              <CodeMirror
                v-model="currentSectionContent"
                :key="`codemirror-${activeSection}-${isDarkMode}`"
                :lang="lang"
                :extensions="extensions"
                basic
                :placeholder="`Enter configuration for ${activeSection}`"
                class="min-h-[400px] max-h-[900px]" />
            </div>
            <div
              v-if="activeSection && validationMessages[activeSection]"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ validationMessages[activeSection] }}
            </div>
          </div>

          <!-- Error and Success messages -->
          <div class="mb-6 space-y-3">
            <!-- Error message -->
            <div
              v-if="errorMessage"
              class="rounded-md border border-red-400 bg-red-100 p-3 text-red-700 dark:bg-red-900 dark:text-red-200">
              <div class="flex items-start justify-between">
                <div class="flex items-center">
                  <span class="mr-2">⚠️</span>
                  <span>{{ errorMessage }}</span>
                </div>
                <button
                  @click="errorMessage = null"
                  class="ml-3 text-sm text-red-700 hover:underline focus:outline-none dark:text-red-200">
                  {{ t('web.LABELS.dismiss') }}
                </button>
              </div>
            </div>

            <!-- Success message -->
            <div
              v-if="saveSuccess"
              class="rounded-md border border-green-400 bg-green-100 p-3 text-green-700 dark:bg-green-900 dark:text-green-200">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <span class="mr-2">✅</span>
                  <span>{{ t('web.colonel.configSaved') }}</span>
                </div>
                <button
                  @click="saveSuccess = false"
                  class="ml-3 text-sm text-green-700 hover:underline focus:outline-none dark:text-green-200">
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
              class="rounded-md bg-brand-600 px-4 py-2 text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:opacity-50"
              :disabled="isSaving">
              {{ isSaving ? t('web.LABELS.saving') : t('web.colonel.saveSection', { section: configSections.find(s => s.key === activeSection)?.label }) }}
            </button>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>
