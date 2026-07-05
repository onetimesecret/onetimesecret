// src/tests/shared/components/navigation/DomainContextSwitcher.spec.ts

/**
 * Tests for the Domain Context Switcher's add/manage call-to-action logic.
 *
 * Behaviour under test:
 * - Owner/admin with 0 custom domains  -> prominent "Add Domain" footer link
 *   (no header [+] icon, no "Manage Domains" link).
 * - Owner/admin with >=1 custom domain -> compact header [+] icon AND the
 *   "Manage Domains" footer link (no prominent "Add Domain" link).
 * - Members (cannot manage domains)     -> none of the above.
 *
 * HeadlessUI is stubbed so the dropdown contents always render, independent of
 * the real open/close state machine.
 */

import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import DomainContextSwitcher from '@/shared/components/navigation/DomainContextSwitcher.vue';

// Shared spy for HeadlessUI's Menu `close` slot function so tests can assert the
// dropdown is dismissed on navigation. Hoisted so it is available inside the
// (hoisted) vi.mock factory below.
const { mockClose } = vi.hoisted(() => ({ mockClose: vi.fn() }));

// --- HeadlessUI: render slot content unconditionally -------------------------
vi.mock('@headlessui/vue', () => ({
  Menu: {
    name: 'Menu',
    template: '<div class="menu"><slot :open="false" :close="mockClose" /></div>',
    props: ['as'],
    setup: () => ({ mockClose }),
  },
  MenuButton: {
    name: 'MenuButton',
    template: '<button><slot /></button>',
    props: ['as', 'disabled'],
  },
  MenuItems: {
    name: 'MenuItems',
    template: '<div role="menu"><slot /></div>',
    props: ['as', 'class'],
  },
  MenuItem: {
    name: 'MenuItem',
    template: '<div role="menuitem"><slot :active="false" /></div>',
    props: ['as', 'disabled'],
  },
}));

// --- OIcon: lightweight stub -------------------------------------------------
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class', 'ariaLabel'],
  },
}));

// --- i18n --------------------------------------------------------------------
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

// --- router ------------------------------------------------------------------
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

// --- organization + bootstrap stores ----------------------------------------
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

// --- domain context ----------------------------------------------------------
const mockAvailableDomains = ref<string[]>(['canonical.example.com']);
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

const addLink = (w: VueWrapper) => w.find('[data-testid="domain-context-add-link"]');
const addIcon = (w: VueWrapper) => w.find('[data-testid="domain-context-add-icon"]');
const manageLink = (w: VueWrapper) => w.find('[data-testid="domain-context-manage-link"]');

describe('DomainContextSwitcher add/manage call-to-action', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.meta = {};
    mockRoute.params = {};
    mockRoute.matched = [];
    mockCurrentOrganization.value = { current_user_role: 'owner', extid: 'org1' };
    mockBillingEnabled.value = false;
    mockAvailableDomains.value = ['canonical.example.com'];
    mockIsContextActive.value = true;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('shows the "Add Domain" link (and no [+] icon / Manage link) when owner has no custom domains', () => {
    mockAvailableDomains.value = ['canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);

    expect(addLink(wrapper).exists()).toBe(true);
    expect(addIcon(wrapper).exists()).toBe(false);
    expect(manageLink(wrapper).exists()).toBe(false);
  });

  it('shows the [+] icon and Manage link (and no prominent Add link) when owner has a custom domain', () => {
    mockAvailableDomains.value = ['acme.example.com', 'canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);

    expect(addIcon(wrapper).exists()).toBe(true);
    expect(manageLink(wrapper).exists()).toBe(true);
    expect(addLink(wrapper).exists()).toBe(false);
  });

  it('shows no add/manage affordances for members who cannot manage domains', () => {
    mockCurrentOrganization.value = { current_user_role: 'member', extid: 'org1' };
    mockAvailableDomains.value = ['acme.example.com', 'canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);

    expect(addLink(wrapper).exists()).toBe(false);
    expect(addIcon(wrapper).exists()).toBe(false);
    expect(manageLink(wrapper).exists()).toBe(false);
  });

  it('navigates to the org-qualified add-domain page from the "Add Domain" link', async () => {
    mockAvailableDomains.value = ['canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);
    await addLink(wrapper).trigger('click');

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/add');
  });

  it('navigates to the org-qualified add-domain page from the header [+] icon', async () => {
    mockAvailableDomains.value = ['acme.example.com', 'canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);
    await addIcon(wrapper).trigger('click');

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/add');
  });
});

/**
 * Regression coverage for the "dropdown stays open after navigation" bug.
 *
 * Every navigating interaction must dismiss the menu via HeadlessUI's `close`
 * slot function. This is essential for the gear icon, whose handler calls
 * event.stopPropagation() (to avoid triggering row selection) and thereby
 * suppresses HeadlessUI's built-in MenuItem auto-close.
 */
describe('DomainContextSwitcher closes on navigation', () => {
  let wrapper: VueWrapper;

  const rowButtonFor = (w: VueWrapper, domain: string) =>
    w
      .findAll('[role="menuitem"] > button')
      .find((b) => b.text().includes(domain));

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

  it('closes the dropdown when a domain row is selected', async () => {
    wrapper = mount(DomainContextSwitcher);

    await rowButtonFor(wrapper, 'acme.example.com')!.trigger('click');

    expect(mockClose).toHaveBeenCalled();
  });

  it('closes the dropdown and navigates when the gear icon is clicked', async () => {
    wrapper = mount(DomainContextSwitcher);

    await wrapper
      .find('[aria-label="web.domains.domain_settings"]')
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith('/org/org1/domains/cd1');
    expect(mockClose).toHaveBeenCalled();
  });

  it('closes the dropdown when the header [+] icon is clicked', async () => {
    wrapper = mount(DomainContextSwitcher);

    await addIcon(wrapper).trigger('click');

    expect(mockClose).toHaveBeenCalled();
  });

  it('closes the dropdown when the "Manage Domains" link is clicked', async () => {
    wrapper = mount(DomainContextSwitcher);

    await manageLink(wrapper).trigger('click');

    expect(mockClose).toHaveBeenCalled();
  });

  it('closes the dropdown when the "Add Domain" link is clicked (no custom domains)', async () => {
    mockAvailableDomains.value = ['canonical.example.com'];

    wrapper = mount(DomainContextSwitcher);
    await addLink(wrapper).trigger('click');

    expect(mockClose).toHaveBeenCalled();
  });
});
