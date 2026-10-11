// src/tests/apps/workspace/components/domains/DomainSignupConfigForm.spec.ts
//
// Tests for DomainSignupConfigForm.vue's allow_base_domain option: the
// domain's own registrable domain (`baseDomain`) can join the allowlist
// without being listed. Covers:
// 1. The option is offered only under domain_allowlist AND when the domain
//    record carries a base domain to derive
// 2. Toggling it emits update:formState with allow_base_domain flipped
// 3. can-save: the flag satisfies the list requirement on its own, but only
//    when a base domain exists (same condition the server applies)
// 4. The locked chip and the required marker follow the flag
// 5. Adding the base domain by hand while the flag is on is refused as a
//    duplicate
//
// Copy comes from the real generated bundle (see DomainSigninConfigForm.spec),
// so the {domain} interpolation is verified as substituted, not printed.

import { readFileSync } from 'fs';
import { resolve } from 'path';
import { mount, type VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createRealI18n } from '@tests/setup';
import DomainSignupConfigForm from '@/apps/workspace/components/domains/DomainSignupConfigForm.vue';
import type { SignupConfigFormState } from '@/shared/composables/useSignupConfig';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

vi.mock('@/shared/components/closet/SettingsSkeleton.vue', () => ({
  default: {
    name: 'SettingsSkeleton',
    template: '<div data-testid="settings-skeleton" />',
    props: ['heading'],
  },
}));

// ---------------------------------------------------------------------------
// i18n — the real bundle
// ---------------------------------------------------------------------------

const realEn = JSON.parse(
  readFileSync(resolve(process.cwd(), 'generated/locales/en.json'), 'utf-8')
);
const i18n = createRealI18n({ en: realEn });
const t = (key: string) => i18n.global.t(key);
const tp = (key: string, params: Record<string, string>) => i18n.global.t(key, params);

const BASE_DOMAIN = 'acme.com';

const COPY = {
  allowBaseDomainLabel: tp('web.domains.signup.allow_base_domain_label', { domain: BASE_DOMAIN }),
  allowBaseDomainHint: tp('web.domains.signup.allow_base_domain_hint', { domain: BASE_DOMAIN }),
  automatic: t('web.domains.signup.base_domain_automatic'),
  domainExists: t('web.domains.signup.domain_exists'),
} as const;

// ---------------------------------------------------------------------------
// Fixtures / helpers
// ---------------------------------------------------------------------------

const allowlistFormState: SignupConfigFormState = {
  validation_strategy: 'domain_allowlist',
  allowed_signup_domains: [],
  allow_base_domain: false,
  enabled: true,
  signup_enabled: true,
  autoverify: false,
};

interface MountOptions {
  formState?: Partial<SignupConfigFormState>;
  baseDomain?: string | null;
}

function mountForm(opts: MountOptions = {}): VueWrapper {
  return mount(DomainSignupConfigForm, {
    props: {
      domainExtId: 'dm-ext-test',
      baseDomain: opts.baseDomain === undefined ? BASE_DOMAIN : opts.baseDomain,
      formState: { ...allowlistFormState, ...opts.formState },
      signupConfig: null,
      isLoading: false,
      isSaving: false,
      isDeleting: false,
      hasUnsavedChanges: false,
      isConfigured: false,
    },
    global: { plugins: [i18n] },
  });
}

const checkbox = (wrapper: VueWrapper) => wrapper.find('#signup-allow-base-domain');
const chip = (wrapper: VueWrapper) => wrapper.find('[data-testid="signup-base-domain-chip"]');
const requiredMarker = (wrapper: VueWrapper) =>
  wrapper.find('label[for="signup-domain-input"] span[aria-hidden="true"]');

