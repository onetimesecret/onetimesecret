// src/composables/useSystemSettings.ts

import { systemSettingsSchema, type SystemSettingsDetails } from '@/schemas/api/account/endpoints/colonel';
import { useNotificationsStore } from '@/stores';
import { useSystemSettingsStore } from '@/stores/systemSettingsStore';
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { z } from 'zod';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';

// Use the keys of the systemSettingsSchema.shape as ConfigSectionKey
export type ConfigSectionKey = keyof typeof systemSettingsSchema.shape;

/* eslint-disable max-lines-per-function */
export function useSystemSettings() {
  const { t } = useI18n();
  const store = useSystemSettingsStore();
  const notifications = useNotificationsStore();

  // State
  const activeSection = ref<ConfigSectionKey | null>(null);
  const sectionEditors = ref<Record<ConfigSectionKey, string>>(
    {} as Record<ConfigSectionKey, string>
  );
  const validationState = ref<Record<ConfigSectionKey, boolean>>(
    {} as Record<ConfigSectionKey, boolean>
  );
  const validationMessages = ref<Record<ConfigSectionKey, string | null>>(
    {} as Record<ConfigSectionKey, string | null>
  );
  const errorMessage = ref<string | null>(null);
  const saveSuccess = ref<boolean>(false);
  const isLoading = ref<boolean>(false);
  const isSaving = ref<boolean>(false);
  const isProgrammaticChange = ref<boolean>(false); // <-- Add this flag

  // Track which sections have been modified
  const modifiedSections = ref<Set<ConfigSectionKey>>(new Set());

  // AsyncHandler setup
  const defaultOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSaving.value = loading),
    onError: (err) => {
      errorMessage.value = err.message || t('web.colonel.errorSavingConfig');
      console.error('Error in system settings:', err);
    },
  };

  const { wrap } = useAsyncHandler(defaultOptions);

  // Validation logic
  const validateJson = (section: ConfigSectionKey, content: string) => {
    try {
      let parsedJsonForZod;
      if (!content || content.trim() === '') {
        parsedJsonForZod = {};
      } else {
        parsedJsonForZod = JSON.parse(content);
      }

      const sectionSchema = systemSettingsSchema.shape[section];
      const validationResult = sectionSchema.safeParse(parsedJsonForZod);

      if (validationResult.success) {
        const zodData = validationResult.data;
        if (
          typeof zodData === 'object' &&
          zodData !== null &&
          Object.keys(zodData).length === 0 &&
          content.trim() !== '{}'
        ) {
          validationState.value[section] = false;
          validationMessages.value[section] = t('web.colonel.sectionEffectivelyEmpty', { section });
        } else {
          validationState.value[section] = true;
          validationMessages.value[section] = null;
        }
      } else {
        validationState.value[section] = false;
        const firstError = validationResult.error.issues[0];
        const path = firstError.path.join('.') || 'section root';
        validationMessages.value[section] = t('web.colonel.schemaValidationError', {
          section,
          path,
          message: firstError.message,
        });
      }
    } catch (error) {
      validationState.value[section] = false;
      if (error instanceof SyntaxError) {
        validationMessages.value[section] = error.message;
      } else {
        console.error(`Unexpected error validating section ${section}:`, error);
        validationMessages.value[section] = t('web.colonel.unknownValidationError', { section });
      }
    }
  };

  // Check for validation errors
  const hasValidationErrors = computed(() => {
    const validationStateValue = validationState.value;
    if (!validationStateValue || typeof validationStateValue !== 'object') {
      return false;
    }
    return Object.values(validationStateValue).some((state) => state === false);
  });

  // Check which sections have validation errors
  const sectionsWithErrors = computed(() => {
    const validationStateValue = validationState.value;
    if (!validationStateValue || typeof validationStateValue !== 'object') {
      return [];
    }
    return Object.entries(validationStateValue)
      .filter(([, state]) => state === false)
      .map(([key]) => key as ConfigSectionKey);
  });

  // Check if current section has validation error
  const currentSectionHasError = computed(() =>
    activeSection.value ? sectionsWithErrors.value.includes(activeSection.value) : false
  );

  // Get sections that can be saved (valid and modified)
  const saveableSections = computed(() =>
    Array.from(modifiedSections.value).filter((section) => validationState.value[section] === true)
  );

  // Check if current section can be saved
  const currentSectionCanSave = computed(
    () =>
      activeSection.value &&
      modifiedSections.value.has(activeSection.value) &&
      validationState.value[activeSection.value] === true
  );

  // Initialize section editors
  const initializeSectionEditors = (
    configData: SystemSettingsDetails | null,
    configSections: Array<{ key: ConfigSectionKey }>
  ) => {
    isProgrammaticChange.value = true; // <-- Set flag before programmatic changes
    try {
      configSections.forEach((section) => {
        try {
          const sectionData = configData && configData[section.key] ? configData[section.key] : {};
          const content = JSON.stringify(sectionData, null, 2);
          sectionEditors.value[section.key] = content;
          validateJson(section.key, content);
        } catch (error) {
          console.error(`Error initializing section ${section.key}:`, error);
          sectionEditors.value[section.key] = '{}';
          validateJson(section.key, '{}');
        }
      });
    } finally {
      isProgrammaticChange.value = false; // <-- Reset flag after programmatic changes
    }
  };

  // Mark section as modified
  const markSectionModified = (section: ConfigSectionKey) => {
    modifiedSections.value.add(section);
  };

  // Validate section when switching away from it
  const validateCurrentSection = () => {
    if (activeSection.value) {
      validateJson(activeSection.value, sectionEditors.value[activeSection.value] || '{}');
    }
  };

  // Switch to section with validation
  const switchToSection = (newSection: ConfigSectionKey) => {
    // Validate current section before switching
    validateCurrentSection();

    // Set flag to indicate this is a programmatic change
    isProgrammaticChange.value = true;

    try {
      // Switch to new section
      activeSection.value = newSection;
    } finally {
      // Always reset the flag
      nextTick(() => {
        isProgrammaticChange.value = false;
      });
    }

    // Clear success message when switching sections
    saveSuccess.value = false;
  };

  // Set initial active section with programmatic flag
  const setInitialActiveSection = (section: ConfigSectionKey) => {
    // Set flag to indicate this is a programmatic change
    isProgrammaticChange.value = true;

    try {
      // Set initial section
      activeSection.value = section;
    } finally {
      // Always reset the flag
      nextTick(() => {
        isProgrammaticChange.value = false;
      });
    }
  };

  // Save only the current section
  const saveCurrentSection = async (
    configSections: Array<{ key: ConfigSectionKey; label: string }>
  ) =>
    wrap(async () => {
      if (!activeSection.value) return;

      errorMessage.value = null;
      saveSuccess.value = false;

      const currentSection = activeSection.value;
      const sectionLabel =
        configSections.find((s) => s.key === currentSection)?.label || currentSection;

      // Validate current section
      validateJson(currentSection, sectionEditors.value[currentSection] || '{}');

      if (validationState.value[currentSection] === false) {
        errorMessage.value = t('web.colonel.invalidJson', { section: sectionLabel });
        return;
      }

      // Create a payload with only the current section's data
      const payload: Partial<SystemSettingsDetails> = {};
      payload[currentSection] = JSON.parse(sectionEditors.value[currentSection]);

      try {
        // Send only the current section for update
        await store.update(payload as SystemSettingsDetails);

        // Remove from modified sections
        modifiedSections.value.delete(currentSection);

        saveSuccess.value = true;
        notifications.show(t('web.colonel.sectionSaved', { section: sectionLabel }), 'success');
      } catch (error) {
        // The wrap function will handle notifications.show for errors
        throw error;
      }

      return true;
    });

  // Save all sections (improved UX)
  const saveConfig = async (configSections: Array<{ key: ConfigSectionKey; label: string }>) =>
    wrap(async () => {
      errorMessage.value = null;
      saveSuccess.value = false;

      // Remember current section to return to it
      const originalSection = activeSection.value;

      // Validate all sections first without switching
      const invalidSections: { key: ConfigSectionKey; label: string; error: string }[] = [];

      for (const section of configSections) {
        validateJson(section.key, sectionEditors.value[section.key] || '{}');
        if (validationState.value[section.key] === false) {
          invalidSections.push({
            key: section.key,
            label: section.label,
            error: validationMessages.value[section.key] || 'Invalid JSON',
          });
        }
      }

      // If there are validation errors, show them without switching sections
      if (invalidSections.length > 0) {
        if (invalidSections.length === 1) {
          const invalid = invalidSections[0];
          errorMessage.value = t('web.colonel.sectionHasError', {
            section: invalid.label,
            error: invalid.error,
          });
        } else {
          const sectionNames = invalidSections.map((s) => s.label).join(', ');
          errorMessage.value = t('web.colonel.multipleSectionsInvalid', {
            sections: sectionNames,
            count: invalidSections.length,
          });
        }

        // Don't switch sections - let user decide where to go
        return;
      }

      // Combine all section editors into a single config object
      const combinedConfig: Partial<SystemSettingsDetails> = {};

      for (const section of configSections) {
        const sectionContent = sectionEditors.value[section.key];
        if (sectionContent) {
          combinedConfig[section.key] = JSON.parse(sectionContent);
        }
      }

      // Validate the combined config against the schema
      try {
        systemSettingsSchema.parse(combinedConfig);
      } catch (validationError) {
        if (validationError instanceof z.ZodError) {
          const firstError = validationError.issues[0];
          const errorPath =
            firstError.path.length > 0 ? validationError.issues[0].path.join('.') : 'root';
          errorMessage.value = `${t('web.colonel.validationError')}: ${errorPath} - ${firstError.message}`;
          return;
        }
        throw validationError;
      }

      // Update config and refetch
      await store.update(combinedConfig as SystemSettingsDetails);
      // await store.fetch();

      // Clear all modified sections
      modifiedSections.value.clear();

      saveSuccess.value = true;

      // Return to original section
      activeSection.value = originalSection;

      return true;
    });

  return {
    // State
    activeSection,
    sectionEditors,
    validationState,
    validationMessages,
    errorMessage,
    saveSuccess,
    isLoading,
    isSaving,
    modifiedSections,
    isProgrammaticChange, // <-- Expose the flag

    // Computed
    hasValidationErrors,
    sectionsWithErrors,
    currentSectionHasError,
    saveableSections,
    currentSectionCanSave,

    // Methods
    validateJson,
    initializeSectionEditors,
    saveConfig,
    saveCurrentSection,
    markSectionModified,
    validateCurrentSection,
    switchToSection,
    setInitialActiveSection,
  };
}
