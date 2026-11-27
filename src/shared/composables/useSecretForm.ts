// src/shared/composables/useSecretForm.ts

import {
  DEFAULT_SECRET_DISPLAY_TYPE,
  secretDisplayTypeSchema,
} from '@/schemas/contracts/secret';
import { transforms } from '@/schemas/transforms';
import { passphraseIssueMessage, reportedPassphraseIssue } from './usePassphraseRules';
import { useSharingControls } from './useSharingControls';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
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
  recipient: transforms.fromString.optionalEmail,
  share_domain: z.string(),
  team_id: z.string().optional(),
  display_type: secretDisplayTypeSchema,
});

/**
 * Form data structure with defaults
 */
const generateSchema = formSchema.omit({ secret: true });

export type SecretFormData = z.infer<typeof formSchema>;

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
  const { t } = useI18n();
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

  function validateRecipientPolicy() {
    if (!form.recipient || errors.has('recipient')) return;
    const allowedDomains = controls.recipientDomains.value;
    const domain = form.recipient.slice(form.recipient.lastIndexOf('@') + 1).toLowerCase();
    if (!controls.recipientEnabled.value || (allowedDomains && !allowedDomains.includes(domain))) {
      errors.set('recipient', t('web.secrets.error_recipient_restricted'));
    }
  }

  // The rules and their messages are shared with the dashboard passphrase
  // chip and mobile sheet (usePassphraseRules).
  function validatePassphrase() {
    const issue = reportedPassphraseIssue(form.passphrase, {
      required: controls.passphraseRequired.value,
      config: secret_options.value?.passphrase,
    });
    if (issue) errors.set('passphrase', passphraseIssueMessage(issue, t));
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
      errors.set('ttl', t('web.secrets.error_ttl_below_minimum'));
    }
    validateRecipientPolicy();
    validatePassphrase();

    return errors.size === 0;
  }

  return {
    form,
    validation: { errors, validate, validateGenerate: () => validate(true) },
    operations,
  };
}