/** The last `can-save` value the form reported. */
function lastCanSave(wrapper: VueWrapper): boolean | undefined {
  const events = wrapper.emitted('can-save') ?? [];
  return events.at(-1)?.[0] as boolean | undefined;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DomainSignupConfigForm — allow_base_domain', () => {
  describe('when the option is offered', () => {
    it('renders the checkbox under domain_allowlist with the base domain interpolated', () => {
      const wrapper = mountForm();

      expect(checkbox(wrapper).exists()).toBe(true);
      expect((checkbox(wrapper).element as HTMLInputElement).checked).toBe(false);
      expect(wrapper.text()).toContain(COPY.allowBaseDomainLabel);
      expect(wrapper.text()).toContain(COPY.allowBaseDomainHint);
      // The placeholder was substituted, not printed.
      expect(wrapper.text()).not.toContain('{domain}');
    });

    it('does not render the checkbox under passthrough (the list is not consulted)', () => {
      const wrapper = mountForm({ formState: { validation_strategy: 'passthrough' } });
      expect(checkbox(wrapper).exists()).toBe(false);
    });

    it('does not render the checkbox when the domain record has no base domain', () => {
      const wrapper = mountForm({ baseDomain: null });
      expect(checkbox(wrapper).exists()).toBe(false);
    });
  });

  describe('toggling', () => {
    it('emits update:formState with allow_base_domain true, keeping the other fields', async () => {
      const wrapper = mountForm({ formState: { allowed_signup_domains: ['partner.com'] } });

      await checkbox(wrapper).setValue(true);

      const emitted = wrapper.emitted('update:formState');
      expect(emitted).toHaveLength(1);
      expect(emitted?.[0]?.[0]).toEqual({
        ...allowlistFormState,
        allowed_signup_domains: ['partner.com'],
        allow_base_domain: true,
      });
    });

    it('emits allow_base_domain false when unchecked', async () => {
      const wrapper = mountForm({ formState: { allow_base_domain: true } });

      await checkbox(wrapper).setValue(false);

      const emitted = wrapper.emitted('update:formState');
      expect(emitted?.[0]?.[0]).toMatchObject({ allow_base_domain: false });
    });
  });

  describe('can-save', () => {
    it('is false for domain_allowlist with an empty list and the flag off', () => {
      const wrapper = mountForm();
      expect(lastCanSave(wrapper)).toBe(false);
    });

    it('is true for domain_allowlist with an empty list once the flag is on', () => {
      const wrapper = mountForm({ formState: { allow_base_domain: true } });
      expect(lastCanSave(wrapper)).toBe(true);
    });

    it('stays false when the flag is on but there is no base domain to derive', () => {
      const wrapper = mountForm({ formState: { allow_base_domain: true }, baseDomain: null });
      expect(lastCanSave(wrapper)).toBe(false);
    });

    it('re-evaluates when the parent flips the flag', async () => {
      const wrapper = mountForm();
      expect(lastCanSave(wrapper)).toBe(false);

      await wrapper.setProps({ formState: { ...allowlistFormState, allow_base_domain: true } });

      expect(lastCanSave(wrapper)).toBe(true);
    });
  });

  describe('list presentation', () => {
    it('shows the base domain as a locked chip marked automatic while the flag is on', () => {
      const wrapper = mountForm({ formState: { allow_base_domain: true } });

      expect(chip(wrapper).exists()).toBe(true);
      expect(chip(wrapper).text()).toContain(BASE_DOMAIN);
      expect(chip(wrapper).text()).toContain(COPY.automatic);
      // Locked: no remove button inside the automatic chip.
      expect(chip(wrapper).find('button').exists()).toBe(false);
    });

    it('shows no chip while the flag is off', () => {
      const wrapper = mountForm();
      expect(chip(wrapper).exists()).toBe(false);
    });

    it('drops the required marker from the list label while the flag is on', () => {
      expect(requiredMarker(mountForm()).exists()).toBe(true);
      expect(requiredMarker(mountForm({ formState: { allow_base_domain: true } })).exists()).toBe(
        false
      );
    });
  });

  describe('adding domains by hand', () => {
    it('refuses the base domain as a duplicate while the flag is on', async () => {
      const wrapper = mountForm({ formState: { allow_base_domain: true } });

      const input = wrapper.find('#signup-domain-input');
      await input.setValue('ACME.com');
      await input.trigger('keydown.enter');

      expect(wrapper.emitted('update:formState')).toBeUndefined();
      expect(wrapper.find('#signup-domain-input-error').text()).toBe(COPY.domainExists);
    });

    it('still accepts the base domain as a listed entry while the flag is off', async () => {
      const wrapper = mountForm();

      const input = wrapper.find('#signup-domain-input');
      await input.setValue(BASE_DOMAIN);
      await input.trigger('keydown.enter');

      expect(wrapper.emitted('update:formState')?.[0]?.[0]).toMatchObject({
        allowed_signup_domains: [BASE_DOMAIN],
      });
    });
  });
});
