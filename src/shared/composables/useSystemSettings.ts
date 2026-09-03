// src/shared/composables/useSystemSettings.ts

import { systemSettingsSchema, type SystemSettingsDetails } from '@/schemas/contracts/config';
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// Use the keys of the systemSettingsSchema.shape as ConfigSectionKey
export type ConfigSectionKey = keyof typeof systemSettingsSchema.shape;

/* eslint-disable max-lines-per-function */
export function useSystemSettings() {
  const { t } = useI18n();

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
  const isLoading = ref<boolean>(false);
  const isProgrammaticChange = ref<boolean>(false); // <-- Add this flag

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

  return {
    // State
    activeSection,
    sectionEditors,
    validationState,
    validationMessages,
    isLoading,
    isProgrammaticChange, // <-- Expose the flag

    // Computed
    hasValidationErrors,
    sectionsWithErrors,
    currentSectionHasError,

    // Methods
    validateJson,
    initializeSectionEditors,
    validateCurrentSection,
    switchToSection,
    setInitialActiveSection,
  };
}
