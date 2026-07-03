// src/tests/apps/session/views/CheckEmail.spec.ts

/**
 * CheckEmail View Tests
 *
 * The post-signup "Check your email" confirmation page. Verifies that it:
 *  - echoes the email address from the ?email query param,
 *  - falls back to generic copy when no email is present,
 *  - prefills the resend form with the known address, and
 *  - preserves email/billing/redirect params on the onward sign-in/start-over links.
 */

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, afterEach, vi } from 'vitest';
import { createRouter, createMemoryHistory, Router } from 'vue-router';
import { defineComponent } from 'vue';
import CheckEmail from '@/apps/session/views/CheckEmail.vue';
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
      'hideIcon',
      'hideBackgroundIcon',
    ],
  }),
}));

// Stub the resend form but expose its `email` prop so we can assert prefill.
vi.mock('@/apps/session/components/ResendVerificationForm.vue', () => ({
  default: defineComponent({
    name: 'ResendVerificationForm',
    props: ['email'],
    template: '<div data-testid="resend-stub" :data-email="email" />',
  }),
}));

const i18n = createTestI18n();

describe('CheckEmail.vue', () => {
  let router: Router;
  let wrapper: VueWrapper;

  const createWrapper = async (query: Record<string, string> = {}) => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/check-email', name: 'check-email', component: CheckEmail },
        { path: '/signin', name: 'signin', component: { template: '<div />' } },
        { path: '/signup', name: 'signup', component: { template: '<div />' } },
      ],
    });
    await router.push({ path: '/check-email', query });
    await router.isReady();

    return mount(CheckEmail, {
      global: { plugins: [router, i18n] },
    });
  };

  afterEach(() => {
    wrapper?.unmount();
  });

  it('echoes the email address from the query param', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const address = wrapper.find('[data-testid="check-email-address"]');
    expect(address.exists()).toBe(true);
    expect(address.text()).toBe('tom@myspace.com');
  });

  it('falls back to generic copy when no email is present', async () => {
    wrapper = await createWrapper({});

    expect(wrapper.find('[data-testid="check-email-address"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.auth.check_email.sent_to_generic');
  });

  it('prefills the resend form with the known address', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const resend = wrapper.find('[data-testid="resend-stub"]');
    expect(resend.exists()).toBe(true);
    expect(resend.attributes('data-email')).toBe('tom@myspace.com');
  });

  it('preserves email + billing params on the onward sign-in link', async () => {
    wrapper = await createWrapper({
      email: 'tom@myspace.com',
      product: 'identity',
      interval: 'month',
    });

    const to = wrapper.findComponent('[data-testid="check-email-signin-link"]').props('to');
    expect(to).toEqual({
      path: '/signin',
      query: { email: 'tom@myspace.com', product: 'identity', interval: 'month' },
    });
  });

  it('points "start over" back to signup preserving the email', async () => {
    wrapper = await createWrapper({ email: 'tom@myspace.com' });

    const to = wrapper.findComponent('[data-testid="check-email-start-over-link"]').props('to');
    expect(to).toEqual({ path: '/signup', query: { email: 'tom@myspace.com' } });
  });
});
