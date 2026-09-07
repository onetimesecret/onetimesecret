// src/tests/apps/session/views/MfaChallenge.spec.ts

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { defineComponent, ref } from 'vue';
import { createTestI18n } from '@tests/setup';
import MfaChallenge from '@/apps/session/views/MfaChallenge.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { OtpVerifySuccess } from '@/schemas/api/auth/responses/auth';
import type { MfaStatus } from '@/types/auth';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

// Route/router: the component reads route.query.redirect and pushes on
// success. Factories dereference lazily (at call time), so plain consts work.
const mockRoute = { path: '/mfa-verify', query: {} as Record<string, unknown> };
const routerPushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: routerPushMock, replace: vi.fn() }),
  isNavigationFailure: () => false,
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

// AuthView is layout chrome (jurisdiction store, RouterLink); render slots only.
vi.mock('@/apps/session/components/AuthView.vue', () => ({
  default: defineComponent({
    name: 'AuthView',
    props: ['heading', 'headingId', 'withSubheading', 'showReturnHome'],
    template: `<div data-testid="auth-view">
      <slot name="form" />
      <slot name="footer" />
    </div>`,
  }),
}));

// OtpCodeInput: six-input widget, irrelevant here — expose the complete emit.
vi.mock('@/apps/session/components/OtpCodeInput.vue', () => ({
  default: defineComponent({
    name: 'OtpCodeInput',
    props: ['disabled', 'ariaDescribedby'],
    emits: ['complete'],
    template: '<input data-testid="otp-input-stub" />',
  }),
}));

// Mock useMfa composable
const mockMfaState = {
  isLoading: ref(false),
  error: ref<string | null>(null),
  // Two-factor completion body (#4306) — the component feeds this into the
  // REAL usePostAuthRedirect, which is deliberately not mocked here.
  verifyResponse: ref<OtpVerifySuccess | null>(null),
  fetchMfaStatus: vi.fn(),
  verifyOtp: vi.fn(),
  verifyRecoveryCode: vi.fn(),
  clearError: vi.fn(),
};

vi.mock('@/shared/composables/useMfa', () => ({
  useMfa: () => mockMfaState,
}));

// Mock useWebAuthn composable
const mockWebAuthnState = {
  supported: ref(true),
  isLoading: ref(false),
  error: ref<string | null>(null),
  // Webauthn's own two-factor completion body (#4306) — the mirror of
  // useMfa.verifyResponse for the passkey factor.
  mfaVerifyResponse: ref<OtpVerifySuccess | null>(null),
  verifyWebAuthnMfa: vi.fn(),
  clearError: vi.fn(),
};

vi.mock('@/shared/composables/useWebAuthn', () => ({
  useWebAuthn: () => mockWebAuthnState,
}));

// Mock useAuth (cancel → logout)
const mockLogout = vi.fn();
vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({ logout: mockLogout }),
}));

const i18n = createTestI18n();

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/**
 * Backend truth: `enabled` means otp || recovery ONLY — webauthn does not
 * flip it. Fixtures below keep that invariant (webauthn-only ⇒ enabled=false
 * unless recovery codes exist).
 */
const status = (over: Partial<MfaStatus> = {}): MfaStatus => ({
  enabled: true,
  last_used_at: null,
  recovery_codes_remaining: 5,
  recovery_codes_limit: 10,
  otp_enabled: true,
  webauthn_enabled: false,
  ...over,
});

const otpOnly = () => status();
const bothFactors = () => status({ webauthn_enabled: true });
const webauthnOnly = () =>
  status({ enabled: false, otp_enabled: false, webauthn_enabled: true, recovery_codes_remaining: 0 });
const webauthnWithRecovery = () =>
  status({ otp_enabled: false, webauthn_enabled: true, recovery_codes_remaining: 3 });
const nothingEnabled = () =>
  status({ enabled: false, otp_enabled: false, webauthn_enabled: false, recovery_codes_remaining: 0 });

