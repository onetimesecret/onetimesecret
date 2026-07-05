// src/tests/apps/workspace/domains/DomainDns.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import DomainDns from '@/apps/workspace/domains/DomainDns.vue';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';

const mockRouterPush = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { extid: 'dm-test-extid', orgid: 'org-123' } }),
  useRouter: () => ({
    push: mockRouterPush,
    replace: vi.fn(),
    back: vi.fn(),
  }),
}));

// Stub DomainHeader — its own behaviour is covered by DomainHeader.spec.ts.
vi.mock('@/apps/workspace/components/dashboard/DomainHeader.vue', () => ({
  default: {
    name: 'DomainHeader',
    template: '<div data-testid="domain-header" />',
    props: ['domain', 'hasUnsavedChanges', 'orgid', 'externalPath'],
  },
}));

// Stub DetailField so we can read its props without the CopyButton/clipboard.
vi.mock('@/shared/components/ui/DetailField.vue', () => ({
  default: {
    name: 'DetailField',
    template:
      '<div class="detail-field" :data-label="label" :data-value="value" :data-appendix="appendix" />',
    props: ['label', 'value', 'appendix'],
  },
}));

// Mock useDomain composable (used by DomainDns for domain data)
const mockDomain = ref<any>(null);
const mockInitialize = vi.fn();

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    initialize: mockInitialize,
  }),
}));

// Mock bootstrapStore for the canonical CNAME target
const mockCanonicalDomain = ref('secrets.example.com');
const mockSiteHost = ref('secrets.example.com');

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    canonical_domain: mockCanonicalDomain,
    site_host: mockSiteHost,
  }),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: (store: any) => ({
      canonical_domain: store.canonical_domain,
      site_host: store.site_host,
    }),
  };
});

const i18n = createTestI18n();

const createMockDomain = (overrides = {}) => ({
  extid: 'dm-test-extid',
  display_domain: 'test.example.com',
  base_domain: 'example.com',
  trd: 'test',
  is_apex: false,
  ...overrides,
});

function findFieldByLabel(wrapper: ReturnType<typeof mount>, label: string) {
  return wrapper.findAll('.detail-field').find((f) => f.attributes('data-label') === label);
}

describe('DomainDns', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockDomain.value = createMockDomain();
    mockCanonicalDomain.value = 'secrets.example.com';
    mockSiteHost.value = 'secrets.example.com';
    mockInitialize.mockResolvedValue(undefined);
  });

  const mountComponent = async () => {
    const wrapper = mount(DomainDns, {
      props: { extid: 'dm-test-extid', orgid: 'org-123' },
      global: {
        plugins: [i18n],
        stubs: { OIcon: true },
      },
    });
    await flushPromises();
    return wrapper;
  };

  it('initializes the domain on mount', async () => {
    await mountComponent();
    expect(mockInitialize).toHaveBeenCalled();
  });

  it('renders a CNAME record pointing at the canonical domain', async () => {
    const wrapper = await mountComponent();

    // Type: CNAME
    const type = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.type'));
    expect(type?.attributes('data-value')).toBe('CNAME');

    // Host: subdomain + base-domain appendix
    const host = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.host'));
    expect(host?.attributes('data-value')).toBe('test');
    expect(host?.attributes('data-appendix')).toBe('.example.com');

    // Value: the canonical domain the record must point at
    const value = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.value'));
    expect(value?.attributes('data-value')).toBe('secrets.example.com');
  });

  it('falls back to site_host when canonical_domain is empty', async () => {
    mockCanonicalDomain.value = '';
    mockSiteHost.value = 'fallback.example.com';

    const wrapper = await mountComponent();

    const value = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.value'));
    expect(value?.attributes('data-value')).toBe('fallback.example.com');
  });

  it('renders an apex-appropriate record (ALIAS/ANAME, "@" host, no leading dot) with the apex notice', async () => {
    mockDomain.value = createMockDomain({ is_apex: true, trd: null });

    const wrapper = await mountComponent();

    // Apex zones can't CNAME — type must not say "CNAME".
    const type = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.type'));
    expect(type?.attributes('data-value')).toBe('ALIAS / ANAME');

    const host = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.host'));
    expect(host?.attributes('data-value')).toBe('@');
    // No leading dot at the apex: "@" + "example.com", matching VerifyDomainDetails.
    expect(host?.attributes('data-appendix')).toBe('example.com');

    expect(wrapper.text()).toContain(i18n.global.t('web.domains.dns.apex_heading'));
    expect(wrapper.text()).toContain(i18n.global.t('web.domains.dns.apex_notice'));
  });

  it('keeps host "@" for apex even when trd is unexpectedly populated', async () => {
    mockDomain.value = createMockDomain({ is_apex: true, trd: 'ignored' });

    const wrapper = await mountComponent();

    const host = findFieldByLabel(wrapper, i18n.global.t('web.COMMON.host'));
    expect(host?.attributes('data-value')).toBe('@');
  });

  it('does not show the apex notice for non-apex domains', async () => {
    const wrapper = await mountComponent();
    expect(wrapper.text()).not.toContain(i18n.global.t('web.domains.dns.apex_notice'));
  });

  it('shows a loading message when the domain has not loaded', async () => {
    mockDomain.value = null;
    const wrapper = await mountComponent();
    expect(wrapper.text()).toContain(i18n.global.t('web.domains.loading_domain_information'));
  });
});
