// src/tests/apps/workspace/components/navigation/DomainContextSwitcher.spec.ts

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
import DomainContextSwitcher from '@/apps/workspace/components/navigation/DomainContextSwitcher.vue';

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
const mockRoute = reactive<{
  meta: Record<string, unknown>;
  params: Record<string, unknown>;
  matched: unknown[];
}>({
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
// canonical_domain drives row COPY only (the disabled-row tooltip), never row
// identity. With LINK_DOMAINS (#4063) it is not necessarily even selectable.
const mockCanonicalDomain = ref('canonical.example.com');
const mockSiteHost = ref('canonical.example.com');
const mockBootstrapStore = reactive({
  billing_enabled: mockBillingEnabled,
  canonical_domain: mockCanonicalDomain,
  site_host: mockSiteHost,
});
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => mockBootstrapStore,
}));

// --- domain context ----------------------------------------------------------
const mockAvailableDomains = ref<string[]>(['canonical.example.com']);

/**
 * Which domains carry an extid, i.e. which are registered custom domains.
 * Held as data rather than baked into the mock's implementation so a test can
 * vary it without leaving a mockImplementation behind for the next test
 * (vi.clearAllMocks clears calls, not implementations).
 */
const DEFAULT_EXTIDS: Record<string, string> = { 'acme.example.com': 'cd1' };
let mockExtids: Record<string, string> = { ...DEFAULT_EXTIDS };
const mockGetExtidByDomain = vi.fn((domain: string) => mockExtids[domain]);
const mockCurrentContext = ref({
  domain: 'canonical.example.com',
  displayName: 'canonical.example.com',
  isCanonical: true,
  extid: undefined as string | undefined,
});
const mockIsContextActive = ref(true);
const mockSetContext = vi.fn();
vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: () => ({
    currentContext: mockCurrentContext,
    availableDomains: mockAvailableDomains,
    isContextActive: mockIsContextActive,
    setContext: mockSetContext,
    getDomainDisplayName: (domain: string) => domain,
    getExtidByDomain: mockGetExtidByDomain,
    setContextByExtid: vi.fn(),
    initialized: Promise.resolve(),
  }),
}));

/** Restore every shared mock ref to its default. Called by each suite's beforeEach. */
function resetSwitcherMocks() {
  vi.clearAllMocks();
  mockRoute.meta = {};
  mockRoute.params = {};
  mockRoute.matched = [];
  mockCurrentOrganization.value = { current_user_role: 'owner', extid: 'org1' };
  mockBillingEnabled.value = false;
  mockCanonicalDomain.value = 'canonical.example.com';
  mockSiteHost.value = 'canonical.example.com';
  mockExtids = { ...DEFAULT_EXTIDS };
  mockAvailableDomains.value = ['canonical.example.com'];
  mockIsContextActive.value = true;
  mockCurrentContext.value = {
    domain: 'canonical.example.com',
    displayName: 'canonical.example.com',
    isCanonical: true,
    extid: undefined,
  };
}

const addLink = (w: VueWrapper) => w.find('[data-testid="domain-context-add-link"]');
const addIcon = (w: VueWrapper) => w.find('[data-testid="domain-context-add-icon"]');
const manageLink = (w: VueWrapper) => w.find('[data-testid="domain-context-manage-link"]');

