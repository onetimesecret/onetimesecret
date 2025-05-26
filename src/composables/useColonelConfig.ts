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
      if (content.trim() === '') {
        content = '{}';
        sectionEditors.value[section] = content;
      }

      const parsed = JSON.parse(content);

      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error(t('web.colonel.mustBeObject'));
      }

      validationState.value[section] = true;
      validationMessages.value[section] = null;
    } catch (error) {
      validationState.value[section] = false;
      if (error instanceof Error) {
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
  };

  // Save configuration
  const saveConfig = async (configSections: Array<{ key: ConfigSectionKey; label: string }>) =>
    wrap(async () => {
      errorMessage.value = null;
      saveSuccess.value = false;

      // Validate all sections first
      for (const section of configSections) {
        validateJson(section.key, sectionEditors.value[section.key] || '{}');
        if (validationState.value[section.key] === false) {
          activeSection.value = section.key; // Switch to invalid section
          errorMessage.value = t('web.colonel.invalidJson', { section: section.label });
          console.error(
            `Invalid JSON in section ${section.key}:`,
            validationMessages.value[section.key]
          );
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

      // Validate the combined config against the schema
      try {
        colonelConfigSchema.parse(combinedConfig);
      } catch (validationError) {
        if (validationError instanceof z.ZodError) {
          const firstError = validationError.errors[0];
          const errorPath = firstError.path.length > 0 ? firstError.path.join('.') : 'root';
          errorMessage.value = `${t('web.colonel.validationError')}: ${errorPath} - ${firstError.message}`;

          // Set active section to the one with the error if possible
          const errorSection = firstError.path[0];
          if (errorSection && typeof errorSection === 'string') {
            const matchingSection = configSections.find(
              (s) => s.key === (errorSection as ConfigSectionKey)
            );
            // Set active section to matching section if found
            const shouldSetActiveSection = !!matchingSection;
            shouldSetActiveSection && (activeSection.value = matchingSection.key);
          }

          return;
        }
        throw validationError;
      }

      // Update config and refetch
      await store.update(combinedConfig as ColonelConfigDetails);
      await store.fetch();
      saveSuccess.value = true;

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

    // Computed
    hasValidationErrors,

    // Methods
    validateJson,
    initializeSectionEditors,
    saveConfig,
  };
}
