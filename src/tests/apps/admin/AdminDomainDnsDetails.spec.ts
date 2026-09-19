// src/tests/apps/admin/AdminDomainDnsDetails.spec.ts

import AdminDomainDnsDetails from '@/apps/admin/components/AdminDomainDnsDetails.vue';
import type {
  ColonelDomainCluster,
  ColonelDomainDetailRecord,
} from '@/schemas/api/internal/responses/colonel-domains';
import { colonelDomainClusterSchema } from '@/schemas/api/internal/responses/colonel-domains';
import { setDomainValidationStrategy } from '@tests/support/domainValidationStrategy';
import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

// The Colonel DNS panel is what an operator reads out to a customer, so its
// address record has to match the customer pages: the Approximated proxy only
// when the strategy routes through it. The proxy fields stay configured after
// a move to caddy_on_demand (the orphaned-vhost chore needs them), which is
// exactly when showing them would send a new domain to the wrong place.

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

const mockCanonicalDomain = ref('secrets.example.com');
const mockSiteHost = ref('host.example.com');

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    canonical_domain: mockCanonicalDomain,
    site_host: mockSiteHost,
  }),
}));

vi.mock('pinia', async (importOriginal) => ({
  ...(await importOriginal<typeof import('pinia')>()),
  storeToRefs: (store: Record<string, unknown>) => store,
}));

// Bootstrap-level strategy, read only when the response carries no cluster.
vi.mock('@/utils/features', async (importOriginal) => {
  const { featuresForStrategy } = await import('@tests/support/domainValidationStrategy');
  return featuresForStrategy(await importOriginal<typeof import('@/utils/features')>());
});

const PROXY_IP = '192.0.2.10';
const PROXY_HOST = 'proxy.approximated.example';

// Parsed through the real schema, as the Colonel API client does.
const cluster = (validation_strategy: string, overrides: object = {}): ColonelDomainCluster =>
  colonelDomainClusterSchema.parse({
    type: validation_strategy,
    proxy_ip: PROXY_IP,
    proxy_host: PROXY_HOST,
    proxy_name: 'proxy',
    vhost_target: 'target.example.net',
    validation_strategy,
    ...overrides,
  });

const record = (overrides: Partial<ColonelDomainDetailRecord> = {}) =>
  ({
    extid: 'dm-test-extid',
    display_domain: 'secrets.customer.example',
    base_domain: 'customer.example',
    trd: 'secrets',
    is_apex: false,
    txt_validation_host: '_onetime-challenge-abc.secrets',
    txt_validation_value: 'challenge-value',
    ...overrides,
  }) as ColonelDomainDetailRecord;

const apexRecord = () => record({ display_domain: 'customer.example', trd: '', is_apex: true });

function mountPanel(r: ColonelDomainDetailRecord, c: ColonelDomainCluster) {
  const wrapper = mount(AdminDomainDnsDetails, {
    props: { record: r, cluster: c },
    global: {
      stubs: {
        OIcon: true,
        DetailField: {
          name: 'DetailField',
          props: ['label', 'value', 'appendix'],
          template:
            '<div class="detail-field" :data-label="label" :data-value="value" :data-appendix="appendix" />',
        },
      },
    },
  });
  const step = wrapper.find('[data-testid="dns-address-step"]');
  const field = (label: string) => step.find(`[data-label="${label}"]`);
  return {
    wrapper,
    heading: wrapper.find('[data-testid="dns-address-heading"]').text(),
    type: field('web.COMMON.type').attributes('data-value'),
    host: field('web.COMMON.host').attributes('data-value'),
    appendix: field('web.COMMON.host').attributes('data-appendix'),
    target: field('web.COMMON.value').attributes('data-value'),
    apexNote: wrapper.find('[data-testid="dns-apex-note"]').exists(),
  };
}

describe('AdminDomainDnsDetails', () => {
  beforeEach(() => {
    mockCanonicalDomain.value = 'secrets.example.com';
    mockSiteHost.value = 'host.example.com';
    setDomainValidationStrategy('approximated');
  });

  it('always shows the TXT ownership record', () => {
    const { wrapper } = mountPanel(record(), cluster('caddy_on_demand'));
    const values = wrapper.findAll('.detail-field').map((f) => f.attributes('data-value'));

    expect(values).toContain('TXT');
    expect(values).toContain('_onetime-challenge-abc.secrets');
    expect(values).toContain('challenge-value');
  });

  describe('approximated', () => {
    it('points a subdomain at the proxy host with a CNAME', () => {
      const panel = mountPanel(record(), cluster('approximated'));

      expect(panel.heading).toBe('web.admin.domains.dns.cnameStep');
      expect(panel.type).toBe('CNAME');
      expect(panel.host).toBe('secrets');
      expect(panel.appendix).toBe('.customer.example');
      expect(panel.target).toBe(PROXY_HOST);
      expect(panel.apexNote).toBe(false);
    });

    it('points an apex at the proxy IP with an A record', () => {
      const panel = mountPanel(apexRecord(), cluster('approximated'));

      expect(panel.heading).toBe('web.admin.domains.dns.aStep');
      expect(panel.type).toBe('A');
      expect(panel.host).toBe('@');
      expect(panel.target).toBe(PROXY_IP);
      expect(panel.apexNote).toBe(false);
    });
  });

  // Proxy fields populated on purpose: the state right after a cutover.
  describe.each(['caddy_on_demand', 'passthrough'])('%s', (strategy) => {
    it('points a subdomain at this install with a CNAME', () => {
      const panel = mountPanel(record(), cluster(strategy));

      expect(panel.heading).toBe('web.admin.domains.dns.cnameStepInstall');
      expect(panel.type).toBe('CNAME');
      expect(panel.host).toBe('secrets');
      expect(panel.target).toBe('secrets.example.com');
    });

    it('points an apex at this install with ALIAS / ANAME and explains the alternative', () => {
      const panel = mountPanel(apexRecord(), cluster(strategy));

      expect(panel.heading).toBe('web.admin.domains.dns.aliasStepInstall');
      expect(panel.type).toBe('ALIAS / ANAME');
      expect(panel.host).toBe('@');
      expect(panel.target).toBe('secrets.example.com');
      expect(panel.apexNote).toBe(true);
    });

    it('never renders the Approximated proxy IP or host, or the proxy wording', () => {
      for (const r of [record(), apexRecord()]) {
        const { wrapper, heading } = mountPanel(r, cluster(strategy));

        expect(wrapper.html()).not.toContain(PROXY_IP);
        expect(wrapper.html()).not.toContain(PROXY_HOST);
        expect(['web.admin.domains.dns.aStep', 'web.admin.domains.dns.cnameStep']).not.toContain(
          heading
        );
      }
    });

    it('falls back to the site host when there is no canonical domain', () => {
      mockCanonicalDomain.value = '';

      expect(mountPanel(record(), cluster(strategy)).target).toBe('host.example.com');
    });
  });

  it('does not show an empty proxy value on a fresh caddy_on_demand install', () => {
    const panel = mountPanel(
      apexRecord(),
      cluster('caddy_on_demand', { proxy_ip: null, proxy_host: null })
    );

    expect(panel.target).toBe('secrets.example.com');
  });

  it('uses the bootstrap strategy when the response has no cluster', () => {
    setDomainValidationStrategy('caddy_on_demand');

    expect(mountPanel(record(), null).target).toBe('secrets.example.com');
  });

  it('keeps validation_strategy through the cluster schema', () => {
    expect(cluster('caddy_on_demand')?.validation_strategy).toBe('caddy_on_demand');
  });
});
