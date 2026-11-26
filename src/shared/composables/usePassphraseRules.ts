// src/shared/composables/usePassphraseRules.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useSharingControls } from './useSharingControls';

/** The passphrase rules the server publishes (secret_options.passphrase). */
export interface PassphraseRulesConfig {
  minimum_length?: number | null;
  maximum_length?: number | null;
  enforce_complexity?: boolean | null;
}

export type PassphraseCharacterClass = 'uppercase' | 'lowercase' | 'number' | 'symbol';

export type PassphraseIssue =
  | { code: 'required' }
  | { code: 'too_short'; length: number }
  | { code: 'too_long'; length: number }
  | { code: 'complexity'; missing: PassphraseCharacterClass[] };

const CHARACTER_CLASSES: ReadonlyArray<[PassphraseCharacterClass, RegExp]> = [
  ['uppercase', /[A-Z]/],
  ['lowercase', /[a-z]/],
  ['number', /\d/],
  ['symbol', /[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`]/],
];

/**
 * Every passphrase rule the value breaks, in rule order: required, minimum
 * length, maximum length, complexity. The single definition of the client's
 * passphrase rules, used by the secret form's submit validation and by the
 * dashboard passphrase chip and mobile sheet.
 *
 * - A required passphrase that is empty or only whitespace breaks `required`
 *   and nothing else is checked.
 * - An empty optional passphrase breaks nothing.
 */
export function passphraseIssues(
  value: string,
  rules: { required: boolean; config?: PassphraseRulesConfig | null }
): PassphraseIssue[] {
  if (rules.required && !value.trim()) return [{ code: 'required' }];

  const config = rules.config;
  if (!config || !value) return [];

  const issues: PassphraseIssue[] = [];
  if (config.minimum_length && value.length < config.minimum_length) {
    issues.push({ code: 'too_short', length: config.minimum_length });
  }
  if (config.maximum_length && value.length > config.maximum_length) {
    issues.push({ code: 'too_long', length: config.maximum_length });
  }
  if (config.enforce_complexity) {
    const missing = CHARACTER_CLASSES.filter(([, pattern]) => !pattern.test(value)).map(
      ([name]) => name
    );
    if (missing.length > 0) issues.push({ code: 'complexity', missing });
  }
  return issues;
}

/**
 * The one issue shown for a value: the last rule it breaks. This is the
 * order the secret form has always reported in (a later rule's message
 * replaced an earlier one), kept so the chip and the form's banner agree.
 */
export function reportedPassphraseIssue(
  value: string,
  rules: { required: boolean; config?: PassphraseRulesConfig | null }
): PassphraseIssue | null {
  const issues = passphraseIssues(value, rules);
  return issues.length > 0 ? issues[issues.length - 1] : null;
}

/**
 * usePassphraseRules - inline passphrase validation for a single field
 *
 * For the dashboard's passphrase chip and mobile privacy sheet: the same
 * rules the form enforces on submit, the hint texts, and the error text for
 * the current value. A required passphrase left empty is an error only after
 * the user has interacted with the field (markInteracted).
 *
 * @param value - the current passphrase
 * @param minimumLength - overrides the configured minimum when above zero
 */
export function usePassphraseRules(value: () => string, minimumLength?: () => number) {
  const { t } = useI18n();
  const { secret_options } = storeToRefs(useBootstrapStore());
  const { passphraseRequired } = useSharingControls();

  const config = computed<PassphraseRulesConfig>(() => {
    const published = secret_options.value?.passphrase ?? {};
    const override = minimumLength?.() ?? 0;
    return override > 0 ? { ...published, minimum_length: override } : published;
  });

  const minLength = computed(() => config.value.minimum_length || 0);
  const complexityEnforced = computed(() => !!config.value.enforce_complexity);

  const interacted = ref(false);
  const markInteracted = () => {
    interacted.value = true;
  };

  const issue = computed<PassphraseIssue | null>(() => {
    const found = reportedPassphraseIssue(value(), {
      required: passphraseRequired.value,
      config: config.value,
    });
    if (found?.code === 'required' && !interacted.value) return null;
    return found;
  });

  // The shared hint says "(Optional)", which is wrong once a sharing control
  // or the instance requires a passphrase.
  const minimumLengthHint = computed(() =>
    minLength.value > 0
      ? t(
          passphraseRequired.value
            ? 'web.secrets.passphraseMinimumLengthRequired'
            : 'web.secrets.passphraseMinimumLength',
          { length: minLength.value }
        )
      : ''
  );

  const complexityHint = computed(() =>
    complexityEnforced.value ? t('web.secrets.passphraseComplexityRequired') : ''
  );

  const errorText = computed(() => {
    const found = issue.value;
    if (!found) return '';
    switch (found.code) {
      case 'required':
        return t('web.secrets.passphraseRequired');
      case 'too_short':
        return minimumLengthHint.value;
      case 'too_long':
        return t('web.secrets.passphraseMaximumLength', { length: found.length });
      case 'complexity':
        return t('web.secrets.passphraseComplexityRequired');
      default:
        return '';
    }
  });

  return {
    passphraseRequired,
    minLength,
    complexityEnforced,
    issue,
    errorText,
    minimumLengthHint,
    complexityHint,
    markInteracted,
  };
}
