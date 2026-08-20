// src/tests/apps/secret/conceal/IncomingForm.spec.ts
//
// Regression contract for the custom-domain /incoming page header.
//
// The top masthead is suppressed on custom domains (guards.routes.ts), so the
// page body must own the brand logo. Two bugs this locks against:
//   1. Duplicate header — when a logo was configured, the guard toggled the
//      masthead ON, so its logo+title+subtitle rendered ABOVE IncomingForm's
//      own title+subtitle. The page must show exactly one title block.
//   2. Missing logo — the logo previously came only from the masthead, so
//      suppressing the masthead must not lose it: the body renders it when a
//      logo is configured, and hides it (no placeholder) when none is.

import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(() => null),
  updateBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

vi.mock('@/apps/secret/components/incoming/IncomingSecretFormBody.vue', () => ({
  default: {
    name: 'IncomingSecretFormBody',
    template: '<div data-testid="stub-incoming-form-body" />',
  },
}));

const loadConfigMock = vi.fn();
const incomingSecretState = { isFeatureEnabled: ref(true) };

vi.mock('@/shared/composables/useIncomingSecret', () => ({
  useIncomingSecret: () => ({
    isFeatureEnabled: incomingSecretState.isFeatureEnabled,
    loadConfig: loadConfigMock,
  }),
}));

const incomingState = { isEntitlementBlocked: false, configError: null as string | null };

vi.mock('@/shared/stores/incomingStore', () => ({
  useIncomingStore: () => ({
    get isEntitlementBlocked() {
      return incomingState.isEntitlementBlocked;
    },
    get configError() {
      return incomingState.configError;
    },
  }),
}));

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import IncomingForm from '@/apps/secret/conceal/IncomingForm.vue';

const LOGO_URL = 'https://cdn.example.com/imagine/ext123/logo.png';
const DARK_LOGO_URL = 'https://cdn.example.com/imagine/ext123/logo-dark.png';

async function mountIncoming(
  domainLogo: string | null,
  domainBranding: Record<string, unknown> | null = null
) {
  const bootstrap = useBootstrapStore();
  bootstrap.$patch({
    domain_strategy: 'custom',
    domain_logo: domainLogo,
    domain_branding: domainBranding,
  });
  const wrapper = mount(IncomingForm, {
    global: { plugins: [createTestI18n()] },
  });
  await flushPromises();
  return wrapper;
}

describe('IncomingForm custom-domain header', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    loadConfigMock.mockReset().mockResolvedValue(undefined);
    incomingSecretState.isFeatureEnabled = ref(true);
    incomingState.isEntitlementBlocked = false;
    incomingState.configError = null;
  });

  it('renders exactly one title block (no duplicate masthead header)', async () => {
    const wrapper = await mountIncoming(LOGO_URL);

    expect(wrapper.find('[data-testid="stub-incoming-form-body"]').exists()).toBe(true);
    expect(wrapper.findAll('h1')).toHaveLength(1);
    expect(wrapper.find('h1').text()).toContain('incoming.page_title');
  });

  it('renders the brand logo in the page body when a logo is configured', async () => {
    const wrapper = await mountIncoming(LOGO_URL);

    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.attributes('src')).toBe(LOGO_URL);
  });

  it('renders no logo image (and no placeholder) when no logo is configured', async () => {
    const wrapper = await mountIncoming(null);

    expect(wrapper.find('img').exists()).toBe(false);
    // Title still renders — the no-logo page is title + subtitle + form.
    expect(wrapper.findAll('h1')).toHaveLength(1);
  });

  it('renders the tenant dark logo variant (BrandMark dark swap) when configured', async () => {
    const wrapper = await mountIncoming(LOGO_URL, { logo_dark_url: DARK_LOGO_URL });

    const dark = wrapper.find('[data-testid="logo-dark"]');
    expect(dark.exists()).toBe(true);
    expect(dark.attributes('src')).toBe(DARK_LOGO_URL);
    // The light logo is swapped out in dark mode via BrandMark.
    expect(wrapper.findAll('img')[0].classes()).toContain('dark:hidden');
  });

  it('renders only the light logo when no dark variant is configured', async () => {
    const wrapper = await mountIncoming(LOGO_URL);

    expect(wrapper.find('[data-testid="logo-dark"]').exists()).toBe(false);
    expect(wrapper.findAll('img')).toHaveLength(1);
  });
});
