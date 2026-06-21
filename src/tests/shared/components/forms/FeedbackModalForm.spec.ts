// src/tests/shared/components/forms/FeedbackModalForm.spec.ts
//
// Tests for FeedbackModalForm component, specifically verifying that customer
// information (email) is only displayed for authenticated users (when objid is present).
//
// Context: PR #2733/2736 - anonymous users now receive cust: null (not an object
// with null fields). Tests include both null cust and object-with-null-objid
// cases for defensive coverage.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import FeedbackModalForm from '@/shared/components/forms/FeedbackModalForm.vue';
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

// Mock useMediaQuery from VueUse
vi.mock('@vueuse/core', () => ({
  useMediaQuery: () => ({ value: true }),
}));

const i18n = createTestI18n();

describe('FeedbackModalForm', () => {
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

    return mount(FeedbackModalForm, {
      props: {
        enabled: true,
        showRedButton: false,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  describe('Customer Email Display', () => {
    it('displays customer email when user is authenticated (objid present)', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      // Should show customer ID line with email value (pass-through i18n: raw key)
      expect(html).toContain('web.account.customer_id');
      expect(html).toContain(authenticatedCustomer.email);
    });

    it('does NOT display customer email when user is anonymous (objid is null)', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      // Should NOT show customer ID line - the <li> with customer info should be hidden
      // (pass-through i18n: raw key)
      expect(html).not.toContain('web.account.customer_id');
      // Email should not appear (it's null anyway, but the line should be hidden)
      expect(html).not.toContain('test@example.com');
    });

    it('does NOT display customer email when cust is null', async () => {
      wrapper = mountComponent({
        cust: null,
      });

      await nextTick();

      const html = wrapper.html();
      // Should NOT show customer ID line (pass-through i18n: raw key)
      expect(html).not.toContain('web.account.customer_id');
    });
  });

  describe('Always-visible Information', () => {
    it('displays timezone for authenticated users', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('web.account.timezone');
    });

    it('displays timezone for anonymous users', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('web.account.timezone');
    });

    it('displays version for all users', async () => {
      wrapper = mountComponent({
        cust: anonymousCustomer,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('web.site.website_version');
      expect(html).toContain('0.20.0 (test)');
    });
  });

  describe('Edge Cases', () => {
    it('handles customer with objid but no email gracefully', async () => {
      const customerNoEmail = {
        ...authenticatedCustomer,
        email: null,
      };

      wrapper = mountComponent({
        cust: customerNoEmail,
      });

      await nextTick();

      // Should still show customer ID line since objid is present
      // (pass-through i18n: raw key)
      const html = wrapper.html();
      expect(html).toContain('web.account.customer_id');
    });

    it('handles customer with empty string objid as anonymous', async () => {
      const customerEmptyObjid = {
        ...authenticatedCustomer,
        objid: '',
      };

      wrapper = mountComponent({
        cust: customerEmptyObjid,
      });

      await nextTick();

      // Empty string is falsy, so customer ID should NOT be shown
      // (pass-through i18n: raw key)
      const html = wrapper.html();
      expect(html).not.toContain('web.account.customer_id');
    });
  });

  describe('Form Elements', () => {
    it('renders feedback textarea with required attribute', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const textarea = wrapper.find('textarea[name="msg"]');
      expect(textarea.exists()).toBe(true);
      expect(textarea.attributes('required')).toBeDefined();
    });

    it('renders submit button', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const button = wrapper.find('button[type="submit"]');
      expect(button.exists()).toBe(true);
      expect(button.text()).toBe('web.COMMON.button_send_feedback');
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

    it('includes hidden timezone and version inputs', async () => {
      wrapper = mountComponent({
        cust: authenticatedCustomer,
      });

      await nextTick();

      const tzInput = wrapper.find('input[name="tz"]');
      const versionInput = wrapper.find('input[name="version"]');

      expect(tzInput.exists()).toBe(true);
      expect(versionInput.exists()).toBe(true);
      expect(versionInput.attributes('value')).toBe('0.20.0 (test)');
    });
  });
});
