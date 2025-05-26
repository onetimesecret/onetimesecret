// src/composables/useColonelConfig.ts
import { colonelConfigSchema, type ColonelConfigDetails } from '@/schemas/api/endpoints/colonel';
import { useNotificationsStore } from '@/stores';
import { useColonelConfigStore } from '@/stores/colonelConfigStore';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { z } from 'zod';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';

export type ConfigSectionKey = keyof ColonelConfigDetails;

/* eslint-disable max-lines-per-function */
export function useColonelConfig() {
  const { t } = useI18n();
  const store = useColonelConfigStore();
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

  // Track which sections have been modified
  const modifiedSections = ref<Set<ConfigSectionKey>>(new Set());

  // AsyncHandler setup
  const defaultOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSaving.value = loading),
    onError: (err) => {
      errorMessage.value = err.message || t('web.colonel.errorSavingConfig');
      console.error('Error in colonel config:', err);
    },
  };

  const { wrap } = useAsyncHandler(defaultOptions);

  // Validation logic
  const validateJson = (section: ConfigSectionKey, content: string) => {
    try {
      // Handle empty content
      if (!content || content.trim() === '') {
        content = '{}';
        sectionEditors.value[section] = content;
      }

      const parsed = JSON.parse(content);

      // Allow null/undefined for optional sections
      if (parsed === null || parsed === undefined) {
        validationState.value[section] = true;
        validationMessages.value[section] = null;
        return;
      }

      // Require objects (not arrays or primitives) for config sections
      if (typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error(t('web.colonel.mustBeObject'));
      }

      // Additional section-specific validation could be added here
      // For now, any valid JSON object is accepted

      validationState.value[section] = true;
      validationMessages.value[section] = null;
    } catch (error) {
      validationState.value[section] = false;
      if (error instanceof SyntaxError) {
        // JSON parsing error
        validationMessages.value[section] = t('web.colonel.invalidJson', { section });
      } else if (error instanceof Error) {
        validationMessages.value[section] = error.message;
      } else {
        validationMessages.value[section] = t('web.colonel.invalidJson', { section });
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
    activeSection.value ? sectionsWithErrors.value.includes(activeSection.value) : false);

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
    configData: ColonelConfigDetails | null,
    configSections: Array<{ key: ConfigSectionKey }>
  ) => {
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
    // Clear modified sections on initialization
    modifiedSections.value.clear();
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

    // Switch to new section
    activeSection.value = newSection;

    // Clear success message when switching sections
    saveSuccess.value = false;
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

      // Create minimal config with only valid sections to avoid validation errors
      const currentConfig = store.details || ({} as ColonelConfigDetails);

      // Build config with only the current section and other valid sections
      const updatedConfig: Partial<ColonelConfigDetails> = {};

      // Add all currently valid sections from editors
      for (const section of configSections) {
        if (validationState.value[section.key] === true) {
          updatedConfig[section.key] = JSON.parse(sectionEditors.value[section.key] || '{}');
        } else if (section.key !== currentSection) {
          // For invalid sections (except current), use original data if available
          if (currentConfig[section.key]) {
            updatedConfig[section.key] = currentConfig[section.key];
          }
        }
      }

      // Always include the current section we're saving
      updatedConfig[currentSection] = JSON.parse(sectionEditors.value[currentSection]);

      try {
        await store.update(updatedConfig as ColonelConfigDetails);
        await store.fetch();

        // Remove from modified sections
        modifiedSections.value.delete(currentSection);

        saveSuccess.value = true;
        notifications.show(t('web.colonel.sectionSaved', { section: sectionLabel }), 'success');
      } catch (error) {
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
      const combinedConfig: Partial<ColonelConfigDetails> = {};

      for (const section of configSections) {
        const sectionContent = sectionEditors.value[section.key];
        if (sectionContent) {
          combinedConfig[section.key] = JSON.parse(sectionContent);
        }
      }

      // Validate the combined config against the schema
      try {
        colonelConfigSchema.parse(combinedConfig);
      } catch (validationError) {
        if (validationError instanceof z.ZodError) {
          const firstError = validationError.errors[0];
          const errorPath = firstError.path.length > 0 ? firstError.path.join('.') : 'root';
          errorMessage.value = `${t('web.colonel.validationError')}: ${errorPath} - ${firstError.message}`;
          return;
        }
        throw validationError;
      }

      // Update config and refetch
      await store.update(combinedConfig as ColonelConfigDetails);
      await store.fetch();

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
  };
}
