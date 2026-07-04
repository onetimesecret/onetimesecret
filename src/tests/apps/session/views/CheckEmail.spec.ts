// src/tests/apps/session/views/CheckEmail.spec.ts

/**
 * CheckEmail View Tests
 *
 * The post-signup "Check your email" confirmation page. Verifies that it:
 *  - reads the email address from router history state (NOT the URL query — it
 *    is PII; see src/utils/pii.ts and src/router/README.md),
 *  - sanitizes that address for display and falls back to generic copy when it
 *    is absent, non-string, or implausible (tampered state),
 *  - prefills the resend form with the known address in compact mode, and
 *  - preserves billing/redirect params on the "start over" link while
 *    deliberately NOT carrying the email back into a URL.
 */

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, afterEach, vi } from 'vitest';
import { createRouter, createMemoryHistory, Router } from 'vue-router';
import { defineComponent } from 'vue';
import CheckEmail from '@/apps/session/views/CheckEmail.vue';
import { CHECK_EMAIL_STATE_KEY } from '@/shared/constants/checkEmail';
import { createTestI18n } from '@tests/setup';

// Render AuthView's named slots inline so slot content is testable.
vi.mock('@/apps/session/components/AuthView.vue', () => ({
  default: defineComponent({
    name: 'AuthView',
    template: `<div data-testid="auth-view">
      <slot name="form" />
      <slot name="footer" />
    </div>`,
    props: [
      'heading',
      'headingId',
      'withHeading',
      'withSubheading',
      'omitIcon',
      'hideIcon',
      'hideBackgroundIcon',
    ],
  }),
}));

// Stub the resend form but expose its props so we can assert prefill + mode.
vi.mock('@/apps/session/components/ResendVerificationForm.vue', () => ({
  default: defineComponent({
    name: 'ResendVerificationForm',
    props: ['email', 'compact'],
    template: '<div data-testid="resend-stub" :data-email="email" :data-compact="compact" />',
  }),
}));

const i18n = createTestI18n();

describe('CheckEmail.vue', () => {
  let router: Router;
  let wrapper: VueWrapper;

  /**
   * Mount the view with the email handed over via router history state (as
   * useAuth.signup does), and any non-PII billing/redirect params in the query.
   * `email: undefined` simulates a fresh entry with no state (shared link, new
   * tab, typed URL). A plain reload would instead preserve the state.
   */
  const createWrapper = async (
    opts: { email?: unknown; query?: Record<string, string> } = {}
  ) => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/check-email', name: 'check-email', component: CheckEmail },
        { path: '/signin', name: 'signin', component: { template: '<div />' } },
        { path: '/signup', name: 'signup', component: { template: '<div />' } },
      ],
    });
    await router.push({
      path: '/check-email',
      query: opts.query ?? {},
      ...(opts.email !== undefined ? { state: { [CHECK_EMAIL_STATE_KEY]: opts.email } } : {}),
    });
    await router.isReady();

    return mount(CheckEmail, {
      global: { plugins: [router, i18n] },
    });
  };

  afterEach(() => {
    wrapper?.unmount();
  });

  it('echoes the email address from router history state', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const address = wrapper.find('[data-testid="check-email-address"]');
    expect(address.exists()).toBe(true);
    expect(address.text()).toBe('tom@myspace.com');
  });

  it('never places the email in the URL (state, not query)', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    // The whole point: the address is shown, but the URL stays clean.
    expect(wrapper.find('[data-testid="check-email-address"]').text()).toBe('tom@myspace.com');
    expect(router.currentRoute.value.query.email).toBeUndefined();
    expect(router.currentRoute.value.fullPath).toBe('/check-email');
  });

  it('shows a help affordance beside the address carrying the details', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    // The explanatory copy moved onto a help icon (title + aria-label) so the
    // screen stays a single instruction: check this inbox.
    const help = wrapper.find('[data-testid="check-email-help"]');
    expect(help.exists()).toBe(true);
    expect(help.attributes('aria-label')).toBe('web.auth.check_email.help');
    expect(help.attributes('title')).toBe('web.auth.check_email.help');
  });

  it('falls back to generic copy when no email is in state (fresh entry: shared link / new tab)', async () => {
    wrapper = await createWrapper({});

    expect(wrapper.find('[data-testid="check-email-address"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.auth.check_email.sent_to_generic');
  });

  it('falls back to generic copy for an implausible state value (no @, over-long, non-string)', async () => {
    const badValues: unknown[] = ['not-an-email', 'x'.repeat(255) + '@e.com', 12345, { a: 1 }];
    for (const bad of badValues) {
      wrapper = await createWrapper({ email: bad });
      expect(wrapper.find('[data-testid="check-email-address"]').exists()).toBe(false);
      expect(wrapper.text()).toContain('web.auth.check_email.sent_to_generic');
      wrapper.unmount();
    }
  });

  it('uses a compact one-click resend prefilled with the known address', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const resend = wrapper.find('[data-testid="resend-stub"]');
    expect(resend.exists()).toBe(true);
    expect(resend.attributes('data-email')).toBe('tom@myspace.com');
    // Email is known → compact (no editable field competing with "start over").
    expect(resend.attributes('data-compact')).toBe('true');
  });

  it('falls back to the full resend form when no email is known', async () => {
    wrapper = await createWrapper({});

    const resend = wrapper.find('[data-testid="resend-stub"]');
    expect(resend.exists()).toBe(true);
    expect(resend.attributes('data-compact')).toBe('false');
  });

  it('points "start over" back to signup preserving billing params but NOT the email', async () => {
    wrapper = await createWrapper({
      email: 'tom@myspace.com',
      query: { product: 'identity', interval: 'month' },
    });

    const to = wrapper.findComponent('[data-testid="check-email-start-over-link"]').props('to');
    // Billing context is preserved; the email is deliberately dropped so the
    // corrected address is retyped and no PII returns to a URL.
    expect(to).toEqual({
      path: '/signup',
      query: { product: 'identity', interval: 'month' },
    });
  });

  it('points "start over" to a bare /signup when there are no billing params', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const to = wrapper.findComponent('[data-testid="check-email-start-over-link"]').props('to');
    expect(to).toBe('/signup');
  });

  it('does not render a sign-in link (start over is the only recovery path)', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    expect(wrapper.find('[data-testid="check-email-signin-link"]').exists()).toBe(false);
  });
});
