// src/tests/views/session/AcceptInvite.spec.ts

import AcceptInvite from '@/apps/session/views/AcceptInvite.vue';
import InviteSignUpForm from '@/apps/session/components/InviteSignUpForm.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { flushPromises, mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createMemoryHistory, createRouter } from 'vue-router';
import { createTestI18n } from '@tests/setup';
import { createSharedApiInstance, getGlobalAxiosMock } from '../../setup-stores';

// Mock components
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="mock-icon"></span>',
    props: ['collection', 'name'],
  },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template:
      '<div class="form-alerts" :class="{ \'error-alert\': error, \'success-alert\': success }">{{ error || success }}</div>',
    props: ['error', 'success'],
  },
}));

// Stubbed so the restricted-host assertions can read the routing props
// directly. The real button POSTs a form to /auth/sso/:provider, which jsdom
// cannot follow and which would tell us nothing about this component.
vi.mock('@/apps/session/components/SsoButton.vue', () => ({
  default: {
    name: 'SsoButton',
    template: '<button type="button" data-testid="sso-button"></button>',
    props: ['routeName', 'displayName', 'redirect'],
  },
}));

const i18n = createTestI18n();

describe('AcceptInvite', () => {
  let pinia: ReturnType<typeof createPinia>;
  let authStore: ReturnType<typeof useAuthStore>;
  let router: ReturnType<typeof createRouter>;

  const mockInvitation = {
    organization_name: 'Acme Corp',
    organization_id: 'on%orgacme123', // ExtId format for organization reference
    email: 'invitee@example.com',
    role: 'member',
    // Backend emits a masked inviter value, never the raw email (AZ7)
    invited_by: 'a***@a***.com',
    expires_at: Math.floor(Date.now() / 1000) + 604800, // 7 days from now
    status: 'pending',
    actionable: true, // Invitation can be acted upon
  };

  const mockExpiredInvitation = {
    ...mockInvitation,
    status: 'expired',
    actionable: false, // Expired invitations cannot be acted upon
  };

  /**
   * The host's resolved sign-in restriction (ADR-024 A2), as GET
   * /api/invite/:token now reports it. Server-owned and read verbatim — the
   * component never re-derives it, so these fixtures are the only input that
   * drives the restricted states.
   */
  const unrestricted = { state: 'unrestricted', restrict_to: null, source: 'global' };
  const restrictedTo = (method: string, source = 'global') => ({
    state: 'restricted',
    restrict_to: method,
    source,
  });
  const unavailable = (method: string | null, source = 'global') => ({
    state: 'unavailable',
    restrict_to: method,
    source,
  });

  /** The SSO entry the server leaves in auth_methods on a custom-domain host. */
  const ssoAuthMethod = {
    type: 'sso',
    enabled: true,
    provider_type: 'oidc',
    display_name: 'Acme SSO',
    platform_route_name: 'oidc',
  };

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    authStore = useAuthStore();

    // Reset axios mock
    const axiosMock = getGlobalAxiosMock();
    axiosMock.reset();

    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/invite/:token', name: 'Accept Invite', component: AcceptInvite },
        { path: '/signin', name: 'Sign In', component: { template: '<div></div>' } },
        { path: '/orgs', name: 'Organizations', component: { template: '<div></div>' } },
        { path: '/', name: 'Home', component: { template: '<div></div>' } },
      ],
    });

    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
    getGlobalAxiosMock().reset();
  });

  const mountComponent = async (token = 'test-token-123') => {
    await router.push(`/invite/${token}`);
    await router.isReady();

    const wrapper = mount(AcceptInvite, {
      global: {
        plugins: [i18n, pinia, router],
        provide: {
          api: createSharedApiInstance(),
        },
      },
    });
    await flushPromises();
    return wrapper;
  };

  describe('Invitation Display', () => {
    it('displays invitation details correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Acme Corp');
      // Invitee email is in a readonly input value, not text content
      const emailInput = wrapper.find('[data-testid="invite-signup-email-input"]');
      expect(emailInput.exists()).toBe(true);
      expect(emailInput.attributes('value')).toBe('invitee@example.com');
      expect(wrapper.text()).toContain('a***@a***.com');
    });

    it('displays member role correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('web.organizations.invitations.roles.member');
    });

    it('displays admin role correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: { ...mockInvitation, role: 'admin' },
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('web.organizations.invitations.roles.admin');
    });

    it('shows accept and decline buttons for authenticated user with pending invitation', async () => {
      // Must be authenticated to see direct Accept/Decline buttons
      authStore.$patch({
        isAuthenticated: true,
        cust: {
          custid: 'cust-123',
          email: 'invitee@example.com',
          verified: true,
          created: new Date(),
          updated: new Date(),
        },
      });

      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      const buttons = wrapper.findAll('button');
      const buttonTexts = buttons.map((b) => b.text());

      expect(buttonTexts.some((t) => t.includes('web.organizations.invitations.accept_invitation'))).toBe(true);
      expect(buttonTexts.some((t) => t.includes('web.organizations.invitations.decline_invitation'))).toBe(true);
    });
  });

  describe('Expired Invitation', () => {
    it('shows error message for expired invitation', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockExpiredInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('web.organizations.invitations.expired_message');
    });
  });

  describe('Invalid Token', () => {
    it('shows error message for invalid token', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/invalid-token').reply(404, {
        error: 'Not found',
      });

      const wrapper = await mountComponent('invalid-token');
      // Multiple flushPromises to allow all async cycles to complete
      await flushPromises();
      await flushPromises();

      // Component should show invalid state with error message
      expect(wrapper.find('[data-testid="invite-invalid"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('web.organizations.invitations.invalid_token');
    });

    it('shows error message for API errors', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/error-token').reply(500, {
        error: 'Server error',
      });

      const wrapper = await mountComponent('error-token');
      // Multiple flushPromises to allow all async cycles to complete
      await flushPromises();
      await flushPromises();

      // Component should show invalid state with error message
      expect(wrapper.find('[data-testid="invite-invalid"]').exists()).toBe(true);
      expect(wrapper.text()).toContain('web.organizations.invitations.invalid_token');
    });
  });

  describe('Unauthenticated User', () => {
    it('shows signup form by default when user is not authenticated', async () => {
      // The show endpoint deliberately carries no account_exists signal (AZ7),
      // so unauthenticated users always start in the signup flow.
      authStore.$patch({ cust: null });
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      // Component should show the signup_required state testid
      expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);
    });

    it('switches to sign-in notice after signup reports signup unavailable', async () => {
      authStore.$patch({ cust: null });
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();
      expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);

      // The signup attempt comes back with the generic signup_unavailable
      // error (#3856) and the form emits signin-required; the state machine
      // flips to signin_required.
      wrapper.findComponent(InviteSignUpForm).vm.$emit('signin-required');
      await flushPromises();

      expect(wrapper.text()).toContain('web.organizations.invitations.must_sign_in');
    });
  });

  /**
   * ADR-024 A11 (#4139). POST /api/invite/:token/signup 404s and creates
   * nothing on a host that does not permit password. These cover the UX half:
   * the page must render the method the host actually offers rather than a
   * password form whose submit dies.
   */
  describe('Host sign-in restriction (ADR-024 A11)', () => {
    beforeEach(() => {
      authStore.$patch({ isAuthenticated: false, cust: null });
    });

    const replyWith = (record: Record<string, unknown>, token = 'test-token-123') => {
      getGlobalAxiosMock().onGet(`/api/invite/${token}`).reply(200, { record });
    };

    describe('host permits password (unchanged behaviour)', () => {
      it('renders the signup form when the host is unrestricted', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unrestricted });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="invite-signin-unavailable"]').exists()).toBe(false);
      });

      it('renders the signup form when the host is restricted to password', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: restrictedTo('password') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
      });

      it('renders the signup form when the field is absent (pre-#4139 backend)', async () => {
        // Absent is treated as unrestricted on purpose: failing closed on a
        // missing field would take the invite page dark on every older install.
        replyWith(mockInvitation);

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
      });
    });

    describe('host restricted to sso', () => {
      it('explains SSO and routes to the provider from auth_methods', async () => {
        replyWith({
          ...mockInvitation,
          effective_restrict_to: restrictedTo('sso', 'domain'),
          auth_methods: [ssoAuthMethod],
        });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(true);
        // The dead password form must be gone, not merely supplemented.
        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="invite-signup-email-input"]').exists()).toBe(false);
        expect(wrapper.text()).toContain('web.organizations.invitations.restricted_sso_body');

        const sso = wrapper.findComponent({ name: 'SsoButton' });
        expect(sso.exists()).toBe(true);
        expect(sso.props('routeName')).toBe('oidc');
        expect(sso.props('displayName')).toBe('Acme SSO');
        // Comes back here to accept — A11's flow is sign in, then join.
        expect(sso.props('redirect')).toBe('/invite/test-token-123');
      });

      it('does not imply the invitation was lost', async () => {
        replyWith({
          ...mockInvitation,
          effective_restrict_to: restrictedTo('sso'),
          auth_methods: [ssoAuthMethod],
        });

        const wrapper = await mountComponent();

        expect(wrapper.text()).toContain('web.organizations.invitations.invitation_stays_pending');
      });

      it('falls back to the sign-in page when no auth_methods entry is present', async () => {
        // Canonical host: auth_methods is custom-domain-only, so the page has
        // no provider route to name but the restriction is still reported.
        replyWith({ ...mockInvitation, effective_restrict_to: restrictedTo('sso') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(true);
        expect(wrapper.findComponent({ name: 'SsoButton' }).exists()).toBe(false);

        // router-link renders as router-link-stub here, so `to` is the only
        // assertable surface — hence the string path in the component.
        const link = wrapper.find('[data-testid="restricted-signin-link"]');
        expect(link.exists()).toBe(true);
        expect(link.attributes('to')).toBe('/signin?redirect=%2Finvite%2Ftest-token-123');
      });
    });

    describe('host restricted to a method this page cannot complete', () => {
      it('names the method and points at the invitation email link', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: restrictedTo('email_auth') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(false);
        expect(wrapper.text()).toContain('web.organizations.invitations.restricted_host_body');
        expect(wrapper.find('[data-testid="restricted-use-email-link"]').exists()).toBe(true);
        // No SSO affordance for a non-SSO restriction.
        expect(wrapper.findComponent({ name: 'SsoButton' }).exists()).toBe(false);
        expect(wrapper.find('[data-testid="restricted-signin-link"]').exists()).toBe(false);
      });

      it('still hides the form when the method is unrecognized', async () => {
        // The schema degrades an unknown method to null while `state` keeps
        // carrying the truth. A method we cannot name is still one we cannot
        // offer — treating it as unrestricted would put the password form back
        // in front of the A11 gate.
        replyWith({ ...mockInvitation, effective_restrict_to: restrictedTo('passkey_v2') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(false);
        expect(wrapper.text()).toContain(
          'web.organizations.invitations.restricted_host_unknown_body'
        );
      });
    });

    describe('sign-in unavailable on this host', () => {
      it('reports an honest message rather than a form or a blank screen', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unavailable('sso') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-signin-unavailable"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
        expect(wrapper.text()).toContain('web.organizations.invitations.signin_unavailable_body');
        // Still tells them the invitation survives.
        expect(wrapper.text()).toContain('web.organizations.invitations.invitation_stays_pending');
      });

      it('names the conflict rather than showing either side as the winner', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unavailable('sso', 'conflict') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-signin-unavailable"]').exists()).toBe(true);
        expect(wrapper.text()).toContain(
          'web.organizations.invitations.signin_unavailable_conflict_body'
        );
      });

      it('falls back to unnamed copy when the method is unrecognized', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unavailable('passkey_v2') });

        const wrapper = await mountComponent();

        expect(wrapper.text()).toContain(
          'web.organizations.invitations.signin_unavailable_unknown_body'
        );
      });
    });

    describe('restriction never masks a token failure', () => {
      it('renders the bad-token error, not a restriction, for an unknown token', async () => {
        // A genuine 404 from GET must still read as a bad token. It cannot be
        // confused with the A11 signup 404: the restriction is known BEFORE
        // any form renders, so `invalid` keeps sole ownership of token failures.
        getGlobalAxiosMock().onGet('/api/invite/invalid-token').reply(404, { error: 'Not found' });

        const wrapper = await mountComponent('invalid-token');
        await flushPromises();

        expect(wrapper.find('[data-testid="invite-invalid"]').exists()).toBe(true);
        expect(wrapper.text()).toContain('web.organizations.invitations.invalid_token');
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="invite-signin-unavailable"]').exists()).toBe(false);
      });

      it('reports an expired invitation as expired even on a restricted host', async () => {
        // Ordering guard: non-actionable is checked before the restriction, so
        // an expired token on an SSO-only host reads as expired.
        replyWith({
          ...mockExpiredInvitation,
          effective_restrict_to: restrictedTo('sso'),
          auth_methods: [ssoAuthMethod],
        });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-invalid"]').exists()).toBe(true);
        expect(wrapper.text()).toContain('web.organizations.invitations.expired_message');
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
      });

      it('reports an unavailable host as unavailable, not as a bad token', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unavailable('sso') });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-invalid"]').exists()).toBe(false);
        expect(wrapper.text()).not.toContain('web.organizations.invitations.invalid_token');
      });
    });

    describe('authenticated invitee', () => {
      it('can still accept on a restricted host', async () => {
        // POST /:token/accept is deliberately ungated (account-scoped, A7), so
        // the restriction is spent once a session exists. This is what lets
        // A11's flow terminate: SSO signs them in, they return here, they join.
        authStore.$patch({
          isAuthenticated: true,
          cust: {
            custid: 'cust-123',
            email: 'invitee@example.com',
            verified: true,
            created: new Date(),
            updated: new Date(),
          },
        });
        replyWith({
          ...mockInvitation,
          effective_restrict_to: restrictedTo('sso'),
          auth_methods: [ssoAuthMethod],
        });

        const wrapper = await mountComponent();

        expect(wrapper.find('[data-testid="invite-direct-accept"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="accept-invitation-btn"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="invite-restricted-host"]').exists()).toBe(false);
      });
    });

    describe('accessibility', () => {
      it('announces the restriction rather than relying on color', async () => {
        replyWith({
          ...mockInvitation,
          effective_restrict_to: restrictedTo('sso'),
          auth_methods: [ssoAuthMethod],
        });

        const wrapper = await mountComponent();

        const notice = wrapper.find('[data-testid="restricted-host-notice"]');
        expect(notice.attributes('role')).toBe('status');
        expect(notice.attributes('aria-live')).toBe('polite');
        // The meaning is in the text, not the hue.
        expect(notice.text()).toContain('web.organizations.invitations.restricted_host_title');
      });

      it('announces the unavailable dead end assertively', async () => {
        replyWith({ ...mockInvitation, effective_restrict_to: unavailable('sso') });

        const wrapper = await mountComponent();

        const notice = wrapper.find('[data-testid="signin-unavailable-notice"]');
        expect(notice.attributes('role')).toBe('alert');
        expect(notice.text()).toContain('web.organizations.invitations.signin_unavailable_title');
      });
    });
  });

  describe('Authenticated User - Accept Flow', () => {
    beforeEach(() => {
      authStore.$patch({
        isAuthenticated: true,
        cust: {
          custid: 'cust-123',
          email: 'invitee@example.com',
          verified: true,
          created: new Date(),
          updated: new Date(),
        },
      });
    });

    it('accepts invitation successfully', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });
      axiosMock.onPost('/api/invite/test-token-123/accept').reply(200, {});

      const wrapper = await mountComponent();
      const acceptButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.organizations.invitations.accept_invitation'));
      await acceptButton?.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('web.organizations.invitations.accept_success');
      // Action row must be torn down once accepted — prevents flicker during redirect delay
      expect(wrapper.find('[data-testid="accept-invitation-btn"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="decline-invitation-btn"]').exists()).toBe(false);
    });

    it('shows error when accept fails', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });
      axiosMock.onPost('/api/invite/test-token-123/accept').reply(400, {
        error: 'Email mismatch',
      });

      const wrapper = await mountComponent();
      const acceptButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.organizations.invitations.accept_invitation'));
      await acceptButton?.trigger('click');
      await flushPromises();

      expect(wrapper.find('.error-alert').exists()).toBe(true);
    });
  });

  describe('Authenticated User - Decline Flow', () => {
    beforeEach(() => {
      authStore.$patch({
        isAuthenticated: true,
        cust: {
          custid: 'cust-123',
          email: 'invitee@example.com',
          verified: true,
          created: new Date(),
          updated: new Date(),
        },
      });
    });

    it('declines invitation successfully', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });
      axiosMock.onPost('/api/invite/test-token-123/decline').reply(200, {});

      const wrapper = await mountComponent();
      const declineButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.organizations.invitations.decline_invitation'));
      await declineButton?.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('web.organizations.invitations.decline_success');
      // Action row must be torn down once declined — prevents flicker during redirect delay
      expect(wrapper.find('[data-testid="accept-invitation-btn"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="decline-invitation-btn"]').exists()).toBe(false);
    });

    it('shows error when decline fails', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });
      axiosMock.onPost('/api/invite/test-token-123/decline').reply(500, {
        error: 'Server error',
      });

      const wrapper = await mountComponent();
      const declineButton = wrapper
        .findAll('button')
        .find((b) => b.text().includes('web.organizations.invitations.decline_invitation'));
      await declineButton?.trigger('click');
      await flushPromises();

      expect(wrapper.find('.error-alert').exists()).toBe(true);
    });
  });

  describe('UI Layout', () => {
    it('renders invitation header correctly for authenticated user', async () => {
      // Authenticated user sees "Invitation Details" header in direct_accept state
      authStore.$patch({
        isAuthenticated: true,
        cust: {
          custid: 'cust-123',
          email: 'invitee@example.com',
          verified: true,
          created: new Date(),
          updated: new Date(),
        },
      });

      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.find('h1').text()).toContain('web.organizations.invitations.invitation_details');
    });

    it('has proper container styling', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.find('.max-w-md').exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('has accessible buttons with type attributes', async () => {
      // Use authenticated user to see direct Accept/Decline buttons (type="button")
      authStore.$patch({
        isAuthenticated: true,
        cust: {
          custid: 'cust-123',
          email: 'invitee@example.com',
          verified: true,
          created: new Date(),
          updated: new Date(),
        },
      });

      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      const buttons = wrapper.findAll('button');
      expect(buttons.length).toBeGreaterThan(0);

      // Check all buttons have explicit type attribute (either "button" or "submit")
      buttons.forEach((button) => {
        const type = button.attributes('type');
        expect(['button', 'submit']).toContain(type);
      });
    });
  });
});
