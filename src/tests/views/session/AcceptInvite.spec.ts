// src/tests/views/session/AcceptInvite.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import AcceptInvite from '@/apps/session/views/AcceptInvite.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { getGlobalAxiosMock, createSharedApiInstance } from '../../setup-stores';

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

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        COMMON: {
          processing: 'Processing...',
        },
        organizations: {
          invitations: {
            invitation_details: 'Invitation Details',
            you_are_invited: "You've been invited to join",
            email_address: 'Email Address',
            invited_as: 'Role',
            invited_by: 'Invited by',
            expires_at: 'Expires',
            must_sign_in: 'Please sign in to accept this invitation',
            accept_invitation: 'Accept Invitation',
            decline_invitation: 'Decline Invitation',
            accept_success: 'Invitation accepted successfully',
            accept_error: 'Failed to accept invitation',
            decline_success: 'Invitation declined',
            decline_error: 'Failed to decline invitation',
            expired_message: 'This invitation has expired',
            invalid_token: 'Invalid or expired invitation',
            loading_invitation: 'Loading invitation details',
            roles: {
              member: 'Member',
              admin: 'Admin',
            },
          },
        },
      },
    },
  },
});

describe('AcceptInvite', () => {
  let pinia: ReturnType<typeof createPinia>;
  let authStore: ReturnType<typeof useAuthStore>;
  let router: ReturnType<typeof createRouter>;

  const mockInvitation = {
    organization_name: 'Acme Corp',
    organization_id: 'org-123',
    email: 'invitee@example.com',
    role: 'member',
    invited_by_email: 'admin@acme.com',
    expires_at: Math.floor(Date.now() / 1000) + 604800, // 7 days from now
    status: 'pending',
  };

  const mockExpiredInvitation = {
    ...mockInvitation,
    status: 'expired',
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
        { path: '/org', name: 'Organizations', component: { template: '<div></div>' } },
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
      expect(wrapper.text()).toContain('invitee@example.com');
      expect(wrapper.text()).toContain('admin@acme.com');
    });

    it('displays member role correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Member');
    });

    it('displays admin role correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: { ...mockInvitation, role: 'admin' },
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Admin');
    });

    it('shows accept and decline buttons for pending invitation', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      const buttons = wrapper.findAll('button');
      const buttonTexts = buttons.map((b) => b.text());

      expect(buttonTexts.some((t) => t.includes('Accept'))).toBe(true);
      expect(buttonTexts.some((t) => t.includes('Decline'))).toBe(true);
    });
  });

  describe('Expired Invitation', () => {
    it('shows error message for expired invitation', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockExpiredInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('This invitation has expired');
    });
  });

  describe('Invalid Token', () => {
    it('shows error message for invalid token', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/invalid-token').reply(404, {
        error: 'Not found',
      });

      const wrapper = await mountComponent('invalid-token');

      expect(wrapper.text()).toContain('Invalid or expired invitation');
    });

    it('shows error message for API errors', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/error-token').reply(500, {
        error: 'Server error',
      });

      const wrapper = await mountComponent('error-token');

      expect(wrapper.text()).toContain('Invalid or expired invitation');
    });
  });

  describe('Unauthenticated User', () => {
    it('shows sign-in notice when user is not authenticated', async () => {
      authStore.$patch({ cust: null });
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Please sign in to accept this invitation');
    });

    it('redirects to sign in when accept is clicked by unauthenticated user', async () => {
      authStore.$patch({ cust: null });
      const routerPushSpy = vi.spyOn(router, 'push');
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();
      const acceptButton = wrapper.findAll('button').find((b) => b.text().includes('Accept'));
      await acceptButton?.trigger('click');

      expect(routerPushSpy).toHaveBeenCalledWith({
        name: 'Sign In',
        query: { redirect: '/invite/test-token-123' },
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
      const acceptButton = wrapper.findAll('button').find((b) => b.text().includes('Accept'));
      await acceptButton?.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('Invitation accepted successfully');
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
      const acceptButton = wrapper.findAll('button').find((b) => b.text().includes('Accept'));
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
      const declineButton = wrapper.findAll('button').find((b) => b.text().includes('Decline'));
      await declineButton?.trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('Invitation declined');
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
      const declineButton = wrapper.findAll('button').find((b) => b.text().includes('Decline'));
      await declineButton?.trigger('click');
      await flushPromises();

      expect(wrapper.find('.error-alert').exists()).toBe(true);
    });
  });

  describe('UI Layout', () => {
    it('renders invitation header correctly', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      expect(wrapper.find('h1').text()).toContain('Invitation Details');
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
    it('has accessible buttons', async () => {
      const axiosMock = getGlobalAxiosMock();
      axiosMock.onGet('/api/invite/test-token-123').reply(200, {
        record: mockInvitation,
      });

      const wrapper = await mountComponent();

      const buttons = wrapper.findAll('button');
      expect(buttons.length).toBeGreaterThan(0);

      // Check buttons have proper type attribute
      buttons.forEach((button) => {
        expect(button.attributes('type')).toBe('button');
      });
    });
  });
});