describe('DomainContextSwitcher add/manage call-to-action', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    resetSwitcherMocks();
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

  // Select a domain row by its stable test id (keyed by extid) rather than by
  // matching rendered domain text.
  const rowButtonFor = (w: VueWrapper, extid: string) =>
    w.find(`[data-testid="domain-menu-item-${extid}"]`);

  beforeEach(() => {
    resetSwitcherMocks();
    mockAvailableDomains.value = ['acme.example.com', 'canonical.example.com'];
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('closes the dropdown when a domain row is selected', async () => {
    wrapper = mount(DomainContextSwitcher);

    await rowButtonFor(wrapper, 'cd1').trigger('click');

    expect(mockClose).toHaveBeenCalled();
  });

  it('closes the dropdown and navigates when the gear icon is clicked', async () => {
    wrapper = mount(DomainContextSwitcher);

    await wrapper.find('[aria-label="web.domains.domain_settings"]').trigger('click');

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

/**
 * Operator link pool rows (LINK_DOMAINS, #4063).
 *
 * Before #4063 exactly one row could lack an extid -- the canonical domain --
 * so the switcher keyed every extid-less row on a single 'canonical' sentinel.
 * An operator pool makes every offered domain extid-less, so that sentinel
 * collapsed the whole pool onto one id: `domainForId` resolved by search and
 * always returned the first, selecting any later pool row silently selected
 * the first, and the ScopeSwitcher `:key` went with it.
 *
 * Two id spaces now: custom domains by extid, everything else by
 * `link:${domain}`. And "has no extid" no longer implies "is canonical", which
 * is why the disabled-row tooltip had to split.
 */
describe('DomainContextSwitcher operator link pool rows', () => {
  let wrapper: VueWrapper;

  /** The install's own host: serves the app, kept out of the picker. */
  const INTERNAL_HOST = 'ge-abcd123.eu.otshosted.com';

  const rowFor = (w: VueWrapper, id: string) => w.find(`[data-testid="domain-menu-item-${id}"]`);

  beforeEach(() => {
    resetSwitcherMocks();
    // Canonical host excluded from the pool: the picker offers operator
    // domains only, none of which carries an extid.
    mockCanonicalDomain.value = INTERNAL_HOST;
    mockSiteHost.value = INTERNAL_HOST;
    mockExtids = {};
    mockAvailableDomains.value = ['a.example.com', 'b.example.com'];
    mockCurrentContext.value = {
      domain: 'a.example.com',
      displayName: 'a.example.com',
      isCanonical: false,
      extid: undefined,
    };
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('gives each extid-less pool row its own id', () => {
    wrapper = mount(DomainContextSwitcher);

    const rows = wrapper.findAll('[data-testid^="domain-menu-item-"]');
    const ids = rows.map((r) => r.attributes('data-testid'));

    expect(ids).toEqual([
      'domain-menu-item-link:a.example.com',
      'domain-menu-item-link:b.example.com',
    ]);
    expect(new Set(ids).size).toBe(rows.length);
  });

  it('selects the pool row that was clicked, not the first extid-less row', async () => {
    wrapper = mount(DomainContextSwitcher);

    await rowFor(wrapper, 'link:b.example.com').trigger('click');

    expect(mockSetContext).toHaveBeenCalledTimes(1);
    expect(mockSetContext).toHaveBeenCalledWith('b.example.com');
  });

  it('marks exactly one pool row as current', () => {
    mockCurrentContext.value = {
      domain: 'b.example.com',
      displayName: 'b.example.com',
      isCanonical: false,
      extid: undefined,
    };

    wrapper = mount(DomainContextSwitcher);

    // The checkmark renders only for item.isCurrent.
    const checks = wrapper.findAll('[data-icon="check-20-solid"]');
    expect(checks).toHaveLength(1);
    expect(
      rowFor(wrapper, 'link:b.example.com').find('[data-icon="check-20-solid"]').exists()
    ).toBe(true);
    expect(
      rowFor(wrapper, 'link:a.example.com').find('[data-icon="check-20-solid"]').exists()
    ).toBe(false);
  });

  it('explains a disabled pool row as a link domain, and the canonical row as the default', () => {
    // onDomainSwitch needs an :extid to navigate with, so every extid-less row
    // is disabled and renders its reason as the row title.
    mockRoute.meta = { scopesAvailable: { onDomainSwitch: 'same' } };
    mockCanonicalDomain.value = 'canonical.example.com';
    mockAvailableDomains.value = ['canonical.example.com', 'b.example.com'];

    wrapper = mount(DomainContextSwitcher);

    const canonicalRow = rowFor(wrapper, 'link:canonical.example.com');
    const poolRow = rowFor(wrapper, 'link:b.example.com');

    expect(canonicalRow.attributes('aria-disabled')).toBe('true');
    expect(poolRow.attributes('aria-disabled')).toBe('true');
    expect(canonicalRow.attributes('title')).toBe('web.domains.canonical_no_settings');
    // An operator link domain is not the default domain and must not say so.
    expect(poolRow.attributes('title')).toBe('web.domains.link_domain_no_settings');
  });

  it('keeps a pool domain that is also a registered custom domain on its extid id', async () => {
    // The operator listed a host a customer has also registered. The composable
    // lists it once, in its custom slot; the switcher must key it by extid so
    // it keeps its settings gear and stays navigable (not disabled).
    mockRoute.meta = { scopesAvailable: { onDomainSwitch: 'same' } };
    mockExtids = { 'acme.example.com': 'cd1' };
    mockAvailableDomains.value = ['acme.example.com', 'b.example.com'];

    wrapper = mount(DomainContextSwitcher);

    const shadowedRow = rowFor(wrapper, 'cd1');
    expect(shadowedRow.exists()).toBe(true);
    expect(rowFor(wrapper, 'link:acme.example.com').exists()).toBe(false);
    expect(shadowedRow.attributes('aria-disabled')).toBeUndefined();
    // Gear = hasSettings, which is extid presence for an owner.
    expect(shadowedRow.find('[aria-label="web.domains.domain_settings"]').exists()).toBe(true);

    await shadowedRow.trigger('click');
    expect(mockSetContext).toHaveBeenCalledWith('acme.example.com');
  });
});
