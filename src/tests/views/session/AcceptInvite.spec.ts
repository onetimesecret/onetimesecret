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

    it('switches to sign-in notice after signup reports an existing account', async () => {
      authStore.$patch({ cust: null });
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();
      expect(wrapper.find('[data-testid="invite-signup-required"]').exists()).toBe(true);

      // The signup form discovers the existing account via the signup attempt
      // and emits account-exists; the state machine flips to signin_required.
      wrapper.findComponent(InviteSignUpForm).vm.$emit('account-exists');
      await flushPromises();

      expect(wrapper.text()).toContain('web.organizations.invitations.must_sign_in');
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
