// src/composables/useSecretForm.ts

import { transforms } from '@/schemas/transforms';
import { computed, reactive, ref } from 'vue';
import { z } from 'zod';

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
  return {
    secret: '',
    ttl: 3600 * 24 * 7,
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

  const hasContent = computed(() => form.secret.length > 0);

  const updateContent = (content: string) => {
    form.secret = content;
  };

  const validationErrors = ref<z.ZodError | null>(null);
  const validate = () => {
    try {
      const result = formSchema.parse(form);
      validationErrors.value = null;
      return result;
    } catch (error) {
      if (error instanceof z.ZodError) {
        validationErrors.value = error;
      }
      throw error;
    }
  };

  // Add field-level validation
  const getFieldError = (field: keyof SecretFormData) =>
    validationErrors.value?.errors.find((error) => error.path[0] === field)
      ?.message;

  const updateField = <K extends keyof SecretFormData>(
    field: K,
    value: SecretFormData[K]
  ) => {
    form[field] = value;
  };

  const handleFieldChange = {
    ttl: (e: Event) => {
      const value = (e.target as HTMLSelectElement).value;
      updateField('ttl', Number(value));
    },
    passphrase: (e: Event) => {
      const value = (e.target as HTMLInputElement).value;
      updateField('passphrase', value);
    },
    recipient: (e: Event) => {
      const value = (e.target as HTMLInputElement).value;
      updateField('recipient', value);
    },
  };

  const reset = () => {
    Object.assign(form, getDefaultFormState());
  };

  return {
    form,
    hasContent,
    updateContent,
    validate,
    handleFieldChange,
    getFieldError,
    updateField,
    reset,
  };
}
