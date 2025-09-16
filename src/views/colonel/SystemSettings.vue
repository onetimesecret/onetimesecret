<!-- src/views/colonel/SystemSettings.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useSystemSettings, type ConfigSectionKey } from '@/composables/useSystemSettings';
  import { useTheme } from '@/composables/useTheme';
  import { type SystemSettingsDetails } from '@/schemas/api/endpoints/colonel';
  import { useSystemSettingsStore } from '@/stores/systemSettingsStore';
  import { json } from '@codemirror/lang-json';
  import { oneDark } from '@codemirror/theme-one-dark';
  import { EditorView } from '@codemirror/view';
  import { basicSetup } from 'codemirror';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import CodeMirror from 'vue-codemirror6';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const { isDarkMode } = useTheme();

  // Config section tabs with typed keys
  const configSections = [
    { key: 'interface' as ConfigSectionKey, label: 'Interface' },
    { key: 'secret_options' as ConfigSectionKey, label: 'Secret Options' },
    { key: 'mail' as ConfigSectionKey, label: 'Email Validation' },
    { key: 'diagnostics' as ConfigSectionKey, label: 'Diagnostics' },
    { key: 'limits' as ConfigSectionKey, label: 'Limits' },
  ];

  const store = useSystemSettingsStore();
  const { details: config } = storeToRefs(store);
  const { fetch } = store;

  // Use the system settings composable
  const {
    activeSection,
    sectionEditors,
    validationState,
    validationMessages,
    errorMessage,
    saveSuccess,
    isLoading,
    sectionsWithErrors,
    currentSectionHasError,
    initializeSectionEditors,
    switchToSection,
    setInitialActiveSection,
  } = useSystemSettings();

  // Editor configuration
  const lang = json();

  // Light theme configuration
  const lightTheme = EditorView.theme({});

  // Computed extensions that include theme and read-only state
  const extensions = computed(() => [
    basicSetup,
    isDarkMode.value ? oneDark : lightTheme,
    EditorView.theme({
      '&.cm-editor.cm-focused': {
        outline: 'none',
      },
      '.cm-content': {
        caretColor: 'transparent',
      },
    }),
    EditorView.editable.of(false),
  ]);

  // Computed property for the current section's content (read-only)
  const currentSectionContent = computed({
    get: () => (activeSection.value ? sectionEditors.value[activeSection.value] || '' : ''),
    set: () => {
      // No-op for read-only mode
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

  // Handle section switching
  const handleSectionSwitch = (sectionKey: ConfigSectionKey) => {
    switchToSection(sectionKey);
  };
</script>

<template>
  <div class="">
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

        <!-- Read-only notice -->
        <div
          class="mt-4 rounded-md border border-blue-400 bg-blue-50 p-3 text-blue-700 dark:bg-blue-900 dark:text-blue-200">
          <div class="flex items-center">
            <span class="mr-2">🔒</span>
            <span class="text-sm font-medium">Read-Only Mode</span>
          </div>
          <p class="mt-1 text-sm">
            System settings are currently in read-only mode. You can view the configuration but
            cannot make changes.
          </p>
        </div>
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
              class="absolute -right-1 -top-1 size-2 rounded-full bg-red-500"
              :title="`${section.label} has validation errors`">
            </span>
          </button>
        </nav>
      </div>

      <!-- Section status indicator (read-only mode) -->
      <div
        v-if="activeSection"
        class="mb-4 text-sm">
        <span
          class="inline-flex items-center rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-700 dark:bg-gray-800 dark:text-gray-300">
          <span class="mr-1 h-1.5 w-1.5 rounded-full bg-gray-400"></span>
          Read-Only
        </span>
      </div>

      <!-- Editor for current section -->
      <div class="mb-6">
        <div
          class="max-h-[900px] min-h-[400px] overflow-auto rounded-md border bg-gray-50 dark:bg-gray-800"
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
            class="max-h-[900px] min-h-[400px]" />
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
              <OIcon
                collection="heroicons"
                name="x-mark" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
