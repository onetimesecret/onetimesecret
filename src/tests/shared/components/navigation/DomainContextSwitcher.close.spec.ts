// src/tests/shared/components/navigation/DomainContextSwitcher.close.spec.ts

/**
 * End-to-end close-behaviour regression for the Domain Context Switcher.
 *
 * Unlike DomainContextSwitcher.spec.ts, this suite deliberately uses the REAL
 * @headlessui/vue Menu so it exercises the actual open/close state machine.
 * The mocked suite can only assert "the handler called close()"; it would keep
 * passing even if the real dropdown stopped dismissing. This suite drives the
 * genuine user flow — open the menu, click, assert the panel is gone — so a
 * regression of the "dropdown stays open after navigation" bug (the gear icon's
 * stopPropagation suppressing HeadlessUI's built-in close) would fail here.
 *
 * Only the component's data dependencies are stubbed; HeadlessUI is real.
 */

import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, reactive, ref } from 'vue';
import DomainContextSwitcher from '@/shared/components/navigation/DomainContextSwitcher.vue';

// NOTE: no vi.mock('@headlessui/vue') here — that is the whole point.

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class', 'ariaLabel'],
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const mockPush = vi.fn();
const mockRoute = reactive<{ meta: Record<string, unknown>; params: Record<string, unknown>; matched: unknown[] }>({
  meta: {},
  params: {},
  matched: [],
});
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush }),
}));

const mockCurrentOrganization = ref<{ current_user_role: string; extid?: string } | null>({
  current_user_role: 'owner',
  extid: 'org1',
});
const mockOrgStore = reactive({ currentOrganization: mockCurrentOrganization });
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => mockOrgStore,
}));

const mockBillingEnabled = ref(false);
const mockBootstrapStore = reactive({ billing_enabled: mockBillingEnabled });
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => mockBootstrapStore,
}));

const mockAvailableDomains = ref<string[]>(['acme.example.com', 'canonical.example.com']);
const mockGetExtidByDomain = vi.fn((domain: string) =>
  domain === 'acme.example.com' ? 'cd1' : undefined
);
const mockCurrentContext = ref({
  domain: 'canonical.example.com',
  displayName: 'canonical.example.com',
  isCanonical: true,
  extid: undefined as string | undefined,
});
const mockIsContextActive = ref(true);
vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: () => ({
    currentContext: mockCurrentContext,
    availableDomains: mockAvailableDomains,
    isContextActive: mockIsContextActive,
    setContext: vi.fn(),
    getDomainDisplayName: (domain: string) => domain,
    getExtidByDomain: mockGetExtidByDomain,
    setContextByExtid: vi.fn(),
    initialized: Promise.resolve(),
  }),
}));

const dropdown = (w: VueWrapper) =>
  w.find('[data-testid="domain-context-switcher-dropdown"]');

async function openMenu(w: VueWrapper) {
  await w.get('[data-testid="domain-context-switcher-trigger"]').trigger('click');
  await nextTick();
  await flushPromises();
  expect(dropdown(w).exists()).toBe(true);
}

describe('DomainContextSwitcher real-HeadlessUI close behaviour', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.meta = {};
    mockRoute.params = {};
    mockRoute.matched = [];
    mockCurrentOrganization.value = { current_user_role: 'owner', extid: 'org1' };
    mockBillingEnabled.value = false;
    mockAvailableDomains.value = ['acme.example.com', 'canonical.example.com'];
    mockIsContextActive.value = true;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('closes the dropdown when the gear/config icon is clicked (the reported bug)', async () => {
    wrapper = mount(DomainContextSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper
      .get('[aria-label="web.domains.domain_settings"]')
      .trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/cd1');
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('closes the dropdown when a domain row is selected', async () => {
    wrapper = mount(DomainContextSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    // Select the row by its stable test id (extid 'cd1' for acme.example.com)
    // rather than substring-matching the rendered domain text.
    await wrapper.get('[data-testid="domain-menu-item-cd1"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('closes the dropdown when the header [+] icon is clicked', async () => {
    wrapper = mount(DomainContextSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="domain-context-add-icon"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/add');
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('closes the dropdown when the "Manage Domains" footer link is clicked', async () => {
    // Owner + at least one custom domain renders the "Manage Domains" link.
    wrapper = mount(DomainContextSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="domain-context-manage-link"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/org/org1');
    expect(dropdown(wrapper).exists()).toBe(false);
  });

  it('closes the dropdown when the "Add Domain" footer link is clicked (no custom domains)', async () => {
    // With no custom domains the footer shows the prominent "Add Domain" link.
    mockAvailableDomains.value = ['canonical.example.com'];

    wrapper = mount(DomainContextSwitcher, { attachTo: document.body });
    await openMenu(wrapper);

    await wrapper.get('[data-testid="domain-context-add-link"]').trigger('click');
    await nextTick();
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/add');
    expect(dropdown(wrapper).exists()).toBe(false);
  });
});