/**
 * MfaChallenge Component Tests
 *
 * Mounts the REAL component with mocked useMfa/useWebAuthn (pass-through i18n
 * per ADR-014: t() renders keys as-is, so assertions target i18n keys).
 *
 * Covers:
 * - Initial mode truth table from GET /auth/mfa-status (otp-only,
 *   webauthn-only, both, neither → force-complete, webauthn-but-unsupported)
 * - Unsupported-browser terminal state (webauthn sole completable factor +
 *   !supported → explicit notice, no dead factor panels, Cancel as exit)
 * - Passkey verify success → setAuthenticated + validated redirect
 * - Passkey verify failure → composable error surfaced in the panel
 * - Footer toggle visibility matrix (never point at a factor the account
 *   doesn't have — including recovery gated on codes remaining)
 * - Recovery back-link targets the INITIAL mode (passkey for webauthn-only;
 *   hidden entirely when recovery IS the initial mode)
 * - Force-complete guard must NOT fire when webauthn_enabled is true
 */
describe('MfaChallenge', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.query = {};
    mockMfaState.isLoading.value = false;
    mockMfaState.error.value = null;
    mockMfaState.verifyResponse.value = null;
    mockMfaState.fetchMfaStatus.mockResolvedValue(otpOnly());
    mockMfaState.verifyOtp.mockResolvedValue(true);
    mockMfaState.verifyRecoveryCode.mockResolvedValue(true);
    mockWebAuthnState.supported.value = true;
    mockWebAuthnState.isLoading.value = false;
    mockWebAuthnState.error.value = null;
    mockWebAuthnState.mfaVerifyResponse.value = null;
    mockWebAuthnState.verifyWebAuthnMfa.mockResolvedValue(true);
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountChallenge = async () => {
    const w = mount(MfaChallenge, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
          }),
        ],
      },
    });
    await flushPromises();
    return w;
  };

  const panel = (w: VueWrapper, name: 'otp' | 'recovery' | 'webauthn') =>
    w.find(`[data-testid="mfa-${name}-panel"]`);
  const byTestId = (w: VueWrapper, id: string) => w.find(`[data-testid="${id}"]`);

  // -------------------------------------------------------------------------
  // Initial mode truth table
  // -------------------------------------------------------------------------

  describe('initial mode from mfa-status', () => {
    it('starts in OTP mode for an otp-only account', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(otpOnly());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(true);
      expect(panel(wrapper, 'webauthn').exists()).toBe(false);
    });

    it('starts in webauthn mode for a webauthn-only account', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
      expect(panel(wrapper, 'otp').exists()).toBe(false);
      expect(wrapper.text()).toContain('web.auth.mfa.passkey_prompt');
    });

    it('prefers OTP when the account has both factors', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(true);
      expect(panel(wrapper, 'webauthn').exists()).toBe(false);
    });

    it('shows the unsupported-browser notice for a webauthn-only account on an unsupported browser', async () => {
      // NOT an OTP fallback: with no otp and no recovery codes, every factor
      // panel would dead-end, so the terminal notice replaces them.
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-webauthn-unsupported').exists()).toBe(true);
      expect(panel(wrapper, 'otp').exists()).toBe(false);
      expect(panel(wrapper, 'webauthn').exists()).toBe(false);
    });

    it('starts in recovery mode for webauthn-only + recovery codes on an unsupported browser', async () => {
      // Recovery is the only completable factor — landing on the dead OTP
      // panel (the old fallback) would strand the user.
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnWithRecovery());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'recovery').exists()).toBe(true);
      expect(panel(wrapper, 'otp').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-webauthn-unsupported').exists()).toBe(false);
    });

    it('keeps OTP mode against an older backend without the per-factor fields', async () => {
      const legacy = otpOnly();
      delete (legacy as Partial<MfaStatus>).otp_enabled;
      delete (legacy as Partial<MfaStatus>).webauthn_enabled;
      mockMfaState.fetchMfaStatus.mockResolvedValue(legacy);
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(true);
      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).not.toHaveBeenCalled();
    });
  });

  // -------------------------------------------------------------------------
  // Force-complete guard (inconsistent awaiting_mfa state)
  // -------------------------------------------------------------------------

  describe('force-complete guard', () => {
    it('completes auth and leaves when NO factor is enabled', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(nothingEnabled());
      wrapper = await mountChallenge();

      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).toHaveBeenCalledWith(true);
      expect(routerPushMock).toHaveBeenCalledWith('/');
    });

    it('does NOT fire for a webauthn-only account (enabled=false but webauthn_enabled=true)', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).not.toHaveBeenCalled();
      expect(routerPushMock).not.toHaveBeenCalled();
      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Unsupported-browser terminal state
  //
  // webauthn_enabled && !otp_enabled && no recovery codes && !supported:
  // every factor panel would dead-end (the router guard pins the user to
  // /mfa-verify), so an explicit notice replaces them and Cancel is the exit.
  // -------------------------------------------------------------------------

  describe('unsupported-browser terminal state', () => {
    it('renders the notice with the shared webauthn keys and keeps Cancel', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      const notice = byTestId(wrapper, 'mfa-webauthn-unsupported');
      expect(notice.exists()).toBe(true);
      expect(notice.attributes('role')).toBe('alert');
      expect(notice.text()).toContain('web.auth.webauthn.notSupported');
      expect(notice.text()).toContain('web.auth.webauthn.requiresModernBrowser');
      expect(byTestId(wrapper, 'mfa-cancel').exists()).toBe(true);
    });

    it('offers no factor panels and no footer alternatives', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(false);
      expect(panel(wrapper, 'recovery').exists()).toBe(false);
      expect(panel(wrapper, 'webauthn').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-use-webauthn').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-back-to-otp').exists()).toBe(false);
    });

    it('does NOT auto-complete auth (the mount guard still respects webauthn_enabled)', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).not.toHaveBeenCalled();
      expect(routerPushMock).not.toHaveBeenCalled();
    });

    it('does not appear when the browser supports webauthn', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-webauthn-unsupported').exists()).toBe(false);
      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
    });

    it('does not appear when another factor is completable (otp+webauthn, unsupported)', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-webauthn-unsupported').exists()).toBe(false);
      expect(panel(wrapper, 'otp').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-use-webauthn').exists()).toBe(false);
      // Recovery stays reachable: bothFactors() has codes remaining.
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
    });

    it('recovery-initial state (webauthn-only + codes, unsupported) has no back link into a dead panel', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnWithRecovery());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'recovery').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-back-to-otp').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-cancel').exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Passkey verification
  // -------------------------------------------------------------------------

  describe('passkey verification', () => {
    beforeEach(() => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
    });

    it('verifies, completes auth, and redirects to / by default', async () => {
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.verifyWebAuthnMfa).toHaveBeenCalledTimes(1);
      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).toHaveBeenCalledWith(true);
      expect(routerPushMock).toHaveBeenCalledWith('/');
    });

    it('honors a valid internal redirect query param', async () => {
      mockRoute.query = { redirect: '/dashboard' };
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      expect(routerPushMock).toHaveBeenCalledWith('/dashboard');
    });

    it('ignores an external redirect (open-redirect guard) and goes to /', async () => {
      mockRoute.query = { redirect: 'https://evil.example/phish' };
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      expect(routerPushMock).toHaveBeenCalledWith('/');
    });

    it('surfaces the composable error and stays put on failure', async () => {
      mockWebAuthnState.verifyWebAuthnMfa.mockImplementation(async () => {
        mockWebAuthnState.error.value = 'web.auth.webauthn.authFailed';
        return false;
      });
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      const errorBox = byTestId(wrapper, 'mfa-webauthn-error');
      expect(errorBox.exists()).toBe(true);
      expect(errorBox.text()).toContain('web.auth.webauthn.authFailed');
      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).not.toHaveBeenCalled();
      expect(routerPushMock).not.toHaveBeenCalled();
      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
    });

    it('disables the verify button while the ceremony is in flight', async () => {
      mockWebAuthnState.isLoading.value = true;
      wrapper = await mountChallenge();

      expect(
        byTestId(wrapper, 'mfa-verify-webauthn-submit').attributes('disabled')
      ).toBeDefined();
    });
  });

  // -------------------------------------------------------------------------
  // Footer toggle visibility matrix
  // -------------------------------------------------------------------------

  describe('footer alternatives', () => {
    it('otp mode: offers recovery + passkey when the account has webauthn', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-use-webauthn').exists()).toBe(true);
    });

    it('otp mode: no passkey link when the account has no webauthn', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(otpOnly());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-use-webauthn').exists()).toBe(false);
    });

    it('otp mode: shows the recovery toggle only while codes remain', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(otpOnly());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
    });

    it('otp mode: hides the recovery toggle when no codes remain', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(status({ recovery_codes_remaining: 0 }));
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-cancel').exists()).toBe(true);
    });

    it('otp mode: no passkey link on an unsupported browser even with webauthn enabled', async () => {
      mockWebAuthnState.supported.value = false;
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-use-webauthn').exists()).toBe(false);
    });

    it('webauthn mode: offers back-to-code and recovery when the account has both', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-use-webauthn').trigger('click');

      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-back-to-otp').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
    });

    it('webauthn mode: offers ONLY cancel for webauthn-only without recovery codes', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      wrapper = await mountChallenge();

      expect(byTestId(wrapper, 'mfa-back-to-otp').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-cancel').exists()).toBe(true);
    });

    it('webauthn mode: offers recovery (but not back-to-code) when only codes remain', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnWithRecovery());
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-back-to-otp').exists()).toBe(false);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
    });

    it('back-to-code returns from webauthn to the OTP panel', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(bothFactors());
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-use-webauthn').trigger('click');
      await byTestId(wrapper, 'mfa-back-to-otp').trigger('click');

      expect(panel(wrapper, 'otp').exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Recovery mode back-link target
  // -------------------------------------------------------------------------

  describe('recovery back-link', () => {
    it('returns to OTP with the back_to_code label for an otp account', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(otpOnly());
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-use-recovery-code').trigger('click');
      expect(panel(wrapper, 'recovery').exists()).toBe(true);

      const back = byTestId(wrapper, 'mfa-back-to-otp');
      expect(back.text()).toContain('web.auth.mfa.back_to_code');
      await back.trigger('click');
      expect(panel(wrapper, 'otp').exists()).toBe(true);
    });

    it('returns to the PASSKEY panel for a webauthn-only account', async () => {
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnWithRecovery());
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-use-recovery-code').trigger('click');
      expect(panel(wrapper, 'recovery').exists()).toBe(true);

      const back = byTestId(wrapper, 'mfa-back-to-otp');
      expect(back.text()).toContain('web.auth.mfa.use_passkey');
      await back.trigger('click');
      expect(panel(wrapper, 'webauthn').exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Existing surface preserved
  // -------------------------------------------------------------------------

  describe('existing OTP/recovery surface', () => {
    it('keeps the OTP panel testids intact', async () => {
      wrapper = await mountChallenge();

      expect(panel(wrapper, 'otp').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-verify-otp-submit').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-use-recovery-code').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-cancel').exists()).toBe(true);
    });

    it('toggles to the recovery panel and back', async () => {
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-use-recovery-code').trigger('click');
      expect(panel(wrapper, 'recovery').exists()).toBe(true);
      expect(byTestId(wrapper, 'mfa-recovery-code-input').exists()).toBe(true);

      await byTestId(wrapper, 'mfa-back-to-otp').trigger('click');
      expect(panel(wrapper, 'otp').exists()).toBe(true);
    });

    it('completes auth and redirects after a successful OTP verify', async () => {
      wrapper = await mountChallenge();

      await wrapper.findComponent({ name: 'OtpCodeInput' }).vm.$emit('complete', '123456');
      await flushPromises();

      expect(mockMfaState.verifyOtp).toHaveBeenCalledWith('123456');
      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).toHaveBeenCalledWith(true);
      expect(routerPushMock).toHaveBeenCalledWith('/');
    });

    it('cancel logs out to /signin', async () => {
      wrapper = await mountChallenge();

      await byTestId(wrapper, 'mfa-cancel').trigger('click');

      expect(mockLogout).toHaveBeenCalledWith('/signin');
    });
  });

  // -------------------------------------------------------------------------
  // Billing intent on the two-factor completion body (#4306)
  //
  // Contract: for MFA-gated logins the backend replays billing_redirect on the
  // second-factor completion response, NOT the primary-factor login response.
  // Each factor captures its own completion body — OTP/recovery in useMfa's
  // verifyResponse, passkeys in useWebAuthn's mfaVerifyResponse — and the
  // component hands the right one to the REAL usePostAuthRedirect, so an MFA
  // user lands on the same checkout page as a no-MFA user. bootstrapStore is
  // seeded per-test (app bootstrap is absent in vitest; billing_enabled
  // defaults to false).
  // -------------------------------------------------------------------------

  describe('billing intent from the verify response (#4306)', () => {
    const validIntent = {
      success: 'ok',
      billing_redirect: { product: 'identity_plus_v1', interval: 'year', valid: true },
    };

    const verifyOtpWith = (body: OtpVerifySuccess) => {
      mockMfaState.verifyOtp.mockImplementation(async () => {
        mockMfaState.verifyResponse.value = body;
        return true;
      });
    };

    const submitOtp = async (w: VueWrapper) => {
      await w.findComponent({ name: 'OtpCodeInput' }).vm.$emit('complete', '123456');
      await flushPromises();
    };

    it('lands on the org plans page with product and interval preserved', async () => {
      verifyOtpWith(validIntent);
      wrapper = await mountChallenge();

      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.restorePersistedSelection).mockReturnValue({
        extid: 'org_live1',
      } as ReturnType<typeof orgStore.restorePersistedSelection>);

      await submitOtp(wrapper);

      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).toHaveBeenCalledWith(true);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_live1/plans',
        query: { product: 'identity_plus_v1', interval: 'year' },
      });
    });

    it('webauthn completion carries its OWN verify body into the redirect', async () => {
      // The passkey factor gets the same replayed billing_redirect on its
      // /auth/webauthn-auth completion; useWebAuthn keeps it in
      // mfaVerifyResponse, and the component must feed THAT (not useMfa's,
      // which stays null for this factor) into navigateAfterAuth. Without it
      // the intent would depend on the route query surviving the MFA hop.
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      mockWebAuthnState.verifyWebAuthnMfa.mockImplementation(async () => {
        mockWebAuthnState.mfaVerifyResponse.value = validIntent;
        return true;
      });
      wrapper = await mountChallenge();

      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.restorePersistedSelection).mockReturnValue({
        extid: 'org_live1',
      } as ReturnType<typeof orgStore.restorePersistedSelection>);

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      // useMfa never sees the passkey completion — this is the point.
      expect(mockMfaState.verifyResponse.value).toBeNull();
      const authStore = useAuthStore();
      expect(authStore.setAuthenticated).toHaveBeenCalledWith(true);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_live1/plans',
        query: { product: 'identity_plus_v1', interval: 'year' },
      });
    });

    it('webauthn completion with no body still falls back to the query tier', async () => {
      // Older backends emit no billing_redirect on the two-factor completion;
      // the forwarded product/interval pair remains the safety net.
      mockMfaState.fetchMfaStatus.mockResolvedValue(webauthnOnly());
      mockRoute.query = { product: 'identity_plus_v1', interval: 'monthly' };
      wrapper = await mountChallenge();

      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.restorePersistedSelection).mockReturnValue({
        extid: 'org_live1',
      } as ReturnType<typeof orgStore.restorePersistedSelection>);

      await byTestId(wrapper, 'mfa-verify-webauthn-submit').trigger('click');
      await flushPromises();

      expect(mockWebAuthnState.mfaVerifyResponse.value).toBeNull();
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_live1/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });

    it('keeps the billing-disabled gate: falls back to the validated ?redirect', async () => {
      // billing_enabled stays at its default (false) — self-hosted installs.
      verifyOtpWith(validIntent);
      mockRoute.query = { redirect: '/dashboard' };
      wrapper = await mountChallenge();

      await submitOtp(wrapper);

      expect(routerPushMock).toHaveBeenCalledWith('/dashboard');
    });

    it('ignores a billing_redirect the backend marked invalid and goes to /', async () => {
      verifyOtpWith({
        success: 'ok',
        billing_redirect: { product: 'bogus_plan', interval: 'year', valid: false },
      });
      wrapper = await mountChallenge();
      useBootstrapStore().billing_enabled = true;

      await submitOtp(wrapper);

      expect(routerPushMock).toHaveBeenCalledWith('/');
    });
  });
});
