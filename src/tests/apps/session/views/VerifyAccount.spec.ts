// src/tests/apps/session/views/VerifyAccount.spec.ts

/**
 * VerifyAccount View Tests — escape-link redirect preservation.
 *
 * The happy path (a good key) navigates away via useAuth.verifyAccount, which
 * owns the redirect and is covered by useAuth.verifyAccount.spec.ts. What this
 * file pins is the OTHER two states, where the user is stranded on the page and
 * the hardcoded escape links were the last place `?redirect=` got dropped:
 *
 *  - verification FAILED (expired / already-used key) → "Sign in" + "Create a
 *    new account" buttons,
 *  - NO key in the URL at all → the missing-key "Sign in" link.
 *
 * In both cases the user is going to recover through signin/signup, so the
 * destination they were originally headed for has to travel with them. The
 * param is re-validated locally because a query string is user-controlled.
 *
 * Harness note: vue-router-mock stubs <router-link> as an empty
 * <router-link-stub>, so link labels are unassertable — assert on the `to`
 * prop via findComponent + data-testid (same pattern as CheckEmail.spec.ts).
 */

// Import order matters here: vi.mock factories are hoisted above the imports
// and run on first import of the module they replace. The factories below
// close over `defineComponent`/`ref` from 'vue', so 'vue' (and the rest) must
// be imported BEFORE VerifyAccount.vue, whose own import triggers them.
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { createMemoryHistory, createRouter, Router, RouterLink } from 'vue-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import VerifyAccount from '@/apps/session/views/VerifyAccount.vue';

// useAuth is mocked wholesale: this file is about what the view renders when
// verification does NOT navigate away, so the composable is reduced to a
// controllable verifyAccount plus the REAL refs the template reads (they must
// be refs, not plain objects — the template unwraps them, and `v-if="isLoading"`
// on a bare object is always truthy). Declaring them at module scope alongside
// a lazily-dereferencing vi.mock factory is safe despite hoisting.
const mockVerifyAccount = vi.fn();
const mockIsLoading = ref(false);
const mockError = ref<string | null>(null);

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({
    verifyAccount: mockVerifyAccount,
    isLoading: mockIsLoading,
    error: mockError,
  }),
}));

vi.mock('@/apps/session/components/ResendVerificationForm.vue', () => ({
  default: defineComponent({
    name: 'ResendVerificationForm',
    props: ['email', 'compact'],
    template: '<div data-testid="resend-stub" />',
  }),
}));

const i18n = createTestI18n();

describe('VerifyAccount.vue escape links', () => {
  let router: Router;
  let wrapper: VueWrapper;

  const createWrapper = async (query: Record<string, string> = {}) => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/verify-account', name: 'verify-account', component: VerifyAccount },
        { path: '/signin', name: 'signin', component: { template: '<div />' } },
        { path: '/signup', name: 'signup', component: { template: '<div />' } },
        { path: '/', name: 'home', component: { template: '<div />' } },
      ],
    });
    await router.push({ path: '/verify-account', query });
    await router.isReady();

    const mounted = mount(VerifyAccount, {
      global: {
        plugins: [
          router,
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            stubActions: true,
            initialState: {
              bootstrap: {
                authentication: { enabled: true, signin: true, signup: true },
              },
            },
          }),
        ],
      },
    });
    await flushPromises();
    return mounted;
  };

  /** The `to` a router-link was given, without depending on its rendered label. */
  const linkTarget = (testid: string) =>
    wrapper.findComponent<typeof RouterLink>(`[data-testid="${testid}"]`).props('to');

  beforeEach(() => {
    mockIsLoading.value = false;
    mockError.value = null;
    // Default: the key is rejected, which is the state that renders the
    // failure-path escape links.
    mockVerifyAccount.mockReset();
    mockVerifyAccount.mockResolvedValue(false);
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  describe('after a failed verification (expired / already-used key)', () => {
    it('appends a validated redirect to both escape links', async () => {
      mockError.value = 'expired verification key';
      wrapper = await createWrapper({ key: 'stale-key', redirect: '/workspace/domains' });

      expect(linkTarget('verify-signin-link')).toEqual({
        path: '/signin',
        query: { redirect: '/workspace/domains' },
      });
      expect(linkTarget('verify-signup-link')).toEqual({
        path: '/signup',
        query: { redirect: '/workspace/domains' },
      });
    });

    it('preserves the query string and hash of the redirect', async () => {
      mockError.value = 'expired verification key';
      wrapper = await createWrapper({
        key: 'stale-key',
        redirect: '/secret/abc?view=raw#content',
      });

      expect(linkTarget('verify-signin-link')).toEqual({
        path: '/signin',
        query: { redirect: '/secret/abc?view=raw#content' },
      });
    });

    it('leaves the links bare when there is no redirect param', async () => {
      mockError.value = 'expired verification key';
      wrapper = await createWrapper({ key: 'stale-key' });

      expect(linkTarget('verify-signin-link')).toBe('/signin');
      expect(linkTarget('verify-signup-link')).toBe('/signup');
    });

    it.each([
      ['protocol-relative', '//evil.example/phish'],
      ['absolute URL', 'https://evil.example/phish'],
      ['backslash authority', '/\\evil.example'],
      ['encoded traversal', '/%2e%2e/admin'],
      ['CRLF injection', '/x%0D%0ASet-Cookie:%20a=b'],
    ])('drops a %s redirect rather than forwarding it', async (_label, value) => {
      mockError.value = 'expired verification key';
      wrapper = await createWrapper({ key: 'stale-key', redirect: value });

      expect(linkTarget('verify-signin-link')).toBe('/signin');
      expect(linkTarget('verify-signup-link')).toBe('/signup');
    });
  });

  describe('when the URL carries no verification key', () => {
    it('appends a validated redirect to the sign-in link', async () => {
      wrapper = await createWrapper({ redirect: '/workspace/domains' });

      expect(mockVerifyAccount).not.toHaveBeenCalled();
      expect(linkTarget('verify-missing-key-signin-link')).toEqual({
        path: '/signin',
        query: { redirect: '/workspace/domains' },
      });
    });

    it('leaves the sign-in link bare when there is no redirect param', async () => {
      wrapper = await createWrapper({});

      expect(linkTarget('verify-missing-key-signin-link')).toBe('/signin');
    });
  });

  describe('when the key verifies', () => {
    it('delegates navigation to useAuth (no escape links rendered)', async () => {
      // verifyAccount owns the redirect on the happy path; the view must not
      // second-guess it. See useAuth.verifyAccount.spec.ts.
      mockVerifyAccount.mockResolvedValue(true);
      wrapper = await createWrapper({ key: 'good-key', redirect: '/dashboard' });

      expect(mockVerifyAccount).toHaveBeenCalledWith('good-key');
      expect(wrapper.findComponent('[data-testid="verify-signin-link"]').exists()).toBe(false);
    });
  });
});
