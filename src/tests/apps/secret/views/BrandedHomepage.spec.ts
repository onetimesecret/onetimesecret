// src/tests/apps/secret/views/BrandedHomepage.spec.ts
//
// Render-switch contract for the branded custom-domain homepage:
//   - private (enabled: false)            -> disabled-homepage dispatcher, no form
//   - create mode (enabled, create)       -> SecretForm
//   - incoming mode (enabled, incoming)   -> IncomingSecretFormBody once the
//                                            runtime config confirms it
//   - incoming mode, runtime unavailable  -> disabled-homepage dispatcher (NEVER
//                                            upgrade/billing or misconfiguration
//                                            copy on the branded front door)
//
// The private/degraded branch delegates presentation to the disabled-homepage
// variant dispatcher (DisabledHomepage.vue), stubbed here so these tests stay
// focused on BrandedHomepage's public-vs-private switching. The variant chain
// itself is covered in useDisabledConfig.spec.ts.

import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { createTestI18n } from '@tests/setup';
import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(() => null),
  updateBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

vi.mock('@/apps/secret/components/form/SecretForm.vue', () => ({
  default: {
    name: 'SecretForm',
    template: '<div data-testid="stub-secret-form" />',
  },
}));

vi.mock('@/apps/secret/components/incoming/IncomingSecretFormBody.vue', () => ({
  default: {
    name: 'IncomingSecretFormBody',
    template: '<div data-testid="stub-incoming-form-body" />',
  },
}));

vi.mock('@/apps/secret/views/DisabledHomepage.vue', () => ({
  default: {
    name: 'DisabledHomepage',
    template: '<div data-testid="stub-disabled-homepage" />',
  },
}));

const loadConfigMock = vi.fn();
const incomingState: {
  isEntitlementBlocked: boolean;
  configError: string | null;
  isFeatureEnabled: boolean;
  recipients: Array<{ digest: string; display_name: string }>;
} = {
  isEntitlementBlocked: false,
  configError: null,
  isFeatureEnabled: true,
  recipients: [{ digest: 'abc', display_name: 'Security' }],
};

vi.mock('@/shared/stores/incomingStore', () => ({
  useIncomingStore: () => ({
    loadConfig: loadConfigMock,
    get isEntitlementBlocked() {
      return incomingState.isEntitlementBlocked;
    },
    get configError() {
      return incomingState.configError;
    },
    get isFeatureEnabled() {
      return incomingState.isFeatureEnabled;
    },
    get recipients() {
      return incomingState.recipients;
    },
  }),
}));

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import BrandedHomepage from '@/apps/secret/conceal/BrandedHomepage.vue';
import type { HomepageConfigCanonical } from '@/schemas/contracts/custom-domain/homepage-config';

function homepageConfig(overrides: Partial<HomepageConfigCanonical> = {}): HomepageConfigCanonical {
  return {
    domain_id: 'd_123',
    enabled: true,
    secrets_mode: 'create',
    signup_enabled: false,
    signin_enabled: false,
    disabled_homepage_variant: null,
    created_at: 1700000000,
    updated_at: 1700000000,
    ...overrides,
  };
}

async function mountHomepage(config: HomepageConfigCanonical | null) {
  const bootstrap = useBootstrapStore();
  if (config) {
    bootstrap.$patch({ homepage_config: config });
  }
  const wrapper = mount(BrandedHomepage, {
    global: { plugins: [createTestI18n()] },
  });
  await flushPromises();
  return wrapper;
}

describe('BrandedHomepage render switch', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    loadConfigMock.mockReset().mockResolvedValue(undefined);
    incomingState.isEntitlementBlocked = false;
    incomingState.configError = null;
    incomingState.isFeatureEnabled = true;
    incomingState.recipients = [{ digest: 'abc', display_name: 'Security' }];
  });

  it('renders the disabled-homepage dispatcher when the homepage is not public', async () => {
    const wrapper = await mountHomepage(homepageConfig({ enabled: false }));

    expect(wrapper.find('[data-testid="stub-secret-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-disabled-homepage"]').exists()).toBe(true);
    // BrandedHero is suppressed in the private branch — the variant dispatcher
    // owns its own hero, so the branded landing hero must not double up.
    expect(wrapper.findComponent(BrandedHero).exists()).toBe(false);
    expect(loadConfigMock).not.toHaveBeenCalled();
  });

  it('renders the secret creation form in create mode', async () => {
    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'create' }));

    expect(wrapper.find('[data-testid="stub-secret-form"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-disabled-homepage"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.homepage.create_a_secure_link');
    expect(loadConfigMock).not.toHaveBeenCalled();
  });

  it('renders the incoming form in incoming mode once config confirms availability', async () => {
    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'incoming' }));

    expect(loadConfigMock).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="stub-secret-form"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('web.homepage.send_a_secret');
  });

  it('degrades to the disabled-homepage dispatcher when the runtime config is entitlement-blocked', async () => {
    incomingState.isEntitlementBlocked = true;
    incomingState.isFeatureEnabled = false;

    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'incoming' }));

    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-secret-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-disabled-homepage"]').exists()).toBe(true);
    // No upgrade/billing copy for anonymous visitors.
    expect(wrapper.text()).not.toContain('incoming.upgrade_required_title');
    // BrandedHero (and its "Send a secret" headline) is suppressed once the
    // private branch takes over — no marketing copy over a members-only page.
    expect(wrapper.findComponent(BrandedHero).exists()).toBe(false);
    expect(wrapper.text()).not.toContain('web.homepage.send_a_secret');
  });

  it('degrades to the disabled-homepage dispatcher when recipients drift to empty', async () => {
    incomingState.recipients = [];

    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'incoming' }));

    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-disabled-homepage"]').exists()).toBe(true);
  });

  it('degrades to the disabled-homepage dispatcher when the config load fails', async () => {
    loadConfigMock.mockRejectedValue(new Error('network'));
    incomingState.configError = 'network';
    incomingState.isFeatureEnabled = false;

    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'incoming' }));

    expect(wrapper.find('[data-testid="homepage-incoming-form"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="stub-disabled-homepage"]').exists()).toBe(true);
  });

  it('never renders the create form in incoming mode', async () => {
    const wrapper = await mountHomepage(homepageConfig({ secrets_mode: 'incoming' }));

    expect(wrapper.find('[data-testid="stub-secret-form"]').exists()).toBe(false);
  });

  it('renders the headline in the brand heading font', async () => {
    const bootstrap = useBootstrapStore();
    // Patch before mount: identityStore parses domain_branding at creation.
    bootstrap.$patch({
      domain_branding: { heading_font: 'slab', font_family: 'mono' },
    });

    const wrapper = await mountHomepage(homepageConfig());

    expect(wrapper.find('h1').classes()).toContain('font-brand-slab');
  });

  it('falls back to the body font for the headline when heading_font is unset', async () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ domain_branding: { font_family: 'mono' } });

    const wrapper = await mountHomepage(homepageConfig());

    expect(wrapper.find('h1').classes()).toContain('font-mono');
  });
});
