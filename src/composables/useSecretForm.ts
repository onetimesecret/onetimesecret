// src/composables/useSecretForm.ts

import { transforms } from '@/schemas/transforms';
import { reactive } from 'vue';
import { WindowService } from '@/services/window.service';
import { z } from 'zod';

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
 * Form validation schema
 */
const formSchema = z.object({
  secret: z.string().min(1, 'Secret content is required'),
  ttl: z.number().min(1, 'Expiration time is required'),
  passphrase: z.string(),
  recipient: transforms.fromString.optionalEmail,
  share_domain: z.string(),
});

/**
 * Form data structure with defaults
 */
export type SecretFormData = z.infer<typeof formSchema>;

/**
 * Creates default form state
 */
function getDefaultFormState(): SecretFormData {
  // Get system configuration for default TTL
  const secretOptions = WindowService.get('secret_options');

  return {
    secret: '',
    ttl: secretOptions.default_ttl ?? 3600 * 24 * 7,
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
  const form = reactive<SecretFormData>(getDefaultFormState());
  const errors = reactive(new Map<keyof SecretFormData, string>());

  const operations = {
    updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => {
      form[field] = value;
    },
    reset: () => Object.assign(form, getDefaultFormState()),
  };

  return {
    form,
    validation: {
      errors,
      validate: () => {
        const result = formSchema.safeParse(form);
        errors.clear();
        if (!result.success) {
          result.error.errors.forEach((err) => {
            if (err.path[0]) {
              errors.set(err.path[0] as keyof SecretFormData, err.message);
            }
          });
        }

        // Additional passphrase validation based on configuration
        const secretOptions = WindowService.get('secret_options');
        const passphraseConfig = secretOptions?.passphrase;

        if (passphraseConfig) {
          // Check if passphrase is required
          if (passphraseConfig.required && !form.passphrase.trim()) {
            errors.set('passphrase', 'A passphrase is required for all secrets');
          }

          // Check minimum length if passphrase is provided
          if (form.passphrase && form.passphrase.length < (passphraseConfig.minimum_length || 8)) {
            errors.set('passphrase', `Passphrase must be at least ${passphraseConfig.minimum_length || 8} characters long`);
          }

          // Check maximum length if passphrase is provided
          if (form.passphrase && form.passphrase.length > (passphraseConfig.maximum_length || 128)) {
            errors.set('passphrase', `Passphrase must be no more than ${passphraseConfig.maximum_length || 128} characters long`);
          }

          // Check complexity if required and passphrase is provided
          if (form.passphrase && passphraseConfig.enforce_complexity) {
            const complexityErrors = [];
            if (!/[A-Z]/.test(form.passphrase)) complexityErrors.push('uppercase letter');
            if (!/[a-z]/.test(form.passphrase)) complexityErrors.push('lowercase letter');
            if (!/\d/.test(form.passphrase)) complexityErrors.push('number');
            if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`]/.test(form.passphrase)) complexityErrors.push('symbol');

            if (complexityErrors.length > 0) {
              errors.set('passphrase', `Passphrase must contain at least one ${complexityErrors.join(', ')}`);
            }
          }
        }

        return errors.size === 0;
      },
    },
    operations,
  };
}
