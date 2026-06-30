// src/tests/apps/session/components/ResendVerificationForm.spec.ts

/**
 * Tests for ResendVerificationForm.vue — the self-service "resend verification
 * email" form shown on the verify-account screen for stuck Unverified accounts.
 *
 * Key behaviours (these encode the PR #3552 review fixes):
 *  - The neutral confirmation replaces the form ONLY when the request was
 *    accepted. A failed request (network/5xx/malformed) keeps the form visible
 *    so the user can retry, and surfaces a retryable error.
 *  - Submitting via the <form> (Enter key or button) triggers the resend.
 *  - An empty email never calls the API.
 *
 * useAuth is mocked so the component is tested against the composable contract;
 * the composable itself is covered by useAuth.resendVerification.spec.ts.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

import ResendVerificationForm from '@/apps/session/components/ResendVerificationForm.vue';

// Return the i18n key verbatim so assertions are stable and locale-independent.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const resendVerificationEmail = vi.fn();
const isLoading = ref(false);

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({ resendVerificationEmail, isLoading }),
}));

describe('ResendVerificationForm', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    isLoading.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const sel = {
    form: 'form',
    input: '[data-testid="resend-verification-email-input"]',
    submit: '[data-testid="resend-verification-email-submit"]',
    confirmation: '[data-testid="resend-verification-email-confirmation"]',
    error: '[data-testid="resend-verification-email-error"]',
  };

  const submitWith = async (w: VueWrapper, email: string) => {
    await w.find(sel.input).setValue(email);
    await w.find(sel.form).trigger('submit.prevent');
    await flushPromises();
  };

  it('renders the help text, email input and submit button', () => {
    wrapper = mount(ResendVerificationForm);

    expect(wrapper.find('[data-testid="resend-verification-form"]').exists()).toBe(true);
    expect(wrapper.find(sel.input).exists()).toBe(true);
    expect(wrapper.find(sel.submit).exists()).toBe(true);
    expect(wrapper.text()).toContain('web.auth.verify.resend_help_text');
  });

  it('calls resendVerificationEmail with the entered email on submit', async () => {
    resendVerificationEmail.mockResolvedValue(true);
    wrapper = mount(ResendVerificationForm);

    await submitWith(wrapper, 'user@example.com');

    expect(resendVerificationEmail).toHaveBeenCalledWith('user@example.com');
  });

  it('shows the neutral confirmation and hides the form when the request is accepted', async () => {
    resendVerificationEmail.mockResolvedValue(true);
    wrapper = mount(ResendVerificationForm);

    await submitWith(wrapper, 'user@example.com');

    expect(wrapper.find(sel.confirmation).exists()).toBe(true);
    expect(wrapper.find(sel.confirmation).text()).toContain('web.auth.verify.resend_sent');
    // Form (and its input) is gone once confirmed.
    expect(wrapper.find(sel.form).exists()).toBe(false);
  });

  it('keeps the form visible and shows an error when the request fails', async () => {
    resendVerificationEmail.mockResolvedValue(false);
    wrapper = mount(ResendVerificationForm);

    await submitWith(wrapper, 'user@example.com');

    // Form stays so the user can retry...
    expect(wrapper.find(sel.form).exists()).toBe(true);
    expect(wrapper.find(sel.confirmation).exists()).toBe(false);
    // ...and a retryable error is shown.
    const error = wrapper.find(sel.error);
    expect(error.exists()).toBe(true);
    expect(error.text()).toContain('web.auth.verify.resend_error');
  });

  it('does not call the API for an empty email', async () => {
    wrapper = mount(ResendVerificationForm);

    await submitWith(wrapper, '');

    expect(resendVerificationEmail).not.toHaveBeenCalled();
  });

  it('disables the submit button while loading', async () => {
    isLoading.value = true;
    wrapper = mount(ResendVerificationForm);

    expect(wrapper.find(sel.submit).attributes('disabled')).toBeDefined();
  });
});
