// src/composables/useSecretForm.ts

import { transforms } from '@/schemas/transforms';
import { reactive } from 'vue';
import { WindowService } from '@/services/window.service';
import { z } from 'zod/v4';
import { useI18n } from 'vue-i18n';

export interface SecretFormState {
  form: SecretFormData;
  validation: {
    errors: Map<keyof SecretFormData, string>;
    validate: () => boolean;
  };
  operations: {
    updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => void;
    reset: () => void;
  };
}

/**
 * Form data structure with defaults
 */
export type SecretFormData = {
  secret: string;
  ttl: number;
  passphrase: string;
  recipient: string;
  share_domain: string;
};

/**
 * Creates default form state
 */
function getDefaultFormState(): SecretFormData {
  // Get system configuration for default TTL
  const secretOptions = WindowService.get('secret_options');

  // Handle different secret_options structures and missing data
  let defaultTtl = 3600 * 24 * 7; // Default to 7 days

  if (secretOptions) {
    // Try direct access first (old structure)
    if (secretOptions.default_ttl) {
      defaultTtl = secretOptions.default_ttl;
    }
    // Try nested structure (new structure)
    else if (secretOptions.anonymous?.default_ttl) {
      defaultTtl = secretOptions.anonymous.default_ttl;
    }
    else if (secretOptions.standard?.default_ttl) {
      defaultTtl = secretOptions.standard.default_ttl;
    }
    else if (secretOptions.enhanced?.default_ttl) {
      defaultTtl = secretOptions.enhanced.default_ttl;
    }
  }

  return {
    secret: '',
    ttl: defaultTtl,
    passphrase: '',
    recipient: '',
    share_domain: '',
  };
}

/**
 * useSecretForm - secret form state and validation
 *
 * Central source of truth for form state. Manages form data validation,
 * updates, and schema enforcement. Provides type-safe interface for form
 * operations while maintaining a predictable state shape.
 *
 * Responsibilities:
 * - Form state management
 * - Schema validation
 * - Type safety
 * - Field updates
 * - Form reset
 */
/* eslint-disable max-lines-per-function */
export function useSecretForm() {
  const { t } = useI18n();
  const form = reactive<SecretFormData>(getDefaultFormState());
  const errors = reactive(new Map<keyof SecretFormData, string>());

  /**
   * Creates form validation schema with i18n messages
   */
  const createFormSchema = () => z.object({
    secret: z.string().min(1, t('web.COMMON.form_validation.secret_required')),
    ttl: z.number().min(1, t('web.COMMON.form_validation.ttl_required')),
    passphrase: z.string(),
    recipient: transforms.fromString.optionalEmail,
    share_domain: z.string(),
  });

  const operations = {
    updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => {
      form[field] = value;
      // Clear field error when user starts fixing it
      if (errors.has(field)) {
        errors.delete(field);
      }
    },
    reset: () => Object.assign(form, getDefaultFormState()),
  };

  const validateWithUserFriendlyMessages = () => {
    const formSchema = createFormSchema();
    const result = formSchema.safeParse(form);
    errors.clear();

    if (!result.success) {
      result.error.issues.forEach((issue) => {
        if (issue.path[0]) {
          const field = issue.path[0] as keyof SecretFormData;
          const userFriendlyMessage = getUserFriendlyErrorMessage(field, issue);
          errors.set(field, userFriendlyMessage);
        }
      });
    }
    return result.success;
  };

  const getUserFriendlyErrorMessage = (field: keyof SecretFormData, issue: any): string => {
    // Use i18n keys for field-specific messages
    switch (field) {
      case 'secret':
        if (issue.code === 'too_small') {
          return t('web.COMMON.form_validation.secret_required');
        }
        break;
      case 'ttl':
        return t('web.COMMON.form_validation.ttl_required');
      case 'share_domain':
        if (issue.code === 'invalid_type') {
          return t('web.COMMON.form_validation.share_domain_invalid');
        }
        break;
      case 'passphrase':
        if (issue.code === 'too_small') {
          return t('web.COMMON.form_validation.passphrase_too_short');
        }
        break;
      case 'recipient':
        if (issue.code === 'invalid_string') {
          return t('web.COMMON.form_validation.recipient_invalid');
        }
        break;
    }

    // Fallback to the original message or a generic one
    return issue.message || t('web.COMMON.unexpected_error');
  };

  return {
    form,
    validation: {
      errors,
      validate: validateWithUserFriendlyMessages,
    },
    operations,
  };
}
