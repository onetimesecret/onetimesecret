// src/tests/apps/secret/components/support/FeedbackForm.spec.ts
//
// Tests for FeedbackForm component, specifically verifying that customer
// information is only displayed for authenticated users (when objid is present).
//
// Context: PR #2733/2736 - anonymous users now receive cust: null (not an object
// with null fields). Tests include both null cust and object-with-null-objid
// cases for defensive coverage.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import FeedbackForm from '@/apps/secret/components/support/FeedbackForm.vue';
import { nextTick } from 'vue';

// Mock useFormSubmission composable
vi.mock('@/shared/composables/useFormSubmission', () => ({
  useFormSubmission: () => ({
    isSubmitting: { value: false },
    error: { value: null },
    success: { value: null },
    submitForm: vi.fn(),
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        COMMON: {
          feedback_text: 'Enter your feedback...',
          button_send_feedback: 'Send Feedback',
        },
        LABELS: {
          feedback_received: 'Feedback received',
          sending_ellipses: 'Sending...',
        },
        feedback: {
          your_feedback: 'Your feedback',
          send_feedback: 'Send Feedback',
          when_you_submit_feedback_well_see: "When you submit feedback, we'll see:",
          reason_email_change_unauthorized: 'Email change unauthorized',
          sending_ellipses: 'Sending...',
        },
        account: {
          customer_id: 'Customer ID',
          timezone: 'Timezone',
        },
        site: {
          website_version: 'Version',
        },
      },
    },
  },
});

describe('FeedbackForm', () => {
  let wrapper: VueWrapper;

  // Authenticated customer with objid present
  const authenticatedCustomer = {
    objid: 'cust_obj_123',
    extid: 'cust_ext_123',
    email: 'test@example.com',
    role: 'customer',
    verified: true,
  };

  // Edge case: object with null fields (defensive test, backend now sends null)
  const anonymousCustomer = {
    objid: null,
    extid: null,
    email: null,
    role: 'anonymous',
    verified: false,
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    storeState: {
      cust?: typeof authenticatedCustomer | typeof anonymousCustomer | null;
    } = {}
  ) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          cust: storeState.cust ?? null,
          ot_version_long: '0.20.0 (test)',
        },
        csrf: {
          shrimp: 'test-csrf-token',
        },
      },
    });

    return mount(FeedbackForm, {
      props: {
        enabled: true,
        showRedButton: false,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  describe('Customer ID Display', () => {
    it('displays customer email when user is authenticated (objid present)', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      // Should show customer ID line with email value (changed from extid to email in #2761)
      expect(html).toContain('Customer ID');
      expect(html).toContain(authenticatedCustomer.email);
    });

    it('does NOT display customer ID when user is anonymous (objid is null)', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      // Should NOT show customer ID line - the <li> with customer info should be hidden
      // The parent element contains timezone and version, but not customer ID
      expect(html).not.toContain('Customer ID');
      expect(html).not.toContain('cust_ext');
    });

    it('does NOT display customer ID when cust is null', async () => {
      wrapper = mountComponent({
        cust: null,
      });

      await nextTick();

      const html = wrapper.html();
      // Should NOT show customer ID line
      expect(html).not.toContain('Customer ID');
    });
  });

  describe('Always-visible Information', () => {
    it('displays timezone for authenticated users', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('Timezone');
    });

    it('displays timezone for anonymous users', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('Timezone');
    });

    it('displays version for all users', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('Version');
      expect(html).toContain('0.20.0 (test)');
    });
  });

  describe('Form Elements', () => {
    it('renders feedback textarea', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const textarea = wrapper.find('textarea[name="msg"]');
      expect(textarea.exists()).toBe(true);
    });

    it('renders submit button', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const button = wrapper.find('button[type="submit"]');
      expect(button.exists()).toBe(true);
    });

    it('includes CSRF token in form', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const shrimpInput = wrapper.find('input[name="shrimp"]');
      expect(shrimpInput.exists()).toBe(true);
      expect(shrimpInput.attributes('value')).toBe('test-csrf-token');
    });
  });
});
