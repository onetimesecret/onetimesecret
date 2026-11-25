// src/shared/composables/useSecretForm.ts

import {
  DEFAULT_SECRET_DISPLAY_TYPE,
  secretDisplayTypeSchema,
} from '@/schemas/contracts/secret';
import { useSharingControls } from './useSharingControls';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { reactive, watch } from 'vue';
import { z } from 'zod';

export interface SecretFormState {
  form: SecretFormData;
  validation: {
    errors: Map<keyof SecretFormData, string>;
    validate: () => boolean;
    validateGenerate: () => boolean;
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
  ttl: z.number().min(60, 'Expiration time is required'),
  passphrase: z.string(),
  recipient: z.string(),
  share_domain: z.string(),
  team_id: z.string().optional(),
  display_type: secretDisplayTypeSchema,
});

/**
 * Form data structure with defaults
 */
const generateSchema = formSchema.omit({ secret: true });

export type SecretFormData = z.infer<typeof formSchema>;

/** The HTML multiple-email input uses a comma-separated value. */
export function recipientList(value: string) {
  return value.trim() ? [...new Set(value.split(',').map(email => email.trim()))] : [];
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
export function useSecretForm(shareDomain?: () => string) {
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);

  const controls = useSharingControls(shareDomain);

  /**
   * Creates default form state
   */
  function getDefaultFormState(): SecretFormData {
    return {
      secret: '',
      ttl: controls.defaultTtl.value,
      passphrase: '',
      recipient: '',
      share_domain: '',
      display_type: DEFAULT_SECRET_DISPLAY_TYPE,
    };
  }

  const form = reactive<SecretFormData>(getDefaultFormState());
  const errors = reactive(new Map<keyof SecretFormData, string>());

  const operations = {
    updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => {
      form[field] = value;
      if (field === 'ttl') form.ttl = controls.clampTtl(form.ttl);
    },
    reset: () => Object.assign(form, getDefaultFormState(), { share_domain: form.share_domain }),
  };

  watch(controls.ttlCeiling, () => { form.ttl = controls.clampTtl(form.ttl); }, { flush: 'sync' });
  watch(controls.recipientEnabled, enabled => { if (!enabled) form.recipient = ''; }, { flush: 'sync' });

  function validateRecipients() {
    const recipients = recipientList(form.recipient);
    const allowedDomains = controls.recipientDomains.value;
    if (recipients.length > 10) {
      errors.set('recipient', 'At most 10 recipients are allowed');
    } else if (recipients.some(email => !z.email().safeParse(email).success)) {
      errors.set('recipient', 'Invalid recipient email');
    } else if (recipients.some(email => {
      const domain = email.slice(email.lastIndexOf('@') + 1).toLowerCase();
      return !controls.recipientEnabled.value ||
        (allowedDomains && !allowedDomains.includes(domain));
    })) {
      errors.set('recipient', 'Recipient email is restricted by the organization');
    }
  }

  function validatePassphrase() {
    const value = form.passphrase;
    if (controls.passphraseRequired.value && !value.trim()) {
      errors.set('passphrase', 'A passphrase is required for all secrets');
      return;
    }
    const config = secret_options.value?.passphrase;
    if (!config || !value) return;
    if (config.minimum_length && value.length < config.minimum_length) {
      errors.set('passphrase',
        `Passphrase must be at least ${config.minimum_length} characters long`);
    }
    if (config.maximum_length && value.length > config.maximum_length) {
      errors.set('passphrase',
        `Passphrase must be no more than ${config.maximum_length} characters long`);
    }
    if (config.enforce_complexity) validatePassphraseComplexity(value);
  }

  function validatePassphraseComplexity(passphrase: string) {
    const complexityErrors = [];
    if (!/[A-Z]/.test(passphrase)) complexityErrors.push('uppercase letter');
    if (!/[a-z]/.test(passphrase)) complexityErrors.push('lowercase letter');
    if (!/\d/.test(passphrase)) complexityErrors.push('number');
    if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`]/.test(passphrase))
      complexityErrors.push('symbol');

    if (complexityErrors.length > 0) {
      errors.set(
        'passphrase',
        `Passphrase must contain at least one ${complexityErrors.join(', ')}`
      );
    }
  }

  function validate(generate = false) {
    errors.clear();
    const result = (generate ? generateSchema : formSchema).safeParse(form);
    if (!result.success) {
      for (const issue of result.error.issues) {
        errors.set(issue.path[0] as keyof SecretFormData, issue.message);
      }
    }
    if (controls.ttlCeiling.value !== null && controls.ttlCeiling.value < 60) {
      errors.set('ttl', 'Maximum secret lifetime is below 60 seconds');
    }
    validateRecipients();
    validatePassphrase();

    return errors.size === 0;
  }

  return {
    form,
    validation: { errors, validate, validateGenerate: () => validate(true) },
    operations,
  };
}
