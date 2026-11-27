// src/shared/composables/usePassphraseRules.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed, ref, watch } from 'vue';
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
 * The one issue shown for a value: the first rule it breaks, in rule order
 * (required, minimum length, maximum length, complexity). The secret form's
 * banner and the chip both report this one, so they agree.
 */
export function reportedPassphraseIssue(
  value: string,
  rules: { required: boolean; config?: PassphraseRulesConfig | null }
): PassphraseIssue | null {
  return passphraseIssues(value, rules)[0] ?? null;
}

const CHARACTER_CLASS_KEYS: Record<PassphraseCharacterClass, string> = {
  uppercase: 'web.secrets.passphrase_class_uppercase',
  lowercase: 'web.secrets.passphrase_class_lowercase',
  number: 'web.secrets.passphrase_class_number',
  symbol: 'web.secrets.passphrase_class_symbol',
};

type Translate = (key: string, named?: Record<string, unknown>) => string;

/**
 * The error message for an issue, naming the rule it breaks. Shared by the
 * secret form's submit validation and the chip and sheet, so one passphrase
 * gets one message wherever it is shown. None of these messages say
 * "(Optional)": a passphrase that was entered has to meet the rules whether
 * or not one was required.
 */
export function passphraseIssueMessage(issue: PassphraseIssue, t: Translate): string {
  switch (issue.code) {
    case 'required':
      return t('web.secrets.error_passphrase_required');
    case 'too_short':
      return t('web.secrets.error_passphrase_too_short', { length: issue.length });
    case 'too_long':
      return t('web.secrets.error_passphrase_too_long', { length: issue.length });
    case 'complexity':
      return t('web.secrets.error_passphrase_complexity', {
        missing: issue.missing.map((name) => t(CHARACTER_CLASS_KEYS[name])).join(', '),
      });
  }
}

/**
 * usePassphraseRules - inline passphrase validation for a single field
 *
 * For the dashboard's passphrase chip and mobile privacy sheet: the same
 * rules the form enforces on submit, the hint texts, and the error text for
 * the current value. A required passphrase left empty is an error only after
 * the user has interacted with the field (markInteracted).
 *
 * The rules are read only from the bootstrap config, the same source submit
 * validation reads, so the chip cannot accept what submit refuses.
 *
 * @param value - the current passphrase
 */
export function usePassphraseRules(value: () => string) {
  const { t } = useI18n();
  const { secret_options } = storeToRefs(useBootstrapStore());
  const { passphraseRequired } = useSharingControls();

  const config = computed<PassphraseRulesConfig>(() => secret_options.value?.passphrase ?? {});

  const minLength = computed(() => config.value.minimum_length || 0);
  const complexityEnforced = computed(() => !!config.value.enforce_complexity);

  // `next` is the value the caller is about to emit for a user edit. A change
  // to '' that the user did not make (the form resetting after a submit)
  // clears the flag, so a fresh, empty form is not flagged as required.
  const interacted = ref(false);
  let expectedUserValue: string | undefined;
  const markInteracted = (next?: string) => {
    interacted.value = true;
    if (next !== undefined) expectedUserValue = next;
  };
  watch(value, (current) => {
    const fromUser = current === expectedUserValue;
    expectedUserValue = undefined;
    if (!fromUser && current === '') interacted.value = false;
  });

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

  const errorText = computed(() => (issue.value ? passphraseIssueMessage(issue.value, t) : ''));

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
